from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool
from decimal import Decimal, InvalidOperation
from typing import List, Optional
from uuid import UUID
import html
import logging
import uuid
import datetime

from app.config import settings
from app.database import get_db
from app import models, schemas, auth
from app.services.availability import assert_bookable
from app.services.payment_gateway import (
    PaymentGatewayError,
    PaymentGatewayUnavailable,
    get_gateway,
    to_cents,
)
from app.timezone_utils import now_sl, to_sl

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/payments", tags=["Payments"])

CURRENCY = "LKR"

# A payment session lasts exactly as long as the seat hold, and not a minute
# more. Bancstac's own page stays open for 30 minutes, but we stop honouring it
# at ours: once the window closes the seats go back on sale, so accepting the
# payment after that would confirm a seat we may already have sold. The payer is
# told to start again instead.
#
# Driven by `seat_hold_duration_minutes` so the hold and the payment window can
# never drift apart - there is one number, and the admin console owns it.
def _payment_window_minutes(db: Session) -> int:
    return int(_get_platform_setting(db, "seat_hold_duration_minutes", "10"))


def _payment_expired(db: Session, payment: "models.Payment") -> bool:
    """Has this payment session outlived its window?"""
    created = payment.created_at
    if created is None:
        return False
    if created.tzinfo is None:
        created = created.replace(tzinfo=datetime.timezone.utc)
    age = datetime.datetime.now(datetime.timezone.utc) - created
    return age > datetime.timedelta(minutes=_payment_window_minutes(db))


def _seats_taken_by_others(db: Session, booking: "models.Booking") -> set:
    """Seats on this booking that somebody else has already paid for or holds.

    The check `finalise_payment` never had. A payment can come back long after
    it was started - a backgrounded app, a dropped connection, the sweeper
    retrying - and confirming it blindly is how one seat ends up sold twice,
    with both passengers charged.
    """
    wanted = set(booking.selected_seats or [])
    if not wanted:
        return set()

    taken = set()

    rival_bookings = db.query(models.Booking).filter(
        models.Booking.trip_id == booking.trip_id,
        models.Booking.id != booking.id,
        models.Booking.booking_status.in_(models.OCCUPIED_BOOKING_STATUSES),
        models.Booking.payment_status == "paid",
    ).all()
    for other in rival_bookings:
        taken |= wanted.intersection(other.selected_seats or [])

    rival_holds = db.query(models.SeatHold).filter(
        models.SeatHold.trip_id == booking.trip_id,
        models.SeatHold.user_id != booking.passenger_id,
        models.SeatHold.is_released == False,
        models.SeatHold.expires_at > datetime.datetime.utcnow(),
    ).all()
    for hold in rival_holds:
        taken |= wanted.intersection(hold.seat_labels or [])

    return taken

# The WebView in the mobile app watches for these paths to know the flow is
# over. Keep them stable - changing one silently strands users on a blank page
# inside the app. Mirrored in mobile/lib/screens/payment_webview_screen.dart.
RESULT_SUCCESS_PATH = "/api/v1/payments/result/success"
RESULT_FAILED_PATH = "/api/v1/payments/result/failed"


def _get_platform_setting(db: Session, key: str, default: str = "0") -> str:
    """Helper to read a platform setting from DB."""
    setting = db.query(models.PlatformSetting).filter(
        models.PlatformSetting.key == key
    ).first()
    return setting.value if setting else default


def _calculate_platform_fee(db: Session, subtotal: float) -> float:
    """Calculate platform fee = (percentage% of subtotal) + fixed fee."""
    pct = float(_get_platform_setting(db, "commission_percentage", "3.0"))
    fixed = float(_get_platform_setting(db, "commission_fixed_fee", "25.0"))
    return round((subtotal * pct / 100) + fixed, 2)


def _is_past_booking_cutoff(trip: "models.Trip | None") -> bool:
    """True once we're within 30 minutes of departure (or past it) - the same
    cutoff enforced when the booking/hold was first created. Payment can take
    a while to complete, so this must be re-checked before confirming a seat,
    not just at the moment the booking/hold was first created."""
    if not trip or not trip.departure_time:
        return False
    dep_time = to_sl(trip.departure_time)
    return now_sl() >= (dep_time - datetime.timedelta(minutes=30))


async def _notify_departed_payment(db: Session, booking: models.Booking):
    """The bus left before the payment cleared. Money owed back."""
    try:
        from app.routes.notifications import create_and_send_notification
        await create_and_send_notification(
            db=db,
            user_id=booking.passenger_id,
            title="Bus departed - refund owed",
            message=(
                "Your payment completed after the bus had already departed, so your "
                "booking was not confirmed. You will be refunded in full - our team "
                f"will contact you shortly. Booking ID: {booking.id}"
            ),
            noti_type="booking",
            booking_id=booking.id,
        )
        for admin in db.query(models.User).filter(models.User.role == "admin").all():
            await create_and_send_notification(
                db=db,
                user_id=admin.id,
                title="Refund owed - paid after departure",
                message=(
                    f"Booking {booking.id} was paid after its bus departed. The "
                    f"passenger has been charged and is owed a refund."
                ),
                noti_type="system",
                booking_id=booking.id,
            )
    except Exception as e:
        logger.error("Could not send departed-payment notice for %s: %s", booking.id, e)


