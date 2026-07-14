from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID
import uuid

from app.database import get_db
from app import models, schemas, auth

router = APIRouter(prefix="/vehicles", tags=["Vehicles"])

@router.post("", response_model=schemas.VehicleResponse, status_code=status.HTTP_201_CREATED)
def create_vehicle(
    vehicle_in: schemas.VehicleCreate, 
    db: Session = Depends(get_db), 
    current_user: models.User = Depends(auth.RoleChecker(["owner", "admin"]))
):
    db_vehicle = models.Vehicle(
        id=uuid.uuid4(),
        owner_id=current_user.id,
        company_id=current_user.company_id,  # Auto-assign to owner's company
        name=vehicle_in.name,
        registration_number=vehicle_in.registration_number,
        type=vehicle_in.type,
        seat_layout=vehicle_in.seat_layout,
        total_seats=vehicle_in.total_seats,
        amenities=vehicle_in.amenities,
        document_urls=vehicle_in.document_urls,
        is_verified=False # Requires admin review and approval
    )
    db.add(db_vehicle)
    db.commit()
    db.refresh(db_vehicle)
    return db_vehicle

@router.get("", response_model=List[schemas.VehicleResponse])
def list_vehicles(
    db: Session = Depends(get_db), 
    current_user: models.User = Depends(auth.get_current_user)
):
    if current_user.role == "admin":
        # Admins see everything
        return db.query(models.Vehicle).all()
    elif current_user.role == "owner":
        # Owners see their own vehicles (verified or not)
        return db.query(models.Vehicle).filter(models.Vehicle.owner_id == current_user.id).all()
    else:
        # Passengers only see verified vehicles
        return db.query(models.Vehicle).filter(models.Vehicle.is_verified == True).all()

@router.get("/{vehicle_id}", response_model=schemas.VehicleResponse)
def get_vehicle(
    vehicle_id: UUID, 
    db: Session = Depends(get_db), 
    current_user: models.User = Depends(auth.get_current_user)
):
    vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == vehicle_id).first()
    if not vehicle:
        raise HTTPException(status_code=404, detail="Vehicle not found")
    
    # Hide unverified vehicles from other passengers
    if not vehicle.is_verified and current_user.role != "admin" and vehicle.owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="Unauthorized access to unverified vehicle")
    
    return vehicle

@router.post("/{vehicle_id}/approve", response_model=schemas.VehicleResponse)
def approve_vehicle(
    vehicle_id: UUID, 
    db: Session = Depends(get_db), 
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == vehicle_id).first()
    if not vehicle:
        raise HTTPException(status_code=404, detail="Vehicle not found")
    
    vehicle.is_verified = True
    db.commit()
    db.refresh(vehicle)
    return vehicle

@router.post("/{vehicle_id}/reject", response_model=schemas.VehicleResponse)
def reject_vehicle(
    vehicle_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    """Reject/unverify a vehicle (admin only)."""
    vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == vehicle_id).first()
    if not vehicle:
        raise HTTPException(status_code=404, detail="Vehicle not found")
    
    vehicle.is_verified = False
    db.commit()
    db.refresh(vehicle)
    return vehicle
