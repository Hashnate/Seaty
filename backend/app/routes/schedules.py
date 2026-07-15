from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import UUID
import uuid
import datetime

from app.database import get_db
from app import models, schemas, auth

router = APIRouter(prefix="/schedules", tags=["Schedules"])

@router.post("", response_model=schemas.TripScheduleResponse, status_code=status.HTTP_201_CREATED)
def create_schedule(
    schedule_in: schemas.TripScheduleCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["owner", "admin", "conductor"]))
):
    # Enforce vehicle owner/conductor check
    if current_user.role in ["owner", "conductor"]:
        vehicle = db.query(models.Vehicle).filter(
            models.Vehicle.id == schedule_in.vehicle_id,
            models.Vehicle.company_id == current_user.company_id
        ).first()
        if not vehicle:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only schedule trips for vehicles you own."
            )
        if not vehicle.is_verified:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="You cannot schedule trips for an unverified vehicle."
            )

    # Verify route exists
    route = db.query(models.Route).filter(models.Route.id == schedule_in.route_id).first()
    if not route:
        raise HTTPException(status_code=404, detail="Route template not found")

    cond_id = None
    if schedule_in.conductor_id:
        conductor_user = db.query(models.User).filter(
            models.User.id == schedule_in.conductor_id,
            models.User.role == "conductor"
        ).first()
        if not conductor_user or (current_user.role != "admin" and conductor_user.company_id != current_user.company_id):
            raise HTTPException(status_code=400, detail="Invalid conductor ID or conductor belongs to another company")
        cond_id = schedule_in.conductor_id

    db_schedule = models.TripSchedule(
        id=uuid.uuid4(),
        vehicle_id=schedule_in.vehicle_id,
        route_id=schedule_in.route_id,
        departure_time=schedule_in.departure_time,
        arrival_time=schedule_in.arrival_time,
        price_per_seat=schedule_in.price_per_seat,
        schedule_type=schedule_in.schedule_type,
        custom_days=schedule_in.custom_days or [],
        effective_from=schedule_in.effective_from,
        effective_until=schedule_in.effective_until,
        is_active=True,
        conductor_id=cond_id
    )
    db.add(db_schedule)
    db.commit()
    db.refresh(db_schedule)
    
    db_schedule.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == db_schedule.vehicle_id).first()
    db_schedule.route = db.query(models.Route).filter(models.Route.id == db_schedule.route_id).first()
    db_schedule.conductor = db.query(models.User).filter(models.User.id == db_schedule.conductor_id).first()
    
    return db_schedule

@router.get("", response_model=List[schemas.TripScheduleResponse])
def list_schedules(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    query = db.query(models.TripSchedule).join(models.Vehicle)
    
    if current_user.role == "owner":
        query = query.filter(models.Vehicle.company_id == current_user.company_id)
    elif current_user.role == "conductor":
        query = query.filter(models.TripSchedule.conductor_id == current_user.id)
    
    schedules = query.all()
    
    for s in schedules:
        s.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == s.vehicle_id).first()
        s.route = db.query(models.Route).filter(models.Route.id == s.route_id).first()
        s.conductor = db.query(models.User).filter(models.User.id == s.conductor_id).first()
        
    return schedules

@router.get("/{schedule_id}", response_model=schemas.TripScheduleResponse)
def get_schedule(
    schedule_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    schedule = db.query(models.TripSchedule).filter(models.TripSchedule.id == schedule_id).first()
    if not schedule:
        raise HTTPException(status_code=404, detail="Schedule not found")
        
    vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == schedule.vehicle_id).first()
    if current_user.role != "admin" and (not vehicle or vehicle.company_id != current_user.company_id):
        raise HTTPException(status_code=403, detail="Unauthorized access to this schedule")
        
    schedule.vehicle = vehicle
    schedule.route = db.query(models.Route).filter(models.Route.id == schedule.route_id).first()
    schedule.conductor = db.query(models.User).filter(models.User.id == schedule.conductor_id).first()
    return schedule