async def _notify_trip_cancelled_payment(db: Session, booking: models.Booking):
    """The payment landed after the operator pulled the bus. Money owed back."""
    try:
        from app.routes.notifications import create_and_send_notification
        await create_and_send_notification(
            db=db,
            user_id=booking.passenger_id,
            title="Trip cancelled - refund owed",
            message=(
                "Your payment completed but the operator had already cancelled this "
                "trip, so your booking was not confirmed. You will be refunded in "
                f"full - our team will contact you shortly. Booking ID: {booking.id}"
            ),
            noti_type="trip_cancelled",
            booking_id=booking.id,
        )
        for admin in db.query(models.User).filter(models.User.role == "admin").all():
            await create_and_send_notification(
                db=db,
                user_id=admin.id,
                title="Refund owed - paid for a cancelled trip",
                message=(
                    f"Booking {booking.id} was paid after its trip was cancelled. "
                    f"The passenger has been charged and is owed a refund."
                ),
                noti_type="system",
                booking_id=booking.id,
            )
    except Exception as e:
        logger.error("Could not send trip-cancelled payment notice for %s: %s", booking.id, e)


async def _notify_payment_expired(db: Session, booking: models.Booking):
    """Tell the passenger the window closed, and the admins that money moved.

    Reached when the gateway approved a payment after our ten minutes were up.
    The seats are already back on sale, so the only honest thing to say is:
    your card was charged, it is coming back, book again.
    """
    try:
        from app.routes.notifications import create_and_send_notification
        await create_and_send_notification(
            db=db,
            user_id=booking.passenger_id,
            title="Payment window expired",
            message=(
                "Your payment completed after the 10-minute booking window closed, so "
                "the seats were released and your booking could not be confirmed. "
                "Our team is reviewing this and will contact you. Please do not "
                f"book again until you hear from us. Booking ID: {booking.id}"
            ),
            noti_type="booking",
            booking_id=booking.id,
        )
        for admin in db.query(models.User).filter(models.User.role == "admin").all():
            await create_and_send_notification(
                db=db,
                user_id=admin.id,
                title="Action needed - charged, no seat",
                message=(
                    f"Booking {booking.id} was paid after its 10-minute window expired. "
                    f"The passenger has been charged and has no seat. Needs a decision."
                ),
                noti_type="system",
                booking_id=booking.id,
            )
    except Exception as e:
        logger.error("Could not send payment-expiry notification for %s: %s", booking.id, e)


async def _notify_seat_conflict(db: Session, booking: models.Booking, seats: set):
    """Tell the passenger, and every admin, that money moved without a seat.

    Reached only when a payment succeeded for a seat that was sold in the
    meantime. Bookings are non-refundable by policy, but that policy covers a
    passenger who changes their mind - not a charge we took and could not
    honour. Nothing here can move money either way, so the point is simply that
    it is never silent: somebody has to decide what happens.
    """
    try:
        from app.routes.notifications import create_and_send_notification
        seat_str = ", ".join(sorted(seats))
        await create_and_send_notification(
            db=db,
            user_id=booking.passenger_id,
            title="Payment received, seat unavailable",
            message=(
                f"Seat(s) {seat_str} were taken before your payment completed, so your "
                f"booking could not be confirmed. Our team is reviewing this and will "
                f"contact you. Please do not book again until you hear from us. "
                f"Booking ID: {booking.id}"
            ),
            noti_type="booking",
            booking_id=booking.id,
        )
        for admin in db.query(models.User).filter(models.User.role == "admin").all():
            await create_and_send_notification(
                db=db,
                user_id=admin.id,
                title="Action needed - charged, no seat",
                message=(
                    f"Booking {booking.id} was paid but seat(s) {seat_str} were already "
                    f"sold. The passenger has been charged and has no seat. Needs a decision."
                ),
                noti_type="system",
                booking_id=booking.id,
            )
    except Exception as e:
        logger.error("Could not send seat-conflict notification for %s: %s", booking.id, e)


