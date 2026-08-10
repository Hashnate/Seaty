from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID
import uuid
import datetime

from app.database import get_db
from app import models, schemas, auth
from app.timezone_utils import now_sl, to_sl

router = APIRouter(prefix="/seat-holds", tags=["Seat Holds"])


def _get_hold_duration(db: Session) -> int:
    """Get configured seat hold duration in minutes."""
    setting = db.query(models.PlatformSetting).filter(
        models.PlatformSetting.key == "seat_hold_duration_minutes"
    ).first()
    return int(setting.value) if setting else 10


def get_unavailable_seats(db: Session, trip_id: UUID) -> dict:
    """
    Returns all seats that are currently unavailable for a given trip.
    Includes both confirmed bookings and active (non-expired) holds.
    """
    now = datetime.datetime.utcnow()

    # Get confirmed/paid booking seats
    confirmed_bookings = db.query(models.Booking).filter(
        models.Booking.trip_id == trip_id,
        models.Booking.booking_status.in_(models.OCCUPIED_BOOKING_STATUSES),
        models.Booking.payment_status == "paid"
    ).all()

    booked_seats = set()
    for b in confirmed_bookings:
        booked_seats.update(b.selected_seats)

    # Get actively held seats (not expired, not released)
    active_holds = db.query(models.SeatHold).filter(
        models.SeatHold.trip_id == trip_id,
        models.SeatHold.is_released == False,
        models.SeatHold.expires_at > now
    ).all()

    held_seats = set()
    for h in active_holds:
        held_seats.update(h.seat_labels)

    # Remove overlap (booked seats take priority over holds)
    held_seats = held_seats - booked_seats

    return {
        "booked": list(booked_seats),
        "held": list(held_seats)
    }


@router.post("", response_model=schemas.SeatHoldResponse, status_code=status.HTTP_201_CREATED)
def create_seat_hold(
    hold_in: schemas.SeatHoldCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["passenger", "admin"]))
):
    """
    Temporarily hold seats for a trip while the user completes payment.
    Held seats cannot be booked by other users until the hold expires.
    """
    # Verify trip exists and is bookable
    trip = db.query(models.Trip).filter(models.Trip.id == hold_in.trip_id).first()
    if not trip:
        raise HTTPException(status_code=404, detail="Trip not found")

    if trip.status in ["completed", "cancelled"]:
        raise HTTPException(status_code=400, detail=f"Cannot hold seats on a {trip.status} trip")

    # 30-minute pre-departure cutoff validation
    now = now_sl()
    dep_time = to_sl(trip.departure_time)
    if now >= (dep_time - datetime.timedelta(minutes=30)):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Online seat holds for this bus closed 30 minutes prior to departure."
        )

    # Check seat availability
    unavailable = get_unavailable_seats(db, hold_in.trip_id)
    all_unavailable = set(unavailable["booked"]) | set(unavailable["held"])
    overlap = all_unavailable.intersection(hold_in.seat_labels)

    if overlap:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Seats {list(overlap)} are already booked or held by another user."
        )

    # Release any existing holds by this user for this trip
    db.query(models.SeatHold).filter(
        models.SeatHold.trip_id == hold_in.trip_id,
        models.SeatHold.user_id == current_user.id,
        models.SeatHold.is_released == False
    ).update({"is_released": True})

    # Create new hold
    hold_minutes = _get_hold_duration(db)
    expires_at = datetime.datetime.utcnow() + datetime.timedelta(minutes=hold_minutes)

    db_hold = models.SeatHold(
        id=uuid.uuid4(),
        trip_id=hold_in.trip_id,
        user_id=current_user.id,
        seat_labels=hold_in.seat_labels,
        expires_at=expires_at,
        is_released=False
    )
    db.add(db_hold)
    db.commit()
    db.refresh(db_hold)
    return db_hold


