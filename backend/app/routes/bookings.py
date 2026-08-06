from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import UUID
import uuid
import datetime

from app.database import get_db
from app import models, schemas, auth
from app.routes.seat_holds import get_unavailable_seats
from app.routes.trips import notify_seat_change

router = APIRouter(prefix="/bookings", tags=["Bookings"])


def _get_platform_fee(db: Session, subtotal: float) -> float:
    """Calculate platform fee from settings."""
    pct_setting = db.query(models.PlatformSetting).filter(
        models.PlatformSetting.key == "commission_percentage"
    ).first()
    fixed_setting = db.query(models.PlatformSetting).filter(
        models.PlatformSetting.key == "commission_fixed_fee"
    ).first()
    pct = float(pct_setting.value) if pct_setting else 3.0
    fixed = float(fixed_setting.value) if fixed_setting else 25.0
    return round((subtotal * pct / 100) + fixed, 2)


@router.post("", response_model=schemas.BookingResponse, status_code=status.HTTP_201_CREATED)
def create_booking(
    booking_in: schemas.BookingCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["passenger", "admin"]))
):
    """
    Create a new booking.
    Checks seat availability against both confirmed bookings AND active holds.
    Booking starts as 'pending' until payment is completed.
    """
    if not booking_in.selected_seats or len(booking_in.selected_seats) > 6:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You can book a maximum of 6 seats per booking session."
        )

    # Verify trip exists
    trip = db.query(models.Trip).filter(models.Trip.id == booking_in.trip_id).first()
    if not trip:
        raise HTTPException(status_code=404, detail="Scheduled trip not found")

    if trip.status in ["completed", "cancelled"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Cannot book seats on a trip that is already {trip.status}."
        )

    # 30-minute pre-departure cutoff validation
    now = datetime.datetime.now(datetime.timezone.utc)
    dep_time = trip.departure_time
    if dep_time.tzinfo is None:
        dep_time = dep_time.replace(tzinfo=datetime.timezone.utc)
    if now >= (dep_time - datetime.timedelta(minutes=30)):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Online booking for this bus closed 30 minutes prior to departure."
        )

    # Check seat availability (booked + held seats)
    unavailable = get_unavailable_seats(db, booking_in.trip_id)
    all_unavailable = set(unavailable["booked"]) | set(unavailable["held"])

    # Allow re-booking seats the user already holds
    user_holds = db.query(models.SeatHold).filter(
        models.SeatHold.trip_id == booking_in.trip_id,
        models.SeatHold.user_id == current_user.id,
        models.SeatHold.is_released == False,
        models.SeatHold.expires_at > datetime.datetime.utcnow()
    ).all()
    user_held_seats = set()
    for h in user_holds:
        user_held_seats.update(h.seat_labels)

    # Seats that are truly blocked for this user
    blocked_for_user = all_unavailable - user_held_seats
    overlap = blocked_for_user.intersection(booking_in.selected_seats)

    if overlap:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Seats {list(overlap)} are already booked or held by another user."
        )

    # Calculate total price and platform fee
    subtotal = float(trip.price_per_seat) * len(booking_in.selected_seats)
    platform_fee = _get_platform_fee(db, subtotal)

    db_booking = models.Booking(
        id=uuid.uuid4(),
        trip_id=booking_in.trip_id,
        passenger_id=current_user.id,
        selected_seats=booking_in.selected_seats,
        total_price=subtotal,
        platform_fee=platform_fee,
        payment_status="pending",
        booking_status="pending",  # Starts as pending until payment
        passenger_details=booking_in.passenger_details
    )
    db.add(db_booking)
    db.commit()
    db.refresh(db_booking)

    notify_seat_change(str(booking_in.trip_id), "SEAT_HELD", booking_in.selected_seats)

    # Preload details for response
    db_booking.trip = trip
    db_booking.passenger = current_user
    db_booking.trip.route = db.query(models.Route).filter(models.Route.id == trip.route_id).first()
    db_booking.trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
    return db_booking


def _get_hold_duration(db: Session) -> int:
    setting = db.query(models.PlatformSetting).filter(
        models.PlatformSetting.key == "seat_hold_duration_minutes"
    ).first()
    return int(setting.value) if setting else 10


def _auto_update_booking_statuses(db: Session, bookings: List[models.Booking]):
    """Auto-update booking_status to 'completed' or 'expired' based on departure time, boarding status, and hold timeout."""
    now = datetime.datetime.now(datetime.timezone.utc)
    hold_duration_mins = _get_hold_duration(db)
    updated = False
    for b in bookings:
        if not b.trip or not b.trip.departure_time:
            continue
        dep_time = b.trip.departure_time
        if dep_time.tzinfo is None:
            dep_time = dep_time.replace(tzinfo=datetime.timezone.utc)
        
        boarded = set(b.trip.boarded_seats or [])
        seats = set(b.selected_seats or [])
        is_boarded = len(seats) > 0 and seats.issubset(boarded)
        
        # Check creation time for pending booking expiration
        created_at = b.created_at
        if created_at and created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=datetime.timezone.utc)
        is_pending_expired = (
            b.booking_status == "pending"
            and b.payment_status != "paid"
            and created_at
            and (now - created_at).total_seconds() > (hold_duration_mins * 60)
        )
        
        if is_boarded or b.booking_status == "completed":
            if b.booking_status != "completed":
                b.booking_status = "completed"
                updated = True
        elif dep_time < now and b.booking_status in ["confirmed", "pending"]:
            b.booking_status = "expired"
            updated = True
        elif is_pending_expired:
            b.booking_status = "expired"
            b.payment_status = "failed"
            db.query(models.SeatHold).filter(
                models.SeatHold.trip_id == b.trip_id,
                models.SeatHold.user_id == b.passenger_id,
                models.SeatHold.is_released == False
            ).update({"is_released": True})
            updated = True
            
    if updated:
        try:
            db.commit()
        except Exception:
            db.rollback()


