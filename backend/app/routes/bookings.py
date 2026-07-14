from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID
import uuid

from app.database import get_db
from app import models, schemas, auth

router = APIRouter(prefix="/bookings", tags=["Bookings"])

@router.post("", response_model=schemas.BookingResponse, status_code=status.HTTP_201_CREATED)
def create_booking(
    booking_in: schemas.BookingCreate, 
    db: Session = Depends(get_db), 
    current_user: models.User = Depends(auth.RoleChecker(["passenger", "admin"]))
):
    # Verify trip exists
    trip = db.query(models.Trip).filter(models.Trip.id == booking_in.trip_id).first()
    if not trip:
        raise HTTPException(status_code=404, detail="Scheduled trip not found")
        
    if trip.status in ["completed", "cancelled"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Cannot book seats on a trip that is already {trip.status}."
        )

    # Check if seats are already booked
    existing_bookings = db.query(models.Booking).filter(
        models.Booking.trip_id == booking_in.trip_id,
        models.Booking.booking_status == "confirmed"
    ).all()
    
    booked_seats = set()
    for b in existing_bookings:
        booked_seats.update(b.selected_seats)
        
    # Intersection of selected and already booked seats
    overlap = booked_seats.intersection(booking_in.selected_seats)
    if overlap:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Seats {list(overlap)} are already booked for this trip."
        )

    # Calculate total price
    total_price = trip.price_per_seat * len(booking_in.selected_seats)

    db_booking = models.Booking(
        id=uuid.uuid4(),
        trip_id=booking_in.trip_id,
        passenger_id=current_user.id,
        selected_seats=booking_in.selected_seats,
        total_price=total_price,
        payment_status="pending",
        booking_status="confirmed"
    )
    db.add(db_booking)
    db.commit()
    db.refresh(db_booking)
    
    # Preload details
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
        # Get bookings for trips scheduled on vehicles they own
        bookings = db.query(models.Booking).join(models.Trip).join(models.Vehicle).filter(
            models.Vehicle.owner_id == current_user.id
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
        if vehicle.owner_id != current_user.id:
            raise HTTPException(status_code=403, detail="Unauthorized to view this vehicle's booking")
            
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
    db.commit()
    db.refresh(booking)
    
    booking.trip = db.query(models.Trip).filter(models.Trip.id == booking.trip_id).first()
    booking.passenger = current_user
    if booking.trip:
        booking.trip.route = db.query(models.Route).filter(models.Route.id == booking.trip.route_id).first()
        booking.trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == booking.trip.vehicle_id).first()
        
    return booking
