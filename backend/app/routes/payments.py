from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import UUID
import html
import logging
import uuid
import datetime

from app.config import settings
from app.database import get_db
from app import models, schemas, auth
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
                    send_sms(passenger.phone_number, sms_text)
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
            return existing_payment
        if booking.payment_status == "paid":
            raise HTTPException(status_code=400, detail="Booking is already paid")

    trip = db.query(models.Trip).filter(models.Trip.id == booking.trip_id).first()
    if _is_past_booking_cutoff(trip):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Online payment for this bus closed 30 minutes prior to departure."
        )

    # Calculate platform fee
    platform_fee = _calculate_platform_fee(db, float(booking.total_price))
    total_with_fee = float(booking.total_price) + platform_fee

    # Update booking with platform fee
    booking.platform_fee = platform_fee
    booking.payment_status = "awaiting_payment"

    # Hold seats (create/refresh seat hold)
    hold_minutes = int(_get_platform_setting(db, "seat_hold_duration_minutes", "10"))
    expires_at = datetime.datetime.utcnow() + datetime.timedelta(minutes=hold_minutes)

    # Release any existing holds by this user for this trip
    db.query(models.SeatHold).filter(
        models.SeatHold.trip_id == booking.trip_id,
        models.SeatHold.user_id == current_user.id,
        models.SeatHold.is_released == False
    ).update({"is_released": True})

    seat_hold = models.SeatHold(
        id=uuid.uuid4(),
        trip_id=booking.trip_id,
        user_id=current_user.id,
        seat_labels=booking.selected_seats,
        expires_at=expires_at,
        is_released=False
    )
    db.add(seat_hold)
    db.commit()

    # Open a session with the gateway. clientRef is prefixed because this
    # merchant account is shared with another product - it is how Seaty's
    # transactions are told apart in Bancstac's portal. 50 char limit.
    gateway = get_gateway()
    client_ref = f"SEATY-{booking.id}"[:50]
    amount_cents = to_cents(total_with_fee)

    try:
        session = await gateway.init_payment(
            amount_cents=amount_cents,
            currency=CURRENCY,
            client_ref=client_ref,
            return_url=settings.BANCSTAC_RETURN_URL,
            comment=f"Seaty booking {str(booking.id)[:8]}",
            extra_data={"booking_id": str(booking.id)},
        )
    except PaymentGatewayUnavailable as e:
        raise HTTPException(status_code=503, detail=str(e))
    except PaymentGatewayError as e:
        raise HTTPException(status_code=502, detail=str(e))

    db_payment = models.Payment(
        id=uuid.uuid4(),
        booking_id=booking.id,
        payment_gateway=f"bancstac:{gateway.mode}",
        # The gateway's reqid IS our transaction id. The return handler and the
        # sweeper both look the booking up by it, so it is never taken from the
        # client.
        gateway_transaction_id=session.reqid,
        amount=total_with_fee,
        platform_fee=platform_fee,
        currency=CURRENCY,
        status="pending",
        payment_url=session.payment_page_url,
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

    try:
        result = await get_gateway().complete_payment(payment.gateway_transaction_id)
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
    gateway = get_gateway()
    if gateway.mode != "mock":
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


@router.get("/mock/decline/{reqid}", include_in_schema=False)
def mock_decline(reqid: str):
    """Mark a mock session declined, then follow the normal return path."""
    from app.services.payment_gateway import MockGateway
    gateway = get_gateway()
    if gateway.mode != "mock":
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


@router.post("/{payment_id}/refund", response_model=schemas.PaymentResponse)
def refund_payment(
    payment_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    """Process a refund for a completed payment (admin only)."""
    payment = db.query(models.Payment).filter(models.Payment.id == payment_id).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found")

    if payment.status != "completed":
        raise HTTPException(status_code=400, detail="Can only refund completed payments")

    payment.status = "refunded"
    payment.refunded_at = datetime.datetime.utcnow()

    # Update booking
    booking = db.query(models.Booking).filter(models.Booking.id == payment.booking_id).first()
    if booking:
        booking.payment_status = "refunded"
        booking.booking_status = "cancelled"

    db.commit()
    db.refresh(payment)
    return payment
