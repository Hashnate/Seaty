from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID
import uuid
import datetime

from app.database import get_db
from app import models, schemas, auth

router = APIRouter(prefix="/payments", tags=["Payments"])


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
                message=f"Your seat(s) {seats_str} on trip {vehicle.registration_number if vehicle else ''} ({origin} ➔ {destination}) are confirmed!",
                noti_type="booking"
            )
            
            # Dispatch Confirmation SMS to Passenger after successful payment
            if passenger and passenger.phone_number:
                try:
                    from app.services.sms_service import send_sms
                    dep_dt = trip.departure_time
                    if dep_dt:
                        date_time_str = dep_dt.strftime('%d/%m/%Y at %I:%M %p')
                    else:
                        date_time_str = "Scheduled Departure"
                        
                    total_amount = float(booking.total_price) + float(booking.platform_fee or 0)
                    fare_str = f"Rs. {total_amount:,.2f}"
                    ref_code = f"TKT-{str(booking.id)[:8].upper()}"
                    bus_name = vehicle.name if vehicle else "Seaty Superline"
                    bus_no = vehicle.registration_number if vehicle else "N/A"
                    bus_tel = (vehicle.contact_phone if vehicle and vehicle.contact_phone else "N/A")
                    support_tel = _get_platform_setting(db, "support_phone", "0740006523")
                    
                    sms_text = (
                        "BOOKING CONFIRMATION\n\n"
                        f"{bus_name}\n"
                        f"Bus No: {bus_no}\n"
                        f"Route: {origin} ➔ {destination}\n"
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
                    noti_type="booking"
                )
    except Exception as noti_err:
        print(f"Notification Error: {noti_err}")


@router.post("/initiate", response_model=schemas.PaymentResponse, status_code=status.HTTP_201_CREATED)
def initiate_payment(
    payload: schemas.PaymentInitiateRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["passenger", "admin"]))
):
    """
    Initiate a payment for a booking.
    1. Validates the booking belongs to the current user
    2. Holds the seats temporarily
    3. Creates a payment record with sandbox payment URL
    4. Returns payment details for the client to redirect
    """
    # Fetch booking
    booking = db.query(models.Booking).filter(models.Booking.id == payload.booking_id).first()
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found")

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

    # Generate sandbox payment (mock gateway)
    gateway = _get_platform_setting(db, "payment_gateway", "sandbox")
    transaction_id = f"SB-{uuid.uuid4().hex[:12].upper()}"

    # In sandbox mode, generate a simulated payment URL
    payment_url = f"/api/v1/payments/sandbox/complete/{transaction_id}"

    db_payment = models.Payment(
        id=uuid.uuid4(),
        booking_id=booking.id,
        payment_gateway=gateway,
        gateway_transaction_id=transaction_id,
        amount=total_with_fee,
        platform_fee=platform_fee,
        currency="LKR",
        status="pending",
        payment_url=payment_url
    )
    db.add(db_payment)
    db.commit()
    db.refresh(db_payment)

    return db_payment


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


@router.post("/sandbox/complete/{transaction_id}", response_model=schemas.PaymentResponse)
async def sandbox_complete_payment(
    transaction_id: str,
    db: Session = Depends(get_db)
):
    """
    Sandbox payment completion endpoint.
    In production, this would be replaced by the actual payment gateway webhook.
    Simulates a successful payment completion.
    """
    payment = db.query(models.Payment).filter(
        models.Payment.gateway_transaction_id == transaction_id
    ).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment transaction not found")

    if payment.status == "completed":
        return payment

    # Mark payment as completed
    payment.status = "completed"
    payment.paid_at = datetime.datetime.utcnow()
    payment.gateway_response = {
        "sandbox": True,
        "message": "Sandbox payment completed successfully",
        "completed_at": datetime.datetime.utcnow().isoformat()
    }

    # Update booking status
    booking = db.query(models.Booking).filter(models.Booking.id == payment.booking_id).first()
    if booking:
        booking.payment_status = "paid"
        booking.booking_status = "confirmed"

        # Release the seat hold (seats are now permanently booked)
        db.query(models.SeatHold).filter(
            models.SeatHold.trip_id == booking.trip_id,
            models.SeatHold.user_id == booking.passenger_id,
            models.SeatHold.is_released == False
        ).update({"is_released": True})

        # Trigger notifications
        await _send_booking_notifications(db, booking)

    db.commit()
    db.refresh(payment)
    return payment


@router.post("/sandbox/fail/{transaction_id}", response_model=schemas.PaymentResponse)
def sandbox_fail_payment(
    transaction_id: str,
    db: Session = Depends(get_db)
):
    """
    Sandbox payment failure endpoint.
    Simulates a failed payment — releases seat holds.
    """
    payment = db.query(models.Payment).filter(
        models.Payment.gateway_transaction_id == transaction_id
    ).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment transaction not found")

    payment.status = "failed"
    payment.gateway_response = {
        "sandbox": True,
        "message": "Sandbox payment failed",
        "failed_at": datetime.datetime.utcnow().isoformat()
    }

    # Revert booking status
    booking = db.query(models.Booking).filter(models.Booking.id == payment.booking_id).first()
    if booking:
        booking.payment_status = "failed"
        booking.booking_status = "cancelled"

        # Release seat holds
        db.query(models.SeatHold).filter(
            models.SeatHold.trip_id == booking.trip_id,
            models.SeatHold.user_id == booking.passenger_id,
            models.SeatHold.is_released == False
        ).update({"is_released": True})

    db.commit()
    db.refresh(payment)
    return payment


@router.post("/webhook", status_code=status.HTTP_200_OK)
async def payment_webhook(
    payload: schemas.PaymentWebhookPayload,
    db: Session = Depends(get_db)
):
    """
    Generic payment gateway webhook endpoint.
    In production, this would validate signatures from PayHere/Stripe.
    """
    payment = db.query(models.Payment).filter(
        models.Payment.gateway_transaction_id == payload.transaction_id
    ).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Transaction not found")

    if payload.status == "completed":
        payment.status = "completed"
        payment.paid_at = datetime.datetime.utcnow()
        payment.gateway_response = payload.gateway_data

        booking = db.query(models.Booking).filter(models.Booking.id == payment.booking_id).first()
        if booking:
            booking.payment_status = "paid"
            booking.booking_status = "confirmed"
            # Release hold — seats permanently frozen
            db.query(models.SeatHold).filter(
                models.SeatHold.trip_id == booking.trip_id,
                models.SeatHold.user_id == booking.passenger_id,
                models.SeatHold.is_released == False
            ).update({"is_released": True})

            # Trigger notifications
            await _send_booking_notifications(db, booking)

    elif payload.status == "failed":
        payment.status = "failed"
        payment.gateway_response = payload.gateway_data

        booking = db.query(models.Booking).filter(models.Booking.id == payment.booking_id).first()
        if booking:
            booking.payment_status = "failed"
            booking.booking_status = "cancelled"
            db.query(models.SeatHold).filter(
                models.SeatHold.trip_id == booking.trip_id,
                models.SeatHold.user_id == booking.passenger_id,
                models.SeatHold.is_released == False
            ).update({"is_released": True})

    db.commit()
    return {"status": "ok", "payment_id": str(payment.id)}


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
