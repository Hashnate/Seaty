from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID
import uuid

from app.database import get_db
from app import models, schemas, auth

router = APIRouter(prefix="/vehicles", tags=["Vehicles"])

@router.post("", response_model=schemas.VehicleResponse, status_code=status.HTTP_201_CREATED)
async def create_vehicle(
    vehicle_in: schemas.VehicleCreate, 
    db: Session = Depends(get_db), 
    current_user: models.User = Depends(auth.RoleChecker(["owner", "admin", "conductor"]))
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
        contact_phone=vehicle_in.contact_phone,
        main_image_url=vehicle_in.main_image_url,
        gallery_image_urls=vehicle_in.gallery_image_urls[:5] if vehicle_in.gallery_image_urls else [],
        is_verified=False # Requires admin review and approval
    )
    db.add(db_vehicle)
    db.commit()
    db.refresh(db_vehicle)

    # Notify Admins
    try:
        from app.routes.notifications import create_and_send_notification
        admins = db.query(models.User).filter(models.User.role == "admin").all()
        for admin in admins:
            await create_and_send_notification(
                db=db,
                user_id=admin.id,
                title="New Vehicle Registered",
                message=f"New vehicle verification request: Owner {current_user.full_name} registered vehicle {db_vehicle.registration_number} ({db_vehicle.name}).",
                noti_type="verification",
                vehicle_id=db_vehicle.id
            )
    except Exception as noti_err:
        print(f"Notification Error: {noti_err}")

    return db_vehicle

@router.get("", response_model=List[schemas.VehicleResponse])
def list_vehicles(
    db: Session = Depends(get_db), 
    current_user: models.User = Depends(auth.get_current_user)
):
    if current_user.role == "admin":
        # Admins see everything
        return db.query(models.Vehicle).all()
    elif current_user.role in ["owner", "conductor"]:
        # Owners and conductors see vehicles belonging to their company
        return db.query(models.Vehicle).filter(models.Vehicle.company_id == current_user.company_id).all()
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
async def approve_vehicle(
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

    # Notify Owner
    try:
        from app.routes.notifications import create_and_send_notification
        await create_and_send_notification(
            db=db,
            user_id=vehicle.owner_id,
            title="Vehicle Verification Approved!",
            message=f"Congratulations! Your vehicle {vehicle.registration_number} ({vehicle.name}) has been verified and is ready to schedule trips.",
            noti_type="verification",
            vehicle_id=vehicle.id
        )
    except Exception as noti_err:
        print(f"Notification Error: {noti_err}")

    return vehicle

@router.post("/{vehicle_id}/reject", response_model=schemas.VehicleResponse)
async def reject_vehicle(
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

    # Notify Owner
    try:
        from app.routes.notifications import create_and_send_notification
        await create_and_send_notification(
            db=db,
            user_id=vehicle.owner_id,
            title="Vehicle Verification Rejected",
            message=f"Your vehicle registration for {vehicle.registration_number} ({vehicle.name}) was rejected. Please review submitted documents.",
            noti_type="verification",
            vehicle_id=vehicle.id
        )
    except Exception as noti_err:
        print(f"Notification Error: {noti_err}")

    return vehicle

@router.delete("/{vehicle_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_vehicle(
    vehicle_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == vehicle_id).first()
    if not vehicle:
        raise HTTPException(status_code=404, detail="Vehicle not found")
        
    if current_user.role != "admin" and (current_user.role not in ["owner", "conductor"] or vehicle.company_id != current_user.company_id):
        raise HTTPException(status_code=403, detail="Unauthorized to delete this vehicle")
        
    db.delete(vehicle)
    db.commit()
    return {}

@router.put("/{vehicle_id}", response_model=schemas.VehicleResponse)
def update_vehicle(
    vehicle_id: UUID,
    vehicle_in: schemas.VehicleCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == vehicle_id).first()
    if not vehicle:
        raise HTTPException(status_code=404, detail="Vehicle not found")
        
    if current_user.role != "admin" and (current_user.role not in ["owner", "conductor"] or vehicle.company_id != current_user.company_id):
        raise HTTPException(status_code=403, detail="Unauthorized to update this vehicle")
        
    vehicle.name = vehicle_in.name
    vehicle.registration_number = vehicle_in.registration_number
    vehicle.type = vehicle_in.type
    vehicle.seat_layout = vehicle_in.seat_layout
    vehicle.total_seats = vehicle_in.total_seats
    vehicle.amenities = vehicle_in.amenities
    vehicle.document_urls = vehicle_in.document_urls
    vehicle.contact_phone = vehicle_in.contact_phone
    vehicle.main_image_url = vehicle_in.main_image_url
    vehicle.gallery_image_urls = vehicle_in.gallery_image_urls[:5] if vehicle_in.gallery_image_urls else []
    vehicle.is_verified = False  # Reset verification on edit
    
    db.commit()
    db.refresh(vehicle)
    return vehicle