@router.get("/trip/{trip_id}", response_model=schemas.TripSeatsResponse)
def get_trip_seat_availability(
    trip_id: UUID,
    db: Session = Depends(get_db)
):
    """
    Get real-time seat availability for a trip.
    Returns booked seats, held seats, and available seats.
    """
    trip = db.query(models.Trip).filter(models.Trip.id == trip_id).first()
    if not trip:
        raise HTTPException(status_code=404, detail="Trip not found")

    vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
    if not vehicle:
        raise HTTPException(status_code=404, detail="Vehicle not found")

    unavailable = get_unavailable_seats(db, trip_id)

    # Generate all seat labels based on vehicle layout
    all_seats = []
    layout = vehicle.seat_layout or {}
    if "seats" in layout and isinstance(layout["seats"], list):
        for s in layout["seats"]:
            if isinstance(s, dict) and "label" in s:
                all_seats.append(str(s["label"]))
    else:
        total = vehicle.total_seats or 40
        all_seats = [str(i) for i in range(1, total + 1)]

    # Find genders for the booked seats
    confirmed_bookings = db.query(models.Booking).filter(
        models.Booking.trip_id == trip_id,
        models.Booking.booking_status.in_(models.OCCUPIED_BOOKING_STATUSES),
        models.Booking.payment_status == "paid"
    ).all()

    seat_genders = {}
    for b in confirmed_bookings:
        if not b.selected_seats:
            continue
        primary_seat = b.selected_seats[0]
        details = b.passenger_details or {}
        primary_details = details.get("primary", {})
        primary_gender = primary_details.get("gender", "Male")
        seat_genders[primary_seat] = primary_gender.lower()
        
        # Map guests
        guests = details.get("guests", [])
        for guest in guests:
            g_seat = guest.get("seat")
            g_gender = guest.get("gender", "Female")
            if g_seat:
                seat_genders[g_seat] = g_gender.lower()

    all_unavailable = set(unavailable["booked"]) | set(unavailable["held"])
    available = [s for s in all_seats if s not in all_unavailable]
    valid_booked = [s for s in unavailable["booked"] if s in all_seats]
    valid_held = [s for s in unavailable["held"] if s in all_seats]

    return schemas.TripSeatsResponse(
        trip_id=trip_id,
        total_seats=vehicle.total_seats,
        booked_seats=valid_booked,
        held_seats=valid_held,
        available_seats=available,
        seat_genders=seat_genders
    )


@router.delete("/{hold_id}", status_code=status.HTTP_204_NO_CONTENT)
def release_seat_hold(
    hold_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    """Manually release a seat hold."""
    hold = db.query(models.SeatHold).filter(models.SeatHold.id == hold_id).first()
    if not hold:
        raise HTTPException(status_code=404, detail="Seat hold not found")

    if hold.user_id != current_user.id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Unauthorized")

    hold.is_released = True
    db.commit()


@router.post("/cleanup", status_code=status.HTTP_200_OK)
def cleanup_expired_holds(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    """
    Manually trigger cleanup of all expired seat holds.
    Also automatically called on app startup and periodically.
    """
    now = datetime.datetime.utcnow()
    expired_count = db.query(models.SeatHold).filter(
        models.SeatHold.expires_at <= now,
        models.SeatHold.is_released == False
    ).update({"is_released": True})

    # Also cancel bookings that were awaiting payment and their holds expired
    expired_holds = db.query(models.SeatHold).filter(
        models.SeatHold.expires_at <= now,
        models.SeatHold.is_released == True
    ).all()

    cancelled_bookings = 0
    for hold in expired_holds:
        pending_bookings = db.query(models.Booking).filter(
            models.Booking.trip_id == hold.trip_id,
            models.Booking.passenger_id == hold.user_id,
            models.Booking.payment_status == "awaiting_payment"
        ).all()
        for booking in pending_bookings:
            booking.payment_status = "failed"
            booking.booking_status = "cancelled"
            cancelled_bookings += 1

    db.commit()
    return {
        "expired_holds_released": expired_count,
        "cancelled_bookings": cancelled_bookings
    }
