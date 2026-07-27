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

    passenger_name = review_in.passenger_name or current_user.full_name or "Anonymous Passenger"

    new_review = models.Review(
        id=uuid.uuid4(),
        vehicle_id=vehicle_id,
        user_id=current_user.id,
        passenger_name=passenger_name,
        rating=review_in.rating,
        comment=review_in.comment,
    )
    db.add(new_review)
    db.commit()
    db.refresh(new_review)
    return new_review
