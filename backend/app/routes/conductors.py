from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID
import uuid

from app.database import get_db
from app import models, schemas, auth, permissions

router = APIRouter(prefix="/conductors", tags=["Conductors"])

@router.get("", response_model=List[schemas.UserResponse])
def list_conductors(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["owner", "admin"]))
):
    """List all conductors/staff registered under the current owner's company."""
    query = db.query(models.User).filter(models.User.role == "conductor")
    if current_user.role == "admin":
        return query.all()
    if current_user.company_id is None:
        # Without this an owner with no company would match every conductor
        # whose company_id is also NULL.
        return []
    return query.filter(models.User.company_id == current_user.company_id).all()

@router.post("", response_model=schemas.UserResponse, status_code=status.HTTP_201_CREATED)
def create_conductor(
    payload: schemas.ConductorCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["owner"]))
):
    """Add a new conductor staff member linked to the owner's company."""
    # Ensure owner has a company
    if not current_user.company_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Current owner user is not associated with any bus company."
        )

    # Auto-generate email from phone number (same pattern as /auth/phone/register)
    email = f"{payload.phone_number}@seaty.lk"
        
    # Check if conductor already exists with this phone
    existing_phone = db.query(models.User).filter(
        models.User.phone_number == payload.phone_number,
        models.User.role == "conductor"
    ).first()
    if existing_phone:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A conductor with this phone number is already registered."
        )

    # Check if email already taken
    existing_email = db.query(models.User).filter(models.User.email == email).first()
    if existing_email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A user with this identifier is already registered."
        )

    db_conductor = models.User(
        id=uuid.uuid4(),
        email=email,
        hashed_password=auth.unusable_password_hash(),
        full_name=payload.full_name,
        phone_number=payload.phone_number,
        role="conductor",
        company_id=current_user.company_id
    )
    db.add(db_conductor)
    db.commit()
    db.refresh(db_conductor)
    return db_conductor

@router.delete("/{conductor_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_conductor(
    conductor_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["owner", "admin"]))
):
    """Delete a conductor staff member."""
    conductor = permissions.require_conductor(db, current_user, conductor_id)

    db.delete(conductor)
    db.commit()
    return {}
