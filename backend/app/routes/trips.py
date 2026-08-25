from fastapi import APIRouter, Depends, HTTPException, status, Query, WebSocket, WebSocketDisconnect
import sqlalchemy
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import UUID
import uuid
import datetime
import asyncio

from starlette.concurrency import run_in_threadpool

from app.database import get_db
from app import models, schemas, auth, permissions
from app.services.availability import assert_bookable, is_on_sale, sale_block_reason
from app.services.sms_service import send_sms
from app.timezone_utils import SRI_LANKA_TZ, now_sl, to_sl

router = APIRouter(prefix="/trips", tags=["Trips"])


def _cancellation_sms(db: Session, origin: str, destination: str,
                      departure, paid: bool) -> str:
    """The cancellation text. Kept tight - Notify.lk bills per 160 characters."""
    dep = to_sl(departure)
    when = dep.strftime("%d/%m %I:%M%p") if dep else "your scheduled time"
    support = db.query(models.PlatformSetting).filter(
        models.PlatformSetting.key == "support_phone"
    ).first()
    support_tel = support.value if support else "0262237803"
    tail = "You will be refunded in full." if paid else "You have not been charged."

    # Long terminal names ("Bandaranaike International Airport") push the text
    # over 160 characters, which Notify.lk bills as two messages. Trim the
    # place names rather than the instruction.
    def _short(place: str, limit: int = 20) -> str:
        place = (place or "").strip()
        return place if len(place) <= limit else place[:limit - 1].rstrip() + "."

    return (
        f"SEATY: Your trip {_short(origin)} to {_short(destination)} on {when} "
        f"is CANCELLED. {tail} Support: {support_tel}"
    )

class ConnectionManager:
    def __init__(self):
        self.active_connections: dict[str, List[WebSocket]] = {}

    async def connect(self, trip_id: str, websocket: WebSocket):
        await websocket.accept()
        if trip_id not in self.active_connections:
            self.active_connections[trip_id] = []
        self.active_connections[trip_id].append(websocket)

    def disconnect(self, trip_id: str, websocket: WebSocket):
        if trip_id in self.active_connections:
            if websocket in self.active_connections[trip_id]:
                self.active_connections[trip_id].remove(websocket)
            if not self.active_connections[trip_id]:
                del self.active_connections[trip_id]

    async def broadcast(self, trip_id: str, message: dict):
        if trip_id in self.active_connections:
            disconnected = []
            for connection in self.active_connections[trip_id]:
                try:
                    await connection.send_json(message)
                except Exception:
                    disconnected.append(connection)
            for conn in disconnected:
                self.disconnect(trip_id, conn)

manager = ConnectionManager()

def notify_seat_change(trip_id: str, event_type: str, seats: list, genders: dict = None):
    """Broadcast real-time seat holds, releases, or bookings to active WebSocket viewers."""
    try:
        loop = asyncio.get_event_loop()
        if loop.is_running():
            loop.create_task(manager.broadcast(str(trip_id), {
                "event": event_type,
                "seats": seats,
                "genders": genders or {}
            }))
    except Exception as e:
        print(f"Error broadcasting WS seat update: {e}")

@router.post("", response_model=schemas.TripResponse, status_code=status.HTTP_201_CREATED)
def create_trip(
    trip_in: schemas.TripCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(list(permissions.MANAGER_ROLES)))
):
    # Scoping first: an owner may only ever touch their own company's vehicles.
    vehicle = permissions.require_vehicle(db, current_user, trip_in.vehicle_id)
    if not vehicle.is_verified:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You cannot schedule trips for an unverified vehicle."
        )

    # Verify route exists
    route = db.query(models.Route).filter(models.Route.id == trip_in.route_id).first()
    if not route:
        raise HTTPException(status_code=404, detail="Route not found")

    cond_id = None
    if trip_in.conductor_id:
        cond_id = permissions.require_conductor(db, current_user, trip_in.conductor_id).id

    db_trip = models.Trip(
        id=uuid.uuid4(),
        vehicle_id=trip_in.vehicle_id,
        route_id=trip_in.route_id,
        departure_time=to_sl(trip_in.departure_time),
        arrival_time=to_sl(trip_in.arrival_time),
        price_per_seat=trip_in.price_per_seat,
        status="scheduled",
        conductor_id=cond_id
    )
    db.add(db_trip)
    db.commit()
    db.refresh(db_trip)
    return db_trip