async def _send_booking_notifications(db: Session, booking: models.Booking):
    try:
        from app.routes.notifications import create_and_send_notification
        trip = db.query(models.Trip).filter(models.Trip.id == booking.trip_id).first()
        if trip:
            route = db.query(models.Route).filter(models.Route.id == trip.route_id).first()
            vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
            passenger = db.query(models.User).filter(models.User.id == booking.passenger_id).first()
            
            origin = route.origin if route else "Origin"
            destination = route.destination if route else "Destination"
            seats_str = ", ".join(booking.selected_seats)
            
            # 1. Notify Passenger via In-App Notification
            await create_and_send_notification(
                db=db,
                user_id=booking.passenger_id,
                title="Booking Confirmed!",
                message=f"Your seat(s) {seats_str} on trip {vehicle.registration_number if vehicle else ''} ({origin} to {destination}) are confirmed!",
                noti_type="booking",
                booking_id=booking.id
            )
            
            # Dispatch Confirmation SMS to Passenger after successful payment
            if passenger and passenger.phone_number:
                try:
                    from app.services.sms_service import send_sms
                    dep_dt = to_sl(trip.departure_time)
                    if dep_dt:
                        date_time_str = dep_dt.strftime('%d/%m/%Y at %I:%M %p')
                    else:
                        date_time_str = "Scheduled Departure"
                        
                    total_amount = float(booking.total_price) + float(booking.platform_fee or 0)
                    fare_str = f"Rs. {total_amount:,.2f}"
                    ref_code = f"TKT-{str(booking.id)[:8].upper()}"
                    bus_name = vehicle.name if vehicle else "Seaty Superline"
                    bus_no = vehicle.registration_number if vehicle else "N/A"
                    
                    # Fetch Bus Tel from vehicle / owner / company provided in database
                    bus_tel = "N/A"
                    if vehicle:
                        if vehicle.contact_phone and vehicle.contact_phone.strip():
                            bus_tel = vehicle.contact_phone.strip()
                        elif vehicle.owner and vehicle.owner.phone_number and vehicle.owner.phone_number.strip():
                            bus_tel = vehicle.owner.phone_number.strip()
                        elif vehicle.company and vehicle.company.contact_phone and vehicle.company.contact_phone.strip():
                            bus_tel = vehicle.company.contact_phone.strip()

                    support_tel = _get_platform_setting(db, "support_phone", "0262237803")
                    
                    sms_text = (
                        "BOOKING CONFIRMATION\n\n"
                        f"{bus_name}\n"
                        f"Bus No: {bus_no}\n"
                        f"Route: {origin} to {destination}\n"
                        f"Date & Time: {date_time_str}\n"
                        f"Seat(s): {seats_str}\n"
                        f"Fare: {fare_str}\n"
                        f"Ref: {ref_code}\n\n"
                        f"Bus Tel: {bus_tel}\n"
                        f"Support: {support_tel}\n\n"
                        "Present SMS / QR code upon boarding. Thank you!"
                    )
                    # Blocking urllib call with a 10 s timeout. This function
                    # is `async`, so calling it directly held the event loop -
                    # and every WebSocket in the process - for the duration of
                    # the SMS, on every booking confirmation.
                    await run_in_threadpool(send_sms, passenger.phone_number, sms_text)
                except Exception as sms_err:
                    print(f"SMS Dispatch Error: {sms_err}")

            # 2. Notify Owner
            if vehicle and vehicle.owner_id:
                pass_name = passenger.full_name if passenger else "A passenger"
                reg_num = vehicle.registration_number
                await create_and_send_notification(
                    db=db,
                    user_id=vehicle.owner_id,
                    title="New Booking Received",
                    message=f"{pass_name} booked seat(s) {seats_str} on your vehicle {reg_num}.",
                    noti_type="booking",
                    booking_id=booking.id
                )
    except Exception as noti_err:
        print(f"Notification Error: {noti_err}")


