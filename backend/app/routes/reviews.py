from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from uuid import UUID
import uuid

from app.database import get_db
from app import models, schemas, auth

router = APIRouter(prefix="/vehicles", tags=["Reviews"])

@router.get("/{vehicle_id}/reviews", response_model=schemas.ReviewSummaryResponse)
def get_vehicle_reviews(vehicle_id: UUID, db: Session = Depends(get_db)):
    vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == vehicle_id).first()
    if not vehicle:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Vehicle not found."
        )

    reviews = db.query(models.Review).filter(
        models.Review.vehicle_id == vehicle_id
    ).order_by(models.Review.created_at.desc()).all()

    total = len(reviews)
    if total > 0:
        avg_rating = round(sum(r.rating for r in reviews) / total, 1)
    else:
        avg_rating = 0.0

    return {
        "average_rating": avg_rating,
        "total_reviews": total,
        "reviews": reviews
    }

import datetime

@router.post("/{vehicle_id}/reviews", response_model=schemas.ReviewResponse, status_code=status.HTTP_201_CREATED)
def create_vehicle_review(
    vehicle_id: UUID,
    review_in: schemas.ReviewCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == vehicle_id).first()
    if not vehicle:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Vehicle not found."
        )

    # 1. Condition 1: Check if user has paid bookings for trips operated by this vehicle
    user_bookings = db.query(models.Booking).join(models.Trip).filter(
        models.Trip.vehicle_id == vehicle_id,
        models.Booking.passenger_id == current_user.id,
        models.Booking.payment_status == "paid"
    ).all()

    if not user_bookings:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only review buses you have booked a ticket for."
        )

    # Filter by specific booking if provided
    if review_in.booking_id:
        target_b = next((b for b in user_bookings if b.id == review_in.booking_id), None)
        if target_b:
            user_bookings = [target_b]

    now_utc = datetime.datetime.now(datetime.timezone.utc)
    valid_booking = None

    # 2 & 3. Condition 2 & 3: Ticket scanned by conductor & departure time commenced
    for b in user_bookings:
        trip = db.query(models.Trip).filter(models.Trip.id == b.trip_id).first()
        if not trip:
            continue

        dep_time = trip.departure_time
        if dep_time and dep_time.tzinfo is None:
            dep_time = dep_time.replace(tzinfo=datetime.timezone.utc)

        # Condition 3: Departure time must have commenced
        if dep_time and dep_time > now_utc:
            continue

        # Condition 2: Scanned by conductor or completed
        boarded = set(trip.boarded_seats or [])
        seats = set(b.selected_seats or [])
        is_scanned = (len(seats) > 0 and seats.issubset(boarded)) or (b.booking_status == "completed")

        if is_scanned:
            valid_booking = b
            break

    if not valid_booking:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only review this bus after your ticket has been scanned by the conductor upon boarding."
        )

    # 4. Condition 4: One review per completed booking
    existing = db.query(models.Review).filter(
        models.Review.booking_id == valid_booking.id
    ).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You have already submitted a review for this completed journey."
        )

    passenger_name = review_in.passenger_name or current_user.full_name or "Passenger"

    new_review = models.Review(
        id=uuid.uuid4(),
        vehicle_id=vehicle_id,
        user_id=current_user.id,
        booking_id=valid_booking.id,
        passenger_name=passenger_name,
        rating=review_in.rating,
        comment=review_in.comment,
    )
    db.add(new_review)
    db.commit()
    db.refresh(new_review)
    return new_review