@router.get("", response_model=List[schemas.TripResponse])
def list_trips(
    origin: Optional[str] = Query(None, description="Start terminal location"),
    destination: Optional[str] = Query(None, description="End terminal location"),
    date: Optional[str] = Query(None, description="Trip date in YYYY-MM-DD format"),
    db: Session = Depends(get_db),
    current_user: Optional[models.User] = Depends(auth.get_optional_current_user)
):
    query = db.query(models.Trip).join(models.Route).join(models.Vehicle)

    # Staff (conductor/owner/admin) operate a trip through its whole journey, so
    # they get looser visibility rules than passengers browsing for a seat.
    is_staff = current_user is not None and current_user.role in ("conductor", "owner", "admin")

    if current_user:
        if current_user.role == "owner":
            query = query.filter(models.Vehicle.company_id == current_user.company_id)
        elif current_user.role == "conductor":
            query = query.filter(models.Trip.conductor_id == current_user.id)

    # Filter by date
    if date:
        try:
            target_date = datetime.datetime.strptime(date, "%Y-%m-%d").date()
            start_time = datetime.datetime.combine(target_date, datetime.time.min, tzinfo=SRI_LANKA_TZ)
            end_time = datetime.datetime.combine(target_date, datetime.time.max, tzinfo=SRI_LANKA_TZ)
            
            # Generate trips from active schedules if date is within next 5 days
            today = datetime.date.today()
            max_future_date = today + datetime.timedelta(days=5)
            
            if today <= target_date <= max_future_date:
                sched_query = db.query(models.TripSchedule).filter(
                    models.TripSchedule.is_active == True,
                    models.TripSchedule.effective_from <= target_date
                )
                sched_query = sched_query.filter(
                    (models.TripSchedule.effective_until == None) | (models.TripSchedule.effective_until >= target_date)
                )
                
                # If owner or conductor, filter schedules by their company
                if current_user and current_user.role in ["owner", "conductor"]:
                    sched_query = sched_query.join(models.Vehicle).filter(
                        models.Vehicle.company_id == current_user.company_id
                    )
                    
                schedules = sched_query.all()
                weekday = target_date.weekday()  # 0=Mon, 6=Sun
                
                for sched in schedules:
                    match = False
                    if sched.schedule_type == "daily":
                        match = True
                    elif sched.schedule_type == "weekdays":
                        match = weekday < 5
                    elif sched.schedule_type == "weekends":
                        match = weekday >= 5
                    elif sched.schedule_type == "custom":
                        match = weekday in (sched.custom_days or [])
                        
                    if match:
                        # Check if trip already exists for this schedule and target date
                        existing_trip = db.query(models.Trip).filter(
                            models.Trip.schedule_id == sched.id,
                            models.Trip.departure_time >= start_time,
                            models.Trip.departure_time <= end_time
                        ).first()
                        
                        if not existing_trip:
                            # Check for a bus override
                            override = db.query(models.BusOverride).filter(
                                models.BusOverride.schedule_id == sched.id,
                                models.BusOverride.override_date == target_date
                            ).first()
                            
                            veh_id = override.replacement_vehicle_id if override else sched.vehicle_id
                            
                            # Construct departure/arrival times (schedule times are Sri Lanka wall-clock)
                            dep_time = datetime.datetime.combine(target_date, sched.departure_time, tzinfo=SRI_LANKA_TZ)
                            if sched.arrival_time < sched.departure_time:
                                arr_time = datetime.datetime.combine(target_date + datetime.timedelta(days=1), sched.arrival_time, tzinfo=SRI_LANKA_TZ)
                            else:
                                arr_time = datetime.datetime.combine(target_date, sched.arrival_time, tzinfo=SRI_LANKA_TZ)
                                
                            new_trip = models.Trip(
                                id=uuid.uuid4(),
                                vehicle_id=veh_id,
                                route_id=sched.route_id,
                                schedule_id=sched.id,
                                departure_time=dep_time,
                                arrival_time=arr_time,
                                price_per_seat=sched.price_per_seat,
                                status="scheduled",
                                conductor_id=sched.conductor_id
                            )
                            db.add(new_trip)
                            db.commit()
            
            same_day = sqlalchemy.and_(
                models.Trip.departure_time >= start_time,
                models.Trip.departure_time <= end_time
            )

            if is_staff:
                # An overnight run (e.g. 23:00 -> 05:00) departs on the previous
                # calendar day, so a plain departure-date window loses it the
                # moment midnight passes - while the conductor is still driving
                # it. Keep any journey that is currently under way.
                now_for_query = now_sl()
                in_progress = sqlalchemy.and_(
                    models.Trip.departure_time <= now_for_query,
                    models.Trip.arrival_time >= now_for_query
                )
                query = query.filter(sqlalchemy.or_(same_day, in_progress))
            else:
                query = query.filter(same_day)
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid date format. Use YYYY-MM-DD"
            )
            
    trips = query.order_by(models.Trip.departure_time.asc()).all()
    
    # Preload nested structures and filter matching routes (including intermediate stops)
    filtered_trips = []
    now_sri_lanka = now_sl()

    # The 30-minute cutoff is a passenger *booking* rule, not a visibility rule.
    # Conductors/owners must keep seeing the trip once it enters the boarding
    # window - that is exactly when they need the manifest and scanner.
    #
    # Passengers, including ticket holders, must NOT see it here: this list
    # feeds the home search results, and a bus departing in under 30 minutes is
    # no longer bookable. Live tracking of an already-booked trip is served by
    # `GET /trips/my-active` instead, so the two concerns stay separate.
    for trip in trips:
        dep_time = to_sl(trip.departure_time)
        # Hide trips departing within 30 minutes from passengers only
        if not is_staff and dep_time <= (now_sri_lanka + datetime.timedelta(minutes=30)):
            continue

        trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()

        # The temporary off switch, and every other reason a seat cannot be
        # sold. Passengers must not see the trip at all - showing a bus that
        # rejects the booking at the last step is worse than not listing it.
        # Staff keep seeing it, flagged, because switching it back on is done
        # from this same list.
        trip.sale_blocked_reason = sale_block_reason(db, trip, vehicle=trip.vehicle)
        if trip.sale_blocked_reason is not None and not is_staff:
            continue

        if trip.vehicle:
            v_reviews = db.query(models.Review).filter(models.Review.vehicle_id == trip.vehicle.id).all()
            if v_reviews:
                trip.vehicle.average_rating = round(sum(r.rating for r in v_reviews) / len(v_reviews), 1)
            else:
                trip.vehicle.average_rating = None
        trip.route = db.query(models.Route).filter(models.Route.id == trip.route_id).first()
        trip.conductor = db.query(models.User).filter(models.User.id == trip.conductor_id).first()
        
        # Compute confirmed booked seats
        confirmed_b = db.query(models.Booking).filter(
            models.Booking.trip_id == trip.id,
            models.Booking.booking_status.in_(models.OCCUPIED_BOOKING_STATUSES)
        ).all()
        b_seats = set()
        for cb in confirmed_b:
            if cb.selected_seats:
                b_seats.update(cb.selected_seats)
        
        # Filter against vehicle valid seat layout if present
        if trip.vehicle and trip.vehicle.seat_layout and "seats" in trip.vehicle.seat_layout:
            valid_labels = set(str(s["label"]) for s in trip.vehicle.seat_layout["seats"] if isinstance(s, dict) and "label" in s)
            b_seats = b_seats.intersection(valid_labels)
            
        trip.booked_seats = list(b_seats)
        
        # Verify route match with intermediate stops
        if trip.route:
            match = True
            
            # Helper to find position of a location in route stops (-1 = origin, index = stop index, 100000 = destination)
            def find_stop_position(search_loc: str) -> Optional[int]:
                search_normalized = search_loc.lower().strip()
                if search_normalized in trip.route.origin.lower():
                    return -1
                
                # Check intermediate stops
                stops = trip.route.stops or []
                for idx, stop in enumerate(stops):
                    if search_normalized in stop.get("name", "").lower():
                        return idx
                
                if search_normalized in trip.route.destination.lower():
                    return 100000
                return None

            if origin:
                origin_pos = find_stop_position(origin)
                if origin_pos is None:
                    match = False
                
            if destination:
                dest_pos = find_stop_position(destination)
                if dest_pos is None:
                    match = False
                
            # If both are specified, ensure origin comes before destination
            if origin and destination and match:
                o_pos = find_stop_position(origin)
                d_pos = find_stop_position(destination)
                if o_pos is not None and d_pos is not None and o_pos >= d_pos:
                    match = False
                    
            if match:
                filtered_trips.append(trip)
        else:
            # If no route exists (should not happen), keep it if no filters are specified
            if not origin and not destination:
                filtered_trips.append(trip)
                
    return filtered_trips

