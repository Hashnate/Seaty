from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID
import uuid
import datetime

from app.database import get_db
from app import models, schemas, auth

router = APIRouter(prefix="/banners", tags=["Hero Banners"])


@router.get("", response_model=List[schemas.HeroBannerResponse])
def list_banners(
    include_inactive: bool = Query(False, description="Admin console use - include hidden banners"),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_optional_current_user)
):
    """Hero carousel images for the passenger home screen.

    Public by design: the mobile app fetches this before sign-in. Hidden
    banners are only ever returned to an authenticated admin.
    """
    query = db.query(models.HeroBanner)

    is_admin = current_user is not None and current_user.role == "admin"
    if not (include_inactive and is_admin):
        query = query.filter(models.HeroBanner.is_active == True)

    return query.order_by(
        models.HeroBanner.sort_order.asc(),
        models.HeroBanner.created_at.asc(),
    ).all()


@router.post("", response_model=schemas.HeroBannerResponse, status_code=status.HTTP_201_CREATED)
def create_banner(
    banner_in: schemas.HeroBannerCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    """Add a hero banner. Admin only."""
    if not banner_in.image_url.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="An image is required for a hero banner."
        )

    now = datetime.datetime.now(datetime.timezone.utc)
    db_banner = models.HeroBanner(
        id=uuid.uuid4(),
        image_url=banner_in.image_url.strip(),
        title=banner_in.title,
        subtitle=banner_in.subtitle,
        sort_order=banner_in.sort_order,
        is_active=banner_in.is_active,
        created_at=now,
        updated_at=now,
    )
    db.add(db_banner)
    db.commit()
    db.refresh(db_banner)
    return db_banner


@router.patch("/{banner_id}", response_model=schemas.HeroBannerResponse)
def update_banner(
    banner_id: UUID,
    banner_in: schemas.HeroBannerUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    """Edit a hero banner - image, copy, order or visibility. Admin only."""
    banner = db.query(models.HeroBanner).filter(models.HeroBanner.id == banner_id).first()
    if not banner:
        raise HTTPException(status_code=404, detail="Banner not found")

    updates = banner_in.model_dump(exclude_unset=True)

    if "image_url" in updates:
        new_url = (updates["image_url"] or "").strip()
        if not new_url:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="An image is required for a hero banner."
            )
        updates["image_url"] = new_url

    for field, value in updates.items():
        setattr(banner, field, value)

    banner.updated_at = datetime.datetime.now(datetime.timezone.utc)
    db.commit()
    db.refresh(banner)
    return banner


@router.delete("/{banner_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_banner(
    banner_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    """Remove a hero banner. Admin only."""
    banner = db.query(models.HeroBanner).filter(models.HeroBanner.id == banner_id).first()
    if not banner:
        raise HTTPException(status_code=404, detail="Banner not found")

    db.delete(banner)
    db.commit()
    return None
