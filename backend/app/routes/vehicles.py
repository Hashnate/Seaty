from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID
import datetime
import uuid

from app.database import get_db
from app import models, schemas, auth, permissions

router = APIRouter(prefix="/vehicles", tags=["Vehicles"])

@router.post("", response_model=schemas.VehicleResponse, status_code=status.HTTP_201_CREATED)
async def create_vehicle(
    vehicle_in: schemas.VehicleCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(list(permissions.MANAGER_ROLES)))
):
    # `company_id` comes from the caller's own account, never from the request
    # body - a vehicle can only ever be registered into the registrant's
    # company. An admin has no company, so an admin-registered vehicle is
    # unassigned until an owner claims it; permissions.same_company() makes
    # sure that unassigned state grants nobody access.
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
    if current_user.role in ("admin", "owner", "conductor"):
        # Staff see their own company's fleet; admins see every company.
        # scope_vehicles() refuses to match on a NULL company_id, so a staff
        # account with no company sees nothing rather than everything
        # unassigned.
        return permissions.scope_vehicles(db.query(models.Vehicle), current_user).all()
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
    vehicle = permissions.require_vehicle(db, current_user, vehicle_id)

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
    vehicle = permissions.require_vehicle(db, current_user, vehicle_id)

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

@router.patch("/{vehicle_id}/booking", response_model=schemas.VehicleResponse)
def set_vehicle_booking_enabled(
    vehicle_id: UUID,
    body: schemas.BookingToggle,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(list(permissions.MANAGER_ROLES)))
):
    """Temporarily take a whole bus off sale, or put it back on.

    Every trip on this vehicle - already generated or generated later - stops
    being offered to passengers while the switch is off, without touching any
    trip's own state. Turning it back on restores all of them at once.

    Deliberately separate from `is_verified`, which is admin-only document
    approval and is not the operator's to flip.
    """
    vehicle = permissions.require_vehicle(db, current_user, vehicle_id)

    vehicle.booking_enabled = body.enabled
    vehicle.suspension_reason = None if body.enabled else (body.reason or None)
    vehicle.updated_at = datetime.datetime.utcnow()
    db.commit()

    # Holds on this bus cannot become bookings while it is off sale, so free
    # the seats instead of leaving them blocked until they expire.
    if not body.enabled:
        trip_ids = [
            t.id for t in db.query(models.Trip.id).filter(
                models.Trip.vehicle_id == vehicle.id,
                models.Trip.status.in_(["scheduled", "ongoing"]),
            ).all()
        ]
        if trip_ids:
            db.query(models.SeatHold).filter(
                models.SeatHold.trip_id.in_(trip_ids),
                models.SeatHold.is_released == False,
            ).update({"is_released": True}, synchronize_session=False)
            db.commit()

    db.refresh(vehicle)
    return vehicle


@router.delete("/{vehicle_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_vehicle(
    vehicle_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(list(permissions.MANAGER_ROLES)))
):
    """Hard-delete a bus. Refused while any paid booking rides on it.

    Deleting a vehicle cascades through its trips into bookings and payments,
    so this would silently destroy the records that paid passengers and the
    money are reconciled against. Take the bus off sale instead
    (`PATCH /{vehicle_id}/booking`), or cancel the affected trips first so
    passengers are notified and refunds are queued.
    """
    vehicle = permissions.require_vehicle(db, current_user, vehicle_id)

    paid = db.query(models.Booking).join(
        models.Trip, models.Booking.trip_id == models.Trip.id
    ).filter(
        models.Trip.vehicle_id == vehicle.id,
        models.Booking.payment_status == "paid",
        models.Booking.booking_status.notin_(["cancelled", "expired"]),
    ).count()
    if paid:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"This bus has {paid} paid booking(s) across its trips and cannot be "
                f"deleted. Switch off bookings for it, or cancel those trips first."
            ),
        )

    db.delete(vehicle)
    db.commit()
    return {}

@router.put("/{vehicle_id}", response_model=schemas.VehicleResponse)
def update_vehicle(
    vehicle_id: UUID,
    vehicle_in: schemas.VehicleCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(list(permissions.MANAGER_ROLES)))
):
    vehicle = permissions.require_vehicle(db, current_user, vehicle_id)

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