@router.get("/my-active", response_model=List[schemas.TripResponse])
def list_my_active_trips(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    """Trips the caller holds a confirmed ticket for that are trackable right now.

    Deliberately separate from `GET /trips`: that endpoint feeds home-screen
    search and must keep hiding buses departing within 30 minutes, because they
    can no longer be booked. This one powers live tracking, where the passenger
    needs the very trip that search is hiding. Declared above `/{trip_id}` so
    the literal path is not swallowed as a UUID parameter.
    """
    now = now_sl()

    bookings = db.query(models.Booking).filter(
        models.Booking.passenger_id == current_user.id,
        models.Booking.booking_status.in_(["confirmed", "completed"]),
    ).all()

    trip_ids = {b.trip_id for b in bookings if b.trip_id}
    if not trip_ids:
        return []

    trips = db.query(models.Trip).filter(models.Trip.id.in_(trip_ids)).all()

    active = []
    for trip in trips:
        dep_time = to_sl(trip.departure_time)
        arr_time = to_sl(trip.arrival_time)
        if dep_time is None or arr_time is None:
            continue

        # Same window the driver broadcasts in: boarding open through arrival.
        if now < (dep_time - datetime.timedelta(minutes=30)) or now > arr_time:
            continue

        trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
        trip.route = db.query(models.Route).filter(models.Route.id == trip.route_id).first()
        trip.conductor = db.query(models.User).filter(models.User.id == trip.conductor_id).first()
        active.append(trip)

    active.sort(key=lambda t: t.departure_time)
    return active


@router.get("/{trip_id}", response_model=schemas.TripResponse)
def get_trip(trip_id: UUID, db: Session = Depends(get_db)):
    trip = db.query(models.Trip).filter(models.Trip.id == trip_id).first()
    if not trip:
        raise HTTPException(status_code=404, detail="Trip not found")
        
    trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
    if trip.vehicle:
        v_reviews = db.query(models.Review).filter(models.Review.vehicle_id == trip.vehicle.id).all()
        if v_reviews:
            trip.vehicle.average_rating = round(sum(r.rating for r in v_reviews) / len(v_reviews), 1)
        else:
            trip.vehicle.average_rating = None
    trip.route = db.query(models.Route).filter(models.Route.id == trip.route_id).first()
    trip.conductor = db.query(models.User).filter(models.User.id == trip.conductor_id).first()
    
    confirmed_b = db.query(models.Booking).filter(
        models.Booking.trip_id == trip.id,
        models.Booking.booking_status.in_(models.OCCUPIED_BOOKING_STATUSES)
    ).all()
    b_seats = set()
    for cb in confirmed_b:
        if cb.selected_seats:
            b_seats.update(cb.selected_seats)
    trip.booked_seats = list(b_seats)
    return trip

@router.patch("/{trip_id}/status", response_model=schemas.TripResponse)
async def update_trip_status(
    trip_id: UUID, 
    status: str = Query(..., description="scheduled, ongoing, completed, cancelled"), 
    db: Session = Depends(get_db), 
    current_user: models.User = Depends(auth.RoleChecker(["owner", "admin", "conductor"]))
):
    trip = permissions.require_operable_trip(db, current_user, trip_id)

    if status not in ["scheduled", "ongoing", "completed", "cancelled"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid status type."
        )

    # A conductor runs the trip they were assigned; they do not cancel it.
    # Cancelling voids every booking on the bus and puts paid passengers into
    # the refund queue, so it stays with the people who answer for the money.
    if current_user.role == "conductor" and status in ("cancelled", "scheduled"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the operator or an administrator can cancel or reopen a trip."
        )


    old_status = trip.status
    trip.status = status
    db.commit()
    db.refresh(trip)

    # An operator cancelling a trip is the one case that earns a refund.
    # Passenger-initiated cancellations do not - bookings are sold
    # non-refundable - but a passenger who did nothing wrong and lost their bus
    # is owed their money back.
    #
    # There is no refund call in the gateway (docs/AUDIT.md B4), so this cannot
    # move money. What it can do is stop the trip's tickets looking valid, and
    # put every affected payment into a queue a human can work, instead of the
    # notification that used to promise "a refund has been initiated" while
    # nothing was initiated and the bookings stayed confirmed on a dead trip.
    refunds_due = []
    affected = []
    if status == "cancelled" and old_status != "cancelled":
        # Everyone holding a booking on this bus, not only the ones who have
        # already paid. A passenger sitting on the card page ("pending" /
        # "awaiting_payment") is the one who most needs to hear this: left
        # alone they will finish paying for a bus that is not running.
        affected = db.query(models.Booking).filter(
            models.Booking.trip_id == trip.id,
            models.Booking.booking_status.notin_(["cancelled", "expired"]),
        ).all()
        for b in affected:
            b.booking_status = "cancelled"
            if b.payment_status in ("pending", "awaiting_payment"):
                # No money has moved, so nothing to refund - just make sure the
                # session cannot be completed later.
                b.payment_status = "failed"
            if b.payment_status == "paid":
                # payment_status stays "paid": the money is still ours until
                # somebody actually sends it back. "refunded" would be a lie.
                for pay in db.query(models.Payment).filter(
                    models.Payment.booking_id == b.id,
                    models.Payment.status == "completed",
                ).all():
                    pay.gateway_response = {
                        **(pay.gateway_response or {}),
                        "refund_due": True,
                        "refund_reason": "trip cancelled by operator",
                        "refund_flagged_at": datetime.datetime.now(
                            datetime.timezone.utc).isoformat(),
                    }
                    refunds_due.append((b, pay))

        db.query(models.SeatHold).filter(
            models.SeatHold.trip_id == trip.id,
            models.SeatHold.is_released == False,
        ).update({"is_released": True})
        db.commit()
    
    # Notify passengers if status goes from scheduled -> ongoing / cancelled
    if status != old_status and status in ["ongoing", "cancelled"]:
        # For a cancellation the bookings were just moved to "cancelled" above,
        # so re-querying for confirmed ones would find nobody to tell. Use the
        # list captured before the mutation.
        if status == "cancelled":
            bookings = affected
        else:
            bookings = db.query(models.Booking).filter(
                models.Booking.trip_id == trip.id,
                models.Booking.booking_status == "confirmed"
            ).all()
        sms_jobs = {}
        for b in bookings:
            try:
                from app.routes.notifications import create_and_send_notification
                route = db.query(models.Route).filter(models.Route.id == trip.route_id).first()
                origin = route.origin if route else "Origin"
                destination = route.destination if route else "Destination"
                date_str = to_sl(trip.departure_time).strftime("%Y-%m-%d %H:%M")

                title = f"Trip {status.capitalize()}!"
                if status == "cancelled":
                    if b.payment_status == "paid":
                        msg = (
                            f"Your trip from {origin} to {destination} scheduled for "
                            f"{date_str} has been cancelled by the operator. You will "
                            f"be refunded in full - our team will contact you shortly."
                        )
                    else:
                        msg = (
                            f"Your trip from {origin} to {destination} scheduled for "
                            f"{date_str} has been cancelled by the operator, so your "
                            f"booking could not be completed. You have not been "
                            f"charged. Please choose another bus."
                        )
                    noti_type = "trip_cancelled"
                else: # ongoing
                    msg = f"Your trip from {origin} to {destination} is now active (ongoing)! Safe travels."
                    noti_type = "trip_ongoing"

                await create_and_send_notification(
                    db=db,
                    user_id=b.passenger_id,
                    title=title,
                    message=msg,
                    noti_type=noti_type,
                    booking_id=b.id
                )

                # A cancellation is the one message a passenger cannot afford to
                # miss - push and in-app both depend on the app being installed,
                # permitted and online, and none of that is true of somebody
                # already on their way to the halt. Keyed by number so a
                # passenger with two bookings on the same bus gets one text.
                if status == "cancelled":
                    phone = None
                    passenger = db.query(models.User).filter(
                        models.User.id == b.passenger_id
                    ).first()
                    if passenger and passenger.phone_number:
                        phone = passenger.phone_number.strip()
                    if not phone:
                        primary = (b.passenger_details or {}).get("primary", {})
                        phone = (primary.get("phone") or "").strip() or None
                    if phone:
                        sms_jobs[phone] = _cancellation_sms(
                            db, origin, destination, trip.departure_time,
                            paid=(b.payment_status == "paid"),
                        )
            except Exception as noti_err:
                print(f"Notification Error: {noti_err}")

        # Sent after the loop and all at once. Notify.lk is a blocking HTTP
        # call of roughly a second; a full 40-seat bus done one at a time would
        # hold this request - and the event loop's threadpool - for the best
        # part of a minute.
        if sms_jobs:
            results = await asyncio.gather(
                *(run_in_threadpool(send_sms, phone, text)
                  for phone, text in sms_jobs.items()),
                return_exceptions=True,
            )
            failed = sum(1 for r in results
                         if isinstance(r, Exception) or not (r and r[0]))
            print(f"[trip-cancelled] SMS: {len(sms_jobs) - failed}/{len(sms_jobs)} accepted"
                  + (f", {failed} rejected" if failed else ""))

    if refunds_due:
        total = sum(float(p.amount or 0) for _, p in refunds_due)
        try:
            from app.routes.notifications import create_and_send_notification
            for admin in db.query(models.User).filter(models.User.role == "admin").all():
                await create_and_send_notification(
                    db=db,
                    user_id=admin.id,
                    title="Refunds owed - trip cancelled",
                    message=(
                        f"{len(refunds_due)} paid booking(s) totalling LKR {total:,.2f} "
                        f"were cancelled with the trip on "
                        f"{to_sl(trip.departure_time).strftime('%Y-%m-%d %H:%M')}. "
                        f"See GET /payments/refunds/pending."
                    ),
                    noti_type="system",
                )
        except Exception as noti_err:
            print(f"Notification Error: {noti_err}")

    trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
    trip.route = db.query(models.Route).filter(models.Route.id == trip.route_id).first()
    return trip


@router.patch("/{trip_id}/booking", response_model=schemas.TripResponse)
def set_trip_booking_enabled(
    trip_id: UUID,
    body: schemas.BookingToggle,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(list(permissions.MANAGER_ROLES)))
):
    """Temporarily take this one trip off sale, or put it back on.

    Reversible and non-destructive - the opposite of `PATCH /{trip_id}/status`
    with `cancelled`. Existing bookings are untouched and the passengers who
    hold them keep their tickets and their live tracking; the trip simply stops
    appearing in passenger search and stops accepting new seats until it is
    switched back on.

    Use this for "the bus is in the garage this morning, we'll know by noon".
    Use cancel for "this bus is not running, refund everyone".
    """
    trip = permissions.require_trip(db, current_user, trip_id)

    if trip.status in ("cancelled", "completed"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"This trip is already {trip.status}; the booking switch no longer applies.",
        )

    trip.booking_enabled = body.enabled
    trip.suspension_reason = None if body.enabled else (body.reason or None)
    trip.updated_at = datetime.datetime.utcnow()
    db.commit()
    db.refresh(trip)

    # Seats held for a trip that just went off sale would otherwise sit blocked
    # until they expire, and the hold cannot be converted into a booking any
    # more anyway. Release them so the seat map is honest when it comes back on.
    if not body.enabled:
        db.query(models.SeatHold).filter(
            models.SeatHold.trip_id == trip.id,
            models.SeatHold.is_released == False,
        ).update({"is_released": True})
        db.commit()
        notify_seat_change(str(trip.id), "SEAT_RELEASED", [])

    trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
    trip.route = db.query(models.Route).filter(models.Route.id == trip.route_id).first()
    trip.conductor = db.query(models.User).filter(models.User.id == trip.conductor_id).first()
    trip.sale_blocked_reason = sale_block_reason(db, trip, vehicle=trip.vehicle)
    return trip


