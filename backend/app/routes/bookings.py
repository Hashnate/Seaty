from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID
import uuid
import datetime

from app.database import get_db
from app import models, schemas, auth
from app.routes.seat_holds import get_unavailable_seats

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
    # Verify trip exists
    trip = db.query(models.Trip).filter(models.Trip.id == booking_in.trip_id).first()
    if not trip:
        raise HTTPException(status_code=404, detail="Scheduled trip not found")

    if trip.status in ["completed", "cancelled"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Cannot book seats on a trip that is already {trip.status}."
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

    # Preload details for response
    db_booking.trip = trip
    db_booking.passenger = current_user
    db_booking.trip.route = db.query(models.Route).filter(models.Route.id == trip.route_id).first()
    db_booking.trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
    return db_booking


@router.get("", response_model=List[schemas.BookingResponse])
def list_bookings(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    if current_user.role == "admin":
        bookings = db.query(models.Booking).all()
    elif current_user.role == "owner":
        # Get bookings for trips scheduled on vehicles belonging to their company
        bookings = db.query(models.Booking).join(models.Trip).join(models.Vehicle).filter(
            models.Vehicle.company_id == current_user.company_id
        ).all()
    else:
        # Passengers get their own bookings
        bookings = db.query(models.Booking).filter(models.Booking.passenger_id == current_user.id).all()

    # Populate nested structures for returning to client
    for booking in bookings:
        booking.trip = db.query(models.Trip).filter(models.Trip.id == booking.trip_id).first()
        booking.passenger = db.query(models.User).filter(models.User.id == booking.passenger_id).first()
        if booking.trip:
            booking.trip.route = db.query(models.Route).filter(models.Route.id == booking.trip.route_id).first()
            booking.trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == booking.trip.vehicle_id).first()

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
        if vehicle.company_id != current_user.company_id:
            raise HTTPException(status_code=403, detail="Unauthorized to view this company's booking")

    booking.trip = db.query(models.Trip).filter(models.Trip.id == booking.trip_id).first()
    booking.passenger = db.query(models.User).filter(models.User.id == booking.passenger_id).first()
    if booking.trip:
        booking.trip.route = db.query(models.Route).filter(models.Route.id == booking.trip.route_id).first()
        booking.trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == booking.trip.vehicle_id).first()

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

    booking.trip = db.query(models.Trip).filter(models.Trip.id == booking.trip_id).first()
    booking.passenger = current_user
    if booking.trip:
        booking.trip.route = db.query(models.Route).filter(models.Route.id == booking.trip.route_id).first()
        booking.trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == booking.trip.vehicle_id).first()

    return booking