@router.put("/{schedule_id}", response_model=schemas.TripScheduleResponse)
def update_schedule(
    schedule_id: UUID,
    schedule_in: schemas.TripScheduleUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    schedule = db.query(models.TripSchedule).filter(models.TripSchedule.id == schedule_id).first()
    if not schedule:
        raise HTTPException(status_code=404, detail="Schedule not found")
        
    current_vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == schedule.vehicle_id).first()
    if current_user.role != "admin" and (not current_vehicle or current_vehicle.company_id != current_user.company_id):
        raise HTTPException(status_code=403, detail="Unauthorized to modify this schedule")

    if schedule_in.vehicle_id is not None:
        if current_user.role in ["owner", "conductor"]:
            new_vehicle = db.query(models.Vehicle).filter(
                models.Vehicle.id == schedule_in.vehicle_id,
                models.Vehicle.company_id == current_user.company_id
            ).first()
            if not new_vehicle:
                raise HTTPException(status_code=403, detail="You do not own this vehicle")
            if not new_vehicle.is_verified:
                raise HTTPException(status_code=400, detail="Cannot schedule trips for an unverified vehicle")
        schedule.vehicle_id = schedule_in.vehicle_id

    if schedule_in.route_id is not None:
        route = db.query(models.Route).filter(models.Route.id == schedule_in.route_id).first()
        if not route:
            raise HTTPException(status_code=404, detail="Route template not found")
        schedule.route_id = schedule_in.route_id

    if schedule_in.departure_time is not None:
        schedule.departure_time = schedule_in.departure_time
    if schedule_in.arrival_time is not None:
        schedule.arrival_time = schedule_in.arrival_time
    if schedule_in.price_per_seat is not None:
        schedule.price_per_seat = schedule_in.price_per_seat
    if schedule_in.schedule_type is not None:
        schedule.schedule_type = schedule_in.schedule_type
    if schedule_in.custom_days is not None:
        schedule.custom_days = schedule_in.custom_days
    if schedule_in.effective_from is not None:
        schedule.effective_from = schedule_in.effective_from
    if schedule_in.effective_until is not None:
        schedule.effective_until = schedule_in.effective_until
    if schedule_in.is_active is not None:
        schedule.is_active = schedule_in.is_active
    if schedule_in.conductor_id is not None:
        conductor_user = db.query(models.User).filter(
            models.User.id == schedule_in.conductor_id,
            models.User.role == "conductor"
        ).first()
        if not conductor_user or (current_user.role != "admin" and conductor_user.company_id != current_user.company_id):
            raise HTTPException(status_code=400, detail="Invalid conductor ID or conductor belongs to another company")
        schedule.conductor_id = schedule_in.conductor_id
    elif "conductor_id" in schedule_in.model_dump(exclude_unset=True):
        # Allow removing the assigned conductor if sent explicitly as None
        schedule.conductor_id = None
        
    # Retroactively update future trips generated from this schedule
    now = datetime.datetime.now(datetime.timezone.utc)
    db.query(models.Trip).filter(
        models.Trip.schedule_id == schedule.id,
        models.Trip.departure_time >= now
    ).update({"conductor_id": schedule.conductor_id}, synchronize_session=False)

    schedule.updated_at = datetime.datetime.utcnow()
    db.commit()
    db.refresh(schedule)
    
    schedule.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == schedule.vehicle_id).first()
    schedule.route = db.query(models.Route).filter(models.Route.id == schedule.route_id).first()
    schedule.conductor = db.query(models.User).filter(models.User.id == schedule.conductor_id).first()
    return schedule

@router.patch("/{schedule_id}/toggle", response_model=schemas.TripScheduleResponse)
def toggle_schedule(
    schedule_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    schedule = db.query(models.TripSchedule).filter(models.TripSchedule.id == schedule_id).first()
    if not schedule:
        raise HTTPException(status_code=404, detail="Schedule not found")
        
    vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == schedule.vehicle_id).first()
    if current_user.role != "admin" and (not vehicle or vehicle.company_id != current_user.company_id):
        raise HTTPException(status_code=403, detail="Unauthorized")
        
    schedule.is_active = not schedule.is_active
    schedule.updated_at = datetime.datetime.utcnow()
    db.commit()
    db.refresh(schedule)
    
    schedule.vehicle = vehicle
    schedule.route = db.query(models.Route).filter(models.Route.id == schedule.route_id).first()
    return schedule

@router.delete("/{schedule_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_schedule(
    schedule_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    schedule = db.query(models.TripSchedule).filter(models.TripSchedule.id == schedule_id).first()
    if not schedule:
        raise HTTPException(status_code=404, detail="Schedule not found")
        
    vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == schedule.vehicle_id).first()
    if current_user.role != "admin" and (not vehicle or vehicle.company_id != current_user.company_id):
        raise HTTPException(status_code=403, detail="Unauthorized to delete this schedule")
        
    db.delete(schedule)
    db.commit()
    return {}