@router.put("/{trip_id}", response_model=schemas.TripResponse)
async def update_trip(
    trip_id: UUID,
    trip_in: schemas.TripCreate,
    db: Session = Depends(get_db),
    # Every ownership check here used to be nested under
    # `if role in ["owner", "conductor"]`, so with a bare get_current_user a
    # passenger fell through to the mutations and could rewrite any trip -
    # including price_per_seat, which is what create_booking then charges.
    # See docs/SECURITY.md #24.
    current_user: models.User = Depends(auth.RoleChecker(list(permissions.MANAGER_ROLES)))
):
    # Both the trip being edited and the vehicle it is being moved onto must
    # belong to the caller - checking only one lets an owner reassign their own
    # trip onto someone else's bus, or someone else's trip onto their own.
    trip = permissions.require_trip(db, current_user, trip_id)
    new_vehicle = permissions.require_vehicle(db, current_user, trip_in.vehicle_id)
    if not new_vehicle.is_verified:
        raise HTTPException(status_code=400, detail="You cannot schedule trips for an unverified vehicle.")

    # Verify route exists
    route = db.query(models.Route).filter(models.Route.id == trip_in.route_id).first()
    if not route:
        raise HTTPException(status_code=404, detail="Route not found")

    if trip_in.conductor_id is not None:
        trip.conductor_id = permissions.require_conductor(db, current_user, trip_in.conductor_id).id
    else:
        trip.conductor_id = None

    old_dep_time = trip.departure_time
    trip.vehicle_id = trip_in.vehicle_id
    trip.route_id = trip_in.route_id
    trip.departure_time = to_sl(trip_in.departure_time)
    trip.arrival_time = to_sl(trip_in.arrival_time)
    trip.price_per_seat = trip_in.price_per_seat
    
    db.commit()
    db.refresh(trip)
    
    # Notify if departure time rescheduled
    if old_dep_time != trip.departure_time:
        bookings = db.query(models.Booking).filter(
            models.Booking.trip_id == trip.id,
            models.Booking.booking_status == "confirmed"
        ).all()
        for b in bookings:
            try:
                from app.routes.notifications import create_and_send_notification
                origin = route.origin
                destination = route.destination
                new_date_str = to_sl(trip.departure_time).strftime("%Y-%m-%d %H:%M")
                
                await create_and_send_notification(
                    db=db,
                    user_id=b.passenger_id,
                    title="Trip Rescheduled!",
                    message=f"Your trip from {origin} to {destination} has been rescheduled. New departure time: {new_date_str}.",
                    noti_type="trip_rescheduled",
                    booking_id=b.id
                )
            except Exception as noti_err:
                print(f"Notification Error: {noti_err}")
                
    trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
    trip.route = db.query(models.Route).filter(models.Route.id == trip.route_id).first()
    return trip