@router.get("", response_model=List[schemas.BookingResponse])
def list_bookings(
    status_filter: Optional[str] = Query(None, alias="status", description="upcoming, completed, expired, cancelled, confirmed, pending"),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    if current_user.role == "admin":
        bookings = db.query(models.Booking).order_by(models.Booking.created_at.desc()).all()
    elif current_user.role == "owner":
        # Get bookings for trips scheduled on vehicles belonging to their company
        bookings = db.query(models.Booking).join(models.Trip).join(models.Vehicle).filter(
            models.Vehicle.company_id == current_user.company_id
        ).order_by(models.Booking.created_at.desc()).all()
    elif current_user.role == "conductor":
        # Get bookings for trips assigned to this conductor
        bookings = db.query(models.Booking).join(models.Trip).filter(
            models.Trip.conductor_id == current_user.id
        ).order_by(models.Booking.created_at.desc()).all()
    else:
        # Passengers get their own bookings (only paid bookings or active pending holds; exclude unpaid failed/cancelled sessions)
        from sqlalchemy import or_, and_
        bookings = db.query(models.Booking).filter(
            models.Booking.passenger_id == current_user.id,
            or_(
                models.Booking.payment_status == "paid",
                and_(
                    models.Booking.booking_status == "pending",
                    models.Booking.payment_status == "pending"
                )
            )
        ).order_by(models.Booking.created_at.desc()).all()

    # Populate nested structures for returning to client
    for booking in bookings:
        booking.trip = db.query(models.Trip).filter(models.Trip.id == booking.trip_id).first()
        booking.passenger = db.query(models.User).filter(models.User.id == booking.passenger_id).first()
        if booking.trip:
            booking.trip.route = db.query(models.Route).filter(models.Route.id == booking.trip.route_id).first()
            booking.trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == booking.trip.vehicle_id).first()
            if booking.trip.conductor_id:
                booking.trip.conductor = db.query(models.User).filter(models.User.id == booking.trip.conductor_id).first()

    _auto_update_booking_statuses(db, bookings)

    if status_filter:
        sf = status_filter.lower().strip()
        if sf == "upcoming":
            bookings = [b for b in bookings if b.booking_status == "confirmed"]
        elif sf in ["completed", "expired", "cancelled", "pending"]:
            bookings = [b for b in bookings if b.booking_status == sf]

    return bookings


@router.get("/{booking_id}", response_model=schemas.BookingResponse)
def get_booking(
    booking_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    booking = db.query(models.Booking).filter(models.Booking.id == booking_id).first()
    if not booking:
        raise HTTPException(status_code=404, detail="Booking record not found")

    # Authorize viewing
    if current_user.role == "passenger" and booking.passenger_id != current_user.id:
        raise HTTPException(status_code=403, detail="Unauthorized to view this booking")
    elif current_user.role == "owner":
        trip = db.query(models.Trip).filter(models.Trip.id == booking.trip_id).first()
        vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
        if not vehicle or vehicle.company_id != current_user.company_id:
            raise HTTPException(status_code=403, detail="Unauthorized to view this company's booking")
    elif current_user.role == "conductor":
        trip = db.query(models.Trip).filter(models.Trip.id == booking.trip_id).first()
        if not trip or trip.conductor_id != current_user.id:
            raise HTTPException(status_code=403, detail="Unauthorized to view this booking")

    booking.trip = db.query(models.Trip).filter(models.Trip.id == booking.trip_id).first()
    booking.passenger = db.query(models.User).filter(models.User.id == booking.passenger_id).first()
    if booking.trip:
        booking.trip.route = db.query(models.Route).filter(models.Route.id == booking.trip.route_id).first()
        booking.trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == booking.trip.vehicle_id).first()
        if booking.trip.conductor_id:
            booking.trip.conductor = db.query(models.User).filter(models.User.id == booking.trip.conductor_id).first()

    _auto_update_booking_statuses(db, [booking])

    return booking


@router.post("/{booking_id}/cancel", response_model=schemas.BookingResponse)
def cancel_booking(
    booking_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    booking = db.query(models.Booking).filter(models.Booking.id == booking_id).first()
    if not booking:
        raise HTTPException(status_code=404, detail="Booking record not found")

    # Check permissions (must be the passenger who booked, or admin)
    if current_user.role != "admin" and booking.passenger_id != current_user.id:
        raise HTTPException(status_code=403, detail="Unauthorized to cancel this booking")

    if booking.booking_status == "cancelled":
        raise HTTPException(status_code=400, detail="Booking is already cancelled")

    booking.booking_status = "cancelled"

    # Release any active seat holds for this booking
    db.query(models.SeatHold).filter(
        models.SeatHold.trip_id == booking.trip_id,
        models.SeatHold.user_id == booking.passenger_id,
        models.SeatHold.is_released == False
    ).update({"is_released": True})

    db.commit()
    db.refresh(booking)

    notify_seat_change(str(booking.trip_id), "SEAT_RELEASED", booking.selected_seats)

    booking.trip = db.query(models.Trip).filter(models.Trip.id == booking.trip_id).first()
    booking.passenger = current_user
    if booking.trip:
        booking.trip.route = db.query(models.Route).filter(models.Route.id == booking.trip.route_id).first()
        booking.trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == booking.trip.vehicle_id).first()

    return booking
