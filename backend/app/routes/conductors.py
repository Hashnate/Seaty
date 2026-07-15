from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID
import uuid

from app.database import get_db
from app import models, schemas, auth

router = APIRouter(prefix="/conductors", tags=["Conductors"])

@router.get("", response_model=List[schemas.UserResponse])
def list_conductors(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["owner", "admin"]))
):
    """List all conductors/staff registered under the current owner's company."""
    if current_user.role == "admin":
        return db.query(models.User).filter(models.User.role == "conductor").all()
        
    return db.query(models.User).filter(
        models.User.role == "conductor",
        models.User.company_id == current_user.company_id
    ).all()

@router.post("", response_model=schemas.UserResponse, status_code=status.HTTP_201_CREATED)
def create_conductor(
    payload: schemas.ConductorCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["owner"]))
):
    """Add a new conductor staff member (conductor/driver) linked to the owner's company."""
    # Ensure owner has a company
    if not current_user.company_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Current owner user is not associated with any bus company."
        )
        
    # Check if user already exists
    existing = db.query(models.User).filter(models.User.email == payload.email).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A user with this email is already registered."
        )
        
    existing_phone = db.query(models.User).filter(
        models.User.phone_number == payload.phone_number,
        models.User.role == "conductor"
    ).first()
    if existing_phone:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A staff member with this phone number is already registered."
        )

    db_conductor = models.User(
        id=uuid.uuid4(),
        email=payload.email,
        hashed_password=auth.get_password_hash(payload.password),
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
    conductor = db.query(models.User).filter(
        models.User.id == conductor_id,
        models.User.role == "conductor"
    ).first()
    
    if not conductor:
        raise HTTPException(status_code=404, detail="Conductor record not found")
        
    # Enforce company RBAC
    if current_user.role != "admin" and conductor.company_id != current_user.company_id:
        raise HTTPException(status_code=403, detail="Unauthorized to remove this staff member")
        
    db.delete(conductor)
    db.commit()
    return {}
