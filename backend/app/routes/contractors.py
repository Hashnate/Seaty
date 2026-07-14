from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID
import uuid

from app.database import get_db
from app import models, schemas, auth

router = APIRouter(prefix="/contractors", tags=["Contractors"])

@router.get("", response_model=List[schemas.UserResponse])
def list_contractors(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["owner", "admin"]))
):
    """List all contractors/staff registered under the current owner's company."""
    if current_user.role == "admin":
        return db.query(models.User).filter(models.User.role == "contractor").all()
        
    return db.query(models.User).filter(
        models.User.role == "contractor",
        models.User.company_id == current_user.company_id
    ).all()

@router.post("", response_model=schemas.UserResponse, status_code=status.HTTP_201_CREATED)
def create_contractor(
    payload: schemas.ContractorCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["owner"]))
):
    """Add a new contractor staff member (conductor/driver) linked to the owner's company."""
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
        models.User.role == "contractor"
    ).first()
    if existing_phone:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A staff member with this phone number is already registered."
        )

    db_contractor = models.User(
        id=uuid.uuid4(),
        email=payload.email,
        hashed_password=auth.get_password_hash(payload.password),
        full_name=payload.full_name,
        phone_number=payload.phone_number,
        role="contractor",
        company_id=current_user.company_id
    )
    db.add(db_contractor)
    db.commit()
    db.refresh(db_contractor)
    return db_contractor

@router.delete("/{contractor_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_contractor(
    contractor_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["owner", "admin"]))
):
    """Delete a contractor staff member."""
    contractor = db.query(models.User).filter(
        models.User.id == contractor_id,
        models.User.role == "contractor"
    ).first()
    
    if not contractor:
        raise HTTPException(status_code=404, detail="Contractor record not found")
        
    # Enforce company RBAC
    if current_user.role != "admin" and contractor.company_id != current_user.company_id:
        raise HTTPException(status_code=403, detail="Unauthorized to remove this staff member")
        
    db.delete(contractor)
    db.commit()
    return {}