# ==========================================
# Bus Overrides Endpoints
# ==========================================

@router.post("/{schedule_id}/overrides", response_model=schemas.BusOverrideResponse, status_code=status.HTTP_201_CREATED)
def create_override(
    schedule_id: UUID,
    override_in: schemas.BusOverrideCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    schedule = db.query(models.TripSchedule).filter(models.TripSchedule.id == schedule_id).first()
    if not schedule:
        raise HTTPException(status_code=404, detail="Schedule not found")
        
    # Check permissions (must own the schedule's vehicle company)
    sched_vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == schedule.vehicle_id).first()
    if current_user.role != "admin" and (not sched_vehicle or sched_vehicle.company_id != current_user.company_id):
        raise HTTPException(status_code=403, detail="Unauthorized to override this schedule")
        
    # Check replacement vehicle exists, is verified, and belongs to company
    rep_vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == override_in.replacement_vehicle_id).first()
    if not rep_vehicle:
        raise HTTPException(status_code=404, detail="Replacement vehicle not found")
        
    if current_user.role in ["owner", "conductor"]:
        if rep_vehicle.company_id != current_user.company_id:
            raise HTTPException(status_code=403, detail="Replacement vehicle does not belong to your company")
        if not rep_vehicle.is_verified:
            raise HTTPException(status_code=400, detail="Replacement vehicle is not verified")

    # If there is already an override for this date, delete or update it
    existing = db.query(models.BusOverride).filter(
        models.BusOverride.schedule_id == schedule_id,
        models.BusOverride.override_date == override_in.override_date
    ).first()
    
    if existing:
        db.delete(existing)
        db.commit()

    db_override = models.BusOverride(
        id=uuid.uuid4(),
        schedule_id=schedule_id,
        override_date=override_in.override_date,
        replacement_vehicle_id=override_in.replacement_vehicle_id,
        reason=override_in.reason
    )
    db.add(db_override)
    db.commit()
    db.refresh(db_override)
    
    # If a trip instance has already been generated for this schedule on this override_date, update its vehicle_id!
    # Compute timezone-aware datetime ranges or just match date
    generated_trips = db.query(models.Trip).filter(
        models.Trip.schedule_id == schedule_id
    ).all()
    for trip in generated_trips:
        if trip.departure_time.date() == override_in.override_date:
            trip.vehicle_id = override_in.replacement_vehicle_id
            db.commit()
            
    db_override.replacement_vehicle = rep_vehicle
    return db_override

@router.get("/{schedule_id}/overrides", response_model=List[schemas.BusOverrideResponse])
def get_overrides(
    schedule_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    schedule = db.query(models.TripSchedule).filter(models.TripSchedule.id == schedule_id).first()
    if not schedule:
        raise HTTPException(status_code=404, detail="Schedule not found")
        
    sched_vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == schedule.vehicle_id).first()
    if current_user.role != "admin" and (not sched_vehicle or sched_vehicle.company_id != current_user.company_id):
        raise HTTPException(status_code=403, detail="Unauthorized to view overrides")
        
    overrides = db.query(models.BusOverride).filter(models.BusOverride.schedule_id == schedule_id).all()
    for o in overrides:
        o.replacement_vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == o.replacement_vehicle_id).first()
        
    return overrides

@router.delete("/overrides/{override_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_override(
    override_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    override = db.query(models.BusOverride).filter(models.BusOverride.id == override_id).first()
    if not override:
        raise HTTPException(status_code=404, detail="Override not found")
        
    # Check permissions
    rep_vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == override.replacement_vehicle_id).first()
    if current_user.role != "admin" and (not rep_vehicle or rep_vehicle.company_id != current_user.company_id):
        raise HTTPException(status_code=403, detail="Unauthorized")
        
    # Revert the generated trip vehicle if it exists
    schedule = db.query(models.TripSchedule).filter(models.TripSchedule.id == override.schedule_id).first()
    if schedule:
        generated_trips = db.query(models.Trip).filter(models.Trip.schedule_id == schedule.id).all()
        for trip in generated_trips:
            if trip.departure_time.date() == override.override_date:
                trip.vehicle_id = schedule.vehicle_id
                db.commit()
                
    db.delete(override)
    db.commit()
    return {}