@router.post("/initiate", response_model=schemas.PaymentResponse, status_code=status.HTTP_201_CREATED)
async def initiate_payment(
    payload: schemas.PaymentInitiateRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["passenger", "admin"]))
):
    """Open a payment session for a booking.

    1. Verifies the booking belongs to the caller
    2. Recomputes the amount server-side
    3. Refreshes the seat hold
    4. Asks the gateway for a session and returns its payment page URL

    Nothing here marks anything paid. Only `/bancstac/return` and the
    reconciliation sweeper can do that, and only on the gateway's word.
    """
    # Fetch booking
    booking = db.query(models.Booking).filter(models.Booking.id == payload.booking_id).first()
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found")

    # This check used to be missing entirely, while the docstring claimed it
    # was here: any passenger could pass any booking_id and take actions on a
    # stranger's booking - see docs/SECURITY.md #26.
    if booking.passenger_id != current_user.id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Unauthorized to pay for this booking")

    if booking.booking_status in ["expired", "cancelled"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This booking has expired or been cancelled. Please select your seats again."
        )

    if booking.payment_status in ["paid", "awaiting_payment"]:
        # If already awaiting, check if there's an existing payment
        existing_payment = db.query(models.Payment).filter(
            models.Payment.booking_id == booking.id,
            models.Payment.status.in_(["pending", "processing"])
        ).first()
        if existing_payment:
            if not _payment_expired(db, existing_payment):
                return existing_payment
            # The window has closed on the previous attempt. Retire it rather
            # than handing back a payment page the gateway will refuse, and let
            # the passenger start a fresh booking.
            existing_payment.status = "failed"
            booking.payment_status = "failed"
            booking.booking_status = "cancelled"
            db.query(models.SeatHold).filter(
                models.SeatHold.trip_id == booking.trip_id,
                models.SeatHold.user_id == booking.passenger_id,
                models.SeatHold.is_released == False
            ).update({"is_released": True})
            db.commit()
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Your payment window has expired and the seats have been "
                       "released. Please start the booking again.",
            )
        if booking.payment_status == "paid":
            raise HTTPException(status_code=400, detail="Booking is already paid")

    trip = db.query(models.Trip).filter(models.Trip.id == booking.trip_id).first()
    if _is_past_booking_cutoff(trip):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Online payment for this bus closed 30 minutes prior to departure."
        )

    # Last chokepoint before money moves. A passenger who created their booking
    # before the trip was switched off would otherwise still be able to pay for
    # a bus that is no longer being sold - and taking the payment is much harder
    # to undo than refusing it, since there is no gateway refund call.
    if trip is not None:
        assert_bookable(db, trip)

    # Calculate platform fee
    platform_fee = _calculate_platform_fee(db, float(booking.total_price))
    total_with_fee = float(booking.total_price) + platform_fee

    # Ask the gateway for a session BEFORE writing anything. Committing the
    # hold and the awaiting_payment status first meant a gateway that refused -
    # payments switched off, network down - left the seats locked for the hold
    # window and the booking parked in awaiting_payment with no payment row to
    # resolve it. Nothing is persisted unless there is a session to pay into.
    #
    # clientRef is prefixed because this merchant account is shared with another
    # product; it is how Seaty's transactions are told apart in Bancstac's
    # portal. 50 char limit.
    gateway = get_gateway(for_user=current_user)
    client_ref = f"SEATY-{booking.id}"[:50]

    # Pre-release: charge a token amount against the LIVE gateway so a real card
    # and a real authorisation can be exercised without taking real fares. The
    # booking is still confirmed in full. Clear PAYMENT_TEST_CHARGE_LKR to
    # charge properly - see docs/PAYMENTS.md.
    real_cents = to_cents(total_with_fee)
    charge_cents = real_cents
    test_charge = (settings.PAYMENT_TEST_CHARGE_LKR or "").strip()
    if test_charge and gateway.mode == "live":
        try:
            override = to_cents(Decimal(test_charge))
            if override > 0:
                charge_cents = override
                logger.warning(
                    "TEST CHARGE ACTIVE: booking %s is %s cents but charging %s cents",
                    booking.id, real_cents, charge_cents,
                )
        except (InvalidOperation, ValueError):
            logger.error("PAYMENT_TEST_CHARGE_LKR is not a number: %r - charging the real amount",
                         test_charge)

    try:
        session = await gateway.init_payment(
            amount_cents=charge_cents,
            currency=CURRENCY,
            client_ref=client_ref,
            return_url=settings.BANCSTAC_RETURN_URL,
            comment=f"Seaty booking {str(booking.id)[:8]}",
            extra_data={"booking_id": str(booking.id)},
        )
    except PaymentGatewayUnavailable as e:
        db.rollback()
        raise HTTPException(status_code=503, detail=str(e))
    except PaymentGatewayError as e:
        db.rollback()
        raise HTTPException(status_code=502, detail=str(e))

    # Session is open, so now commit the local side in one go.
    booking.platform_fee = platform_fee
    booking.payment_status = "awaiting_payment"

    # The hold and the payment window are the same ten minutes, deliberately.
    # The seats stay reserved for exactly as long as the payment is honoured,
    # so there is never a period where the seats are back on sale but a stale
    # payment could still confirm them.
    hold_minutes = _payment_window_minutes(db)
    expires_at = datetime.datetime.utcnow() + datetime.timedelta(minutes=hold_minutes)

    # Same lock as create_booking, for the same reason.
    db.query(models.Trip).filter(
        models.Trip.id == booking.trip_id
    ).with_for_update().first()

    # Refuse to open a payment for seats that now belong to somebody else.
    # This used to release the caller's holds and mint a fresh one with no
    # check at all, which handed the seats back to whoever paid last.
    taken = _seats_taken_by_others(db, booking)
    if taken:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Seat(s) {', '.join(sorted(taken))} are no longer available. "
                   "Please choose different seats.",
        )

    # Release only this booking's own earlier holds, not every hold the
    # passenger has on the trip - they may have another booking pending.
    # Compared in Python: `seat_labels == <python list>` renders as
    # `text[] = varchar[]`, which Postgres has no operator for.
    booked_seats = set(booking.selected_seats or [])
    for prior in db.query(models.SeatHold).filter(
        models.SeatHold.trip_id == booking.trip_id,
        models.SeatHold.user_id == current_user.id,
        models.SeatHold.is_released == False,
    ).all():
        if set(prior.seat_labels or []) == booked_seats:
            prior.is_released = True

    db.add(models.SeatHold(
        id=uuid.uuid4(),
        trip_id=booking.trip_id,
        user_id=current_user.id,
        seat_labels=booking.selected_seats,
        expires_at=expires_at,
        is_released=False
    ))

    db_payment = models.Payment(
        id=uuid.uuid4(),
        booking_id=booking.id,
        payment_gateway=f"bancstac:{gateway.mode}",
        # The gateway's reqid IS our transaction id. The return handler and the
        # sweeper both look the booking up by it, so it is never taken from the
        # client.
        gateway_transaction_id=session.reqid,
        # What the card is actually charged. finalise_payment verifies the
        # gateway's figure against this, so it has to be the charged amount and
        # not the booking total.
        amount=Decimal(charge_cents) / 100,
        platform_fee=platform_fee,
        currency=CURRENCY,
        status="pending",
        payment_url=session.payment_page_url,
        gateway_response=(
            {"test_charge": True,
             "real_amount_cents": real_cents,
             "charged_amount_cents": charge_cents}
            if charge_cents != real_cents else None
        ),
    )
    db.add(db_payment)
    db.commit()
    db.refresh(db_payment)

    return db_payment


