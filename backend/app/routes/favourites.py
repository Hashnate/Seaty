from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID

from app.database import get_db
from app import models, schemas, auth

router = APIRouter(prefix="/favourites", tags=["Favourites"])


@router.post("/toggle")
def toggle_favourite(
    payload: schemas.FavouriteToggleRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    """Toggle favourite state for a vehicle/schedule."""
    query = db.query(models.UserFavourite).filter(
        models.UserFavourite.user_id == current_user.id,
        models.UserFavourite.vehicle_id == payload.vehicle_id
    )
    if payload.schedule_id:
        query = query.filter(models.UserFavourite.schedule_id == payload.schedule_id)

    existing = query.first()

    if existing:
        db.delete(existing)
        db.commit()
        return {"favourited": False, "message": "Removed from favourites"}
    else:
        new_fav = models.UserFavourite(
            user_id=current_user.id,
            vehicle_id=payload.vehicle_id,
            schedule_id=payload.schedule_id
        )
        db.add(new_fav)
        db.commit()
        return {"favourited": True, "message": "Saved to favourites"}


@router.get("", response_model=List[schemas.FavouriteResponse])
def get_user_favourites(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    """Get all favourites for current user."""
    return db.query(models.UserFavourite).filter(
        models.UserFavourite.user_id == current_user.id
    ).all()


@router.get("/ids")
def get_user_favourite_ids(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    """Get arrays of favourite vehicle_ids and schedule_ids for easy client checking."""
    favs = db.query(models.UserFavourite).filter(
        models.UserFavourite.user_id == current_user.id
    ).all()
    
    vehicle_ids = list(set([str(f.vehicle_id) for f in favs if f.vehicle_id]))
    schedule_ids = list(set([str(f.schedule_id) for f in favs if f.schedule_id]))

    return {
        "vehicle_ids": vehicle_ids,
        "schedule_ids": schedule_ids
    }