@router.delete("/{trip_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_trip(
    trip_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(list(permissions.MANAGER_ROLES)))
):
    """Hard-delete a trip. Only for trips nobody has paid for.

    `bookings.trip_id` and `payments.booking_id` both cascade, so deleting a
    trip with paid bookings destroys the payment rows the money is reconciled
    against and tells nobody. Cancel it instead: `PATCH /{trip_id}/status` with
    `cancelled` voids the tickets, notifies every passenger, and queues the
    refunds.
    """
    trip = permissions.require_trip(db, current_user, trip_id)

    paid = db.query(models.Booking).filter(
        models.Booking.trip_id == trip.id,
        models.Booking.payment_status == "paid",
        models.Booking.booking_status.notin_(["cancelled", "expired"]),
    ).count()
    if paid:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"This trip has {paid} paid booking(s) and cannot be deleted. "
                f"Cancel the trip instead so passengers are notified and refunded."
            ),
        )


    db.delete(trip)
    db.commit()
    return {}

@router.get("/{trip_id}/manifest")
def get_trip_manifest(
    trip_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin", "owner", "conductor"]))
):
    """Get a detailed manifest of passengers for a specific trip, used by conductors.

    Scoped, not merely role-gated: the manifest is passenger names, genders and
    phone numbers. Role gating alone let any conductor on the platform read any
    other company's passenger list by trip id.
    """
    trip = permissions.require_operable_trip(db, current_user, trip_id)

    bookings = db.query(models.Booking).filter(
        models.Booking.trip_id == trip_id,
        models.Booking.booking_status.in_(models.OCCUPIED_BOOKING_STATUSES)
    ).all()
    
    manifest = []
    
    for b in bookings:
        details = b.passenger_details or {}
        primary = details.get("primary", {})
        guests = details.get("guests", [])
        
        # Determine seats for primary and guests
        seats = b.selected_seats or []
        if not seats:
            continue
            
        primary_seat = seats[0]
        manifest.append({
            "seat": primary_seat,
            "name": primary.get("name", "Unknown"),
            "gender": primary.get("gender", "Male").lower(),
            "phone": primary.get("phone", ""),
            "booking_id": str(b.id)
        })
        
        # For guests, we need to handle both case where guest has explicit seat or not
        for i, guest in enumerate(guests):
            if i + 1 < len(seats):
                g_seat = guest.get("seat", seats[i + 1])
                manifest.append({
                    "seat": g_seat,
                    "name": guest.get("name", "Guest"),
                    "gender": guest.get("gender", "Female").lower(),
                    "phone": guest.get("phone", ""),
                    "booking_id": str(b.id)
                })

    return {
        "trip_id": str(trip.id),
        "boarded_seats": trip.boarded_seats,
        "manifest": manifest
    }