async def finalise_payment(db: Session, payment: models.Payment) -> bool:
    """Ask the gateway what happened to a payment and record the outcome.

    The single place a booking can become paid. Called by the return handler
    and by the reconciliation sweeper; safe to call repeatedly.

    Returns True if the booking ended up confirmed.
    """
    if payment.status == "completed":
        return True                      # idempotent: browser refresh, retry, sweeper overlap
    if payment.status in ("failed", "refunded"):
        return False

    booking = db.query(models.Booking).filter(models.Booking.id == payment.booking_id).first()

    # Resolve against the gateway that opened the session. payment_gateway
    # holds "bancstac:mock" or "bancstac:live"; completing a simulated payment
    # against the real gateway (or the reverse) would never match.
    created_mode = (payment.payment_gateway or "").split(":")[-1] or None

    if created_mode == "mock":
        # Mock sessions are in-process, so a restart between opening and
        # completing loses them. The payment row has everything needed.
        from app.services.payment_gateway import MockGateway
        MockGateway.restore_session(
            payment.gateway_transaction_id,
            amount_cents=to_cents(payment.amount),
            currency=payment.currency or CURRENCY,
            client_ref=f"SEATY-{payment.booking_id}"[:50],
        )

    try:
        result = await get_gateway(force_mode=created_mode).complete_payment(
            payment.gateway_transaction_id
        )
    except PaymentGatewayError as e:
        # Leave it pending - the sweeper will try again. Never fail a payment
        # because we could not reach the gateway; the customer may well have paid.
        logger.warning("PAYMENT_COMPLETE unavailable for %s: %s", payment.gateway_transaction_id, e)
        return False

    expected_cents = to_cents(payment.amount)
    expected_ref = f"SEATY-{payment.booking_id}"[:50]

    # Verify before trusting. An approval for the wrong amount, or for another
    # merchant reference, is not an approval for this booking.
    if result.approved and result.amount_cents and result.amount_cents != expected_cents:
        logger.error(
            "Payment %s AMOUNT MISMATCH: gateway=%s expected=%s - refusing to confirm",
            payment.id, result.amount_cents, expected_cents,
        )
        result.approved = False
        result.response_text = f"Amount mismatch ({result.amount_cents} vs {expected_cents})"
    if result.approved and result.client_ref and result.client_ref != expected_ref:
        logger.error(
            "Payment %s CLIENTREF MISMATCH: gateway=%s expected=%s - refusing to confirm",
            payment.id, result.client_ref, expected_ref,
        )
        result.approved = False
        result.response_text = "Client reference mismatch"

    payment.gateway_response = {
        **(payment.gateway_response or {}),
        "response_code": result.response_code,
        "response_text": result.response_text,
        "txn_reference": result.txn_reference,
        "auth_code": result.auth_code,
        "card_type": result.card_type,
        "card_masked": result.card_masked,
        "amount_cents": result.amount_cents,
        "checked_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }

    if result.approved:
        payment.status = "completed"
        payment.paid_at = datetime.datetime.now(datetime.timezone.utc)

        # Last gate before a seat is handed over. The gateway's approval says
        # the card was charged; it says nothing about whether the seat is still
        # ours. A session that returns late - backgrounded app, dead phone, the
        # sweeper retrying at minute 34 - could otherwise confirm a seat that
        # has since been sold, leaving two passengers holding a paid ticket for
        # it. The money has already moved, so this cannot be undone here: flag
        # it loudly for a human decision instead of quietly double-selling.
        # The ten-minute window is the rule, and it is enforced here rather
        # than trusted to the gateway: once it closes the seats went back on
        # sale, so an approval arriving afterwards is for a seat we no longer
        # own. The card has been charged either way - the gateway does not ask
        # our permission - so this cannot be undone here. Never confirm it, and
        # never let it pass silently.
        expired = _payment_expired(db, payment)
        conflict = _seats_taken_by_others(db, booking) if booking else set()

        # The bus is not running. Whatever the gateway says, there is no seat
        # to hand over - and if the card was charged anyway the passenger is
        # owed it back, because this cancellation was not theirs.
        trip_cancelled = False
        if booking:
            _trip = db.query(models.Trip).filter(models.Trip.id == booking.trip_id).first()
            trip_cancelled = bool(_trip and _trip.status == "cancelled")

        # The bus has already left. Normally unreachable - booking closes 30
        # minutes before departure and the payment window is 10 - but an
        # operator rescheduling a trip earlier moves the departure under a
        # payment that is already in flight.
        #
        # Deliberately checks actual departure, not `_is_past_booking_cutoff`:
        # a booking made just over the 30-minute line legitimately settles
        # inside that window, and refusing it would break the normal path.
        departed = False
        if booking and _trip and _trip.departure_time:
            departed = now_sl() >= to_sl(_trip.departure_time)

        if departed and not trip_cancelled:
            logger.error(
                "PAYMENT %s APPROVED AFTER DEPARTURE of trip %s - booking %s not "
                "confirmed, refund owed", payment.id, booking.trip_id, booking.id,
            )
            payment.gateway_response = {
                **(payment.gateway_response or {}),
                "departed_before_payment": True,
                "refund_due": True,
                "refund_reason": "bus departed before payment completed",
            }
            booking.payment_status = "paid"
            booking.booking_status = "cancelled"
            db.query(models.SeatHold).filter(
                models.SeatHold.trip_id == booking.trip_id,
                models.SeatHold.user_id == booking.passenger_id,
                models.SeatHold.is_released == False
            ).update({"is_released": True})
            db.commit()
            await _notify_departed_payment(db, booking)
            return False

        if trip_cancelled:
            logger.error(
                "PAYMENT %s APPROVED FOR CANCELLED TRIP %s - booking %s not confirmed, "
                "refund owed", payment.id, booking.trip_id, booking.id,
            )
            payment.gateway_response = {
                **(payment.gateway_response or {}),
                "trip_cancelled": True,
                "refund_due": True,
                "refund_reason": "trip cancelled by operator",
            }
            booking.payment_status = "paid"
            booking.booking_status = "cancelled"
            db.query(models.SeatHold).filter(
                models.SeatHold.trip_id == booking.trip_id,
                models.SeatHold.user_id == booking.passenger_id,
                models.SeatHold.is_released == False
            ).update({"is_released": True})
            db.commit()
            await _notify_trip_cancelled_payment(db, booking)
            return False

        if expired and booking:
            logger.error(
                "PAYMENT %s APPROVED AFTER ITS %s-MINUTE WINDOW (booking %s) - "
                "not confirmed, charge unfulfilled",
                payment.id, _payment_window_minutes(db), booking.id,
            )
            payment.gateway_response = {
                **(payment.gateway_response or {}),
                "expired_window": True,
                "unfulfilled_charge": True,
            }
            booking.payment_status = "paid"
            booking.booking_status = "cancelled"
            db.query(models.SeatHold).filter(
                models.SeatHold.trip_id == booking.trip_id,
                models.SeatHold.user_id == booking.passenger_id,
                models.SeatHold.is_released == False
            ).update({"is_released": True})
            db.commit()
            await _notify_payment_expired(db, booking)
            return False

        if conflict:
            logger.error(
                "PAYMENT %s TAKEN BUT SEAT(S) %s ALREADY SOLD on trip %s - "
                "booking %s NOT confirmed, charge unfulfilled",
                payment.id, sorted(conflict), booking.trip_id, booking.id,
            )
            payment.gateway_response = {
                **(payment.gateway_response or {}),
                "seat_conflict": sorted(conflict),
                "unfulfilled_charge": True,
            }
            booking.payment_status = "paid"
            booking.booking_status = "cancelled"
            db.query(models.SeatHold).filter(
                models.SeatHold.trip_id == booking.trip_id,
                models.SeatHold.user_id == booking.passenger_id,
                models.SeatHold.is_released == False
            ).update({"is_released": True})
            db.commit()
            await _notify_seat_conflict(db, booking, conflict)
            return False

        if booking:
            booking.payment_status = "paid"
            booking.booking_status = "confirmed"
            db.query(models.SeatHold).filter(
                models.SeatHold.trip_id == booking.trip_id,
                models.SeatHold.user_id == booking.passenger_id,
                models.SeatHold.is_released == False
            ).update({"is_released": True})
        db.commit()

        if booking:
            # After the commit: a failure here must not undo a real payment.
            await _send_booking_notifications(db, booking)
        return True

    payment.status = "failed"
    if booking:
        booking.payment_status = "failed"
        booking.booking_status = "cancelled"
        db.query(models.SeatHold).filter(
            models.SeatHold.trip_id == booking.trip_id,
            models.SeatHold.user_id == booking.passenger_id,
            models.SeatHold.is_released == False
        ).update({"is_released": True})
    db.commit()
    return False


def _result_page(title: str, message: str, ok: bool) -> HTMLResponse:
    colour = "#0f9d58" if ok else "#d93025"
    return HTMLResponse(f"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)}</title></head>
<body style="font-family:system-ui,-apple-system,sans-serif;display:flex;align-items:center;
justify-content:center;height:100vh;margin:0;background:#f6f8fa">
<div style="text-align:center;padding:32px">
<div style="font-size:56px;color:{colour}">{'&#10003;' if ok else '&#10007;'}</div>
<h2 style="margin:12px 0;color:#0A2540">{html.escape(title)}</h2>
<p style="color:#5f6368;max-width:320px">{html.escape(message)}</p>
</div></body></html>""")


@router.get("/bancstac/return", include_in_schema=False)
async def bancstac_return(reqid: str = Query(...), db: Session = Depends(get_db)):
    """Where Bancstac sends the payer's browser after card entry.

    Unauthenticated by necessity - the gateway performs this redirect, not our
    client, and it carries no session. That is safe because the redirect
    contains no payment result: it only names a `reqid`, and the booking is
    looked up by the reqid *we stored at initiation*. The outcome comes from
    asking Bancstac directly in finalise_payment().
    """
    payment = db.query(models.Payment).filter(
        models.Payment.gateway_transaction_id == reqid
    ).first()

    if not payment:
        logger.warning("Bancstac return for unknown reqid %r", reqid[:64])
        return RedirectResponse(RESULT_FAILED_PATH, status_code=303)

    ok = await finalise_payment(db, payment)
    return RedirectResponse(RESULT_SUCCESS_PATH if ok else RESULT_FAILED_PATH, status_code=303)


@router.get("/result/success", include_in_schema=False)
def payment_result_success():
    return _result_page("Payment successful", "Your booking is confirmed. You can close this window.", True)


@router.get("/result/failed", include_in_schema=False)
def payment_result_failed():
    return _result_page("Payment not completed", "No charge was made. Please try again.", False)


# =====================================================================
# Mock gateway pages - PAYMENT_MODE=mock only
# =====================================================================
@router.get("/mock/pay/{reqid}", include_in_schema=False)
def mock_payment_page(reqid: str, db: Session = Depends(get_db)):
    """Stand-in for Bancstac's hosted card page.

    Only reachable when PAYMENT_MODE=mock, which itself cannot be set in
    production. Lets the whole flow - including the WebView hand-off and the
    return redirect - be exercised without a gateway or a card.
    """
    # Reachable whenever the session itself is simulated - either global mock
    # mode or an allowlisted account. The reqid prefix is the authority.
    if not reqid.startswith("MOCK-"):
        raise HTTPException(status_code=404, detail="Not found")

    payment = db.query(models.Payment).filter(
        models.Payment.gateway_transaction_id == reqid
    ).first()
    amount = f"{float(payment.amount):,.2f}" if payment else "?"
    ret = settings.BANCSTAC_RETURN_URL or "/api/v1/payments/bancstac/return"
    sep = "&" if "?" in ret else "?"
    safe_reqid = html.escape(reqid)

    return HTMLResponse(f"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Mock payment</title></head>
<body style="font-family:system-ui,-apple-system,sans-serif;display:flex;align-items:center;
justify-content:center;height:100vh;margin:0;background:#f6f8fa">
<div style="background:#fff;padding:28px;border-radius:14px;box-shadow:0 2px 16px #0001;
max-width:340px;width:90%;text-align:center">
<div style="background:#fff3cd;color:#7a5b00;padding:8px;border-radius:8px;font-size:13px;
margin-bottom:16px">MOCK GATEWAY — no real payment</div>
<h2 style="margin:0 0 4px;color:#0A2540">LKR {amount}</h2>
<p style="color:#5f6368;font-size:12px;margin:0 0 20px">{safe_reqid}</p>
<a href="{html.escape(ret)}{sep}reqid={safe_reqid}"
   style="display:block;background:#0A2540;color:#fff;padding:13px;border-radius:9px;
   text-decoration:none;font-weight:600;margin-bottom:10px">Approve payment</a>
<a href="/api/v1/payments/mock/decline/{safe_reqid}"
   style="display:block;background:#eee;color:#d93025;padding:13px;border-radius:9px;
   text-decoration:none;font-weight:600">Decline payment</a>
</div></body></html>""")


@router.post("/sandbox/complete/{transaction_id}", response_model=schemas.PaymentResponse,
             include_in_schema=False)
async def sandbox_complete_payment(transaction_id: str, db: Session = Depends(get_db)):
    """Compatibility shim for app builds that predate the WebView flow.

    Those builds show their own checkout screen and POST here with no auth
    header, so requiring one would simply break them.

    The original endpoint accepted **any** transaction id and could confirm any
    booking as paid — free tickets for anyone who guessed one (docs/SECURITY.md
    #3). This one accepts only a `MOCK-` reqid, which exists solely for a
    simulated payment by an account in `PAYMENT_MOCK_ACCOUNTS`. Those bookings
    are free by design, and a real Bancstac payment can never be settled here:
    live sessions never carry that prefix.

    Remove once the WebView build is everywhere.
    """
    if not transaction_id.startswith("MOCK-"):
        raise HTTPException(status_code=404, detail="Not found")

    payment = db.query(models.Payment).filter(
        models.Payment.gateway_transaction_id == transaction_id
    ).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment transaction not found")

    await finalise_payment(db, payment)
    db.refresh(payment)
    return payment


@router.post("/sandbox/fail/{transaction_id}", response_model=schemas.PaymentResponse,
             include_in_schema=False)
async def sandbox_fail_payment(transaction_id: str, db: Session = Depends(get_db)):
    """Compatibility shim — the 'Cancel & Release Seats' button on old builds.

    Same `MOCK-` restriction as above. The original could flip an already-paid
    booking to cancelled for anyone who knew its transaction id
    (docs/SECURITY.md #27).
    """
    from app.services.payment_gateway import MockGateway

    if not transaction_id.startswith("MOCK-"):
        raise HTTPException(status_code=404, detail="Not found")

    payment = db.query(models.Payment).filter(
        models.Payment.gateway_transaction_id == transaction_id
    ).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment transaction not found")

    MockGateway.set_outcome(transaction_id, "decline")
    await finalise_payment(db, payment)
    db.refresh(payment)
    return payment


@router.get("/mock/decline/{reqid}", include_in_schema=False)
def mock_decline(reqid: str):
    """Mark a mock session declined, then follow the normal return path."""
    from app.services.payment_gateway import MockGateway
    if not reqid.startswith("MOCK-"):
        raise HTTPException(status_code=404, detail="Not found")
    MockGateway.set_outcome(reqid, "decline")

    ret = settings.BANCSTAC_RETURN_URL or "/api/v1/payments/bancstac/return"
    sep = "&" if "?" in ret else "?"
    return RedirectResponse(f"{ret}{sep}reqid={reqid}", status_code=303)


@router.get("/{payment_id}", response_model=schemas.PaymentResponse)
def get_payment(
    payment_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    """Get payment status."""
    payment = db.query(models.Payment).filter(models.Payment.id == payment_id).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found")

    # Auth check: only the booking owner or admin can view
    booking = db.query(models.Booking).filter(models.Booking.id == payment.booking_id).first()
    if booking and booking.passenger_id != current_user.id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Unauthorized to view this payment")

    return payment


@router.get("/booking/{booking_id}", response_model=List[schemas.PaymentResponse])
def get_payments_for_booking(
    booking_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    """Get all payments for a booking."""
    booking = db.query(models.Booking).filter(models.Booking.id == booking_id).first()
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found")

    if booking.passenger_id != current_user.id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Unauthorized")

    return db.query(models.Payment).filter(models.Payment.booking_id == booking_id).all()


@router.get("/refunds/pending")
def list_pending_refunds(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    """Payments that are owed back but have not been sent back yet.

    The gateway has no refund call, so a refund is a human action: somebody
    moves the money in Bancstac's portal and then marks it here. Without a list
    to work from, the flags written when a trip is cancelled - or when a charge
    could not be honoured - are invisible, and the passenger simply never hears
    back. Declared above `/{payment_id}` so the literal path is not swallowed
    as a UUID.
    """
    rows = db.query(models.Payment).filter(
        models.Payment.status == "completed",
        models.Payment.gateway_response.isnot(None),
    ).order_by(models.Payment.created_at.desc()).all()

    out = []
    for pay in rows:
        meta = pay.gateway_response or {}
        if not (meta.get("refund_due") or meta.get("unfulfilled_charge")):
            continue
        booking = db.query(models.Booking).filter(
            models.Booking.id == pay.booking_id
        ).first()
        passenger = db.query(models.User).filter(
            models.User.id == booking.passenger_id
        ).first() if booking else None
        out.append({
            "payment_id": str(pay.id),
            "booking_id": str(pay.booking_id),
            "gateway_transaction_id": pay.gateway_transaction_id,
            "amount": float(pay.amount or 0),
            "currency": pay.currency,
            "paid_at": pay.paid_at.isoformat() if pay.paid_at else None,
            "reason": meta.get("refund_reason")
                      or ("charged but no seat" if meta.get("unfulfilled_charge") else "unknown"),
            "passenger_name": passenger.full_name if passenger else None,
            "passenger_phone": passenger.phone_number if passenger else None,
            "seats": (booking.selected_seats if booking else None),
        })

    return {
        "count": len(out),
        "total_amount": round(sum(r["amount"] for r in out), 2),
        "payments": out,
    }


@router.post("/{payment_id}/refund", response_model=schemas.PaymentResponse)
def refund_payment(
    payment_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    """Record that a refund has been sent, and clear it from the queue.

    This does **not** move money - Bancstac exposes no refund operation, so the
    transfer happens by hand in their portal. Calling this is the admin saying
    "I have done that", which is why it is the only thing that clears
    `refund_due`. It used to be presented as processing the refund itself.

    Bookings are non-refundable when a passenger cancels; this exists for the
    cases where Seaty owes the money back - an operator cancelling a trip, or a
    charge that could not be honoured.
    """
    payment = db.query(models.Payment).filter(models.Payment.id == payment_id).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found")

    if payment.status != "completed":
        raise HTTPException(status_code=400, detail="Can only refund completed payments")

    payment.status = "refunded"
    payment.refunded_at = datetime.datetime.utcnow()
    payment.gateway_response = {
        **(payment.gateway_response or {}),
        "refund_due": False,
        "unfulfilled_charge": False,
        "refund_recorded_by": str(current_user.id),
        "refund_recorded_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }

    # Update booking
    booking = db.query(models.Booking).filter(models.Booking.id == payment.booking_id).first()
    if booking:
        booking.payment_status = "refunded"
        booking.booking_status = "cancelled"

    db.commit()
    db.refresh(payment)
    return payment