@router.post("/{trip_id}/toggle-board")
def toggle_seat_board_status(
    trip_id: UUID,
    seat: str,
    action: Optional[str] = Query(None, description="board, unboard, toggle"),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin", "owner", "conductor"]))
):
    """Toggle or set the boarding status of a specific seat."""
    trip = permissions.require_operable_trip(db, current_user, trip_id)

    boarded = list(trip.boarded_seats)
    
    # Resolve action if not specified
    if not action:
        action = "unboard" if seat in boarded else "board"
        
    if action == "board":
        # 30-minute validation check
        now = now_sl()
        dep_time = to_sl(trip.departure_time)
        earliest_boarding_time = dep_time - datetime.timedelta(minutes=30)
        if now < earliest_boarding_time:
            minutes_until_boarding = int((earliest_boarding_time - now).total_seconds() / 60)
            departure_str = dep_time.strftime("%Y-%m-%d %H:%M")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Boarding is only allowed within 30 minutes of the ride. Departure is in {minutes_until_boarding} minutes (at {departure_str})."
            )
            
        if seat not in boarded:
            boarded.append(seat)
        final_action = "boarded"
    elif action == "unboard":
        if seat in boarded:
            boarded.remove(seat)
        final_action = "unboarded"
    else:  # toggle
        if seat in boarded:
            boarded.remove(seat)
            final_action = "unboarded"
        else:
            # Enforce 30-minute check for boarding inside toggle
            now = now_sl()
            dep_time = to_sl(trip.departure_time)
            earliest_boarding_time = dep_time - datetime.timedelta(minutes=30)
            if now < earliest_boarding_time:
                minutes_until_boarding = int((earliest_boarding_time - now).total_seconds() / 60)
                departure_str = dep_time.strftime("%Y-%m-%d %H:%M")
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Boarding is only allowed within 30 minutes of the ride. Departure is in {minutes_until_boarding} minutes (at {departure_str})."
                )
            boarded.append(seat)
            final_action = "boarded"
        
    trip.boarded_seats = boarded
    # Auto-update bookings for this trip to completed if all seats are boarded
    trip_bookings = db.query(models.Booking).filter(models.Booking.trip_id == trip.id).all()
    boarded_set = set(boarded)
    for b in trip_bookings:
        seats_set = set(b.selected_seats or [])
        if seats_set and seats_set.issubset(boarded_set):
            b.booking_status = "completed"
    db.commit()
    
    return {"message": f"Seat {seat} marked as {final_action}", "boarded_seats": boarded}

@router.websocket("/ws/{trip_id}")
async def websocket_trip_seats(websocket: WebSocket, trip_id: str):
    """Real-time WebSocket endpoint broadcasting seat holds, releases, and bookings to all active viewers."""
    await manager.connect(str(trip_id), websocket)
    try:
        while True:
            # Maintain active connection and listen for ping/heartbeats
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(str(trip_id), websocket)
    except Exception:
        manager.disconnect(str(trip_id), websocket)
