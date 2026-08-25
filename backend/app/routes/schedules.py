from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import UUID
import uuid
import datetime

from app.database import get_db
from app import models, schemas, auth, permissions
from app.timezone_utils import now_sl

router = APIRouter(prefix="/schedules", tags=["Schedules"])

@router.post("", response_model=schemas.TripScheduleResponse, status_code=status.HTTP_201_CREATED)
def create_schedule(
    schedule_in: schemas.TripScheduleCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(list(permissions.MANAGER_ROLES)))
):
    vehicle = permissions.require_vehicle(db, current_user, schedule_in.vehicle_id)
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
        cond_id = permissions.require_conductor(db, current_user, schedule_in.conductor_id).id

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
        query = permissions.scope_vehicles(query, current_user)
    elif current_user.role == "conductor":
        query = query.filter(models.TripSchedule.conductor_id == current_user.id)
    elif current_user.role != "admin":
        # Schedules are operator planning data, not a passenger-facing resource.
        query = query.filter(False)


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
    current_user: models.User = Depends(auth.RoleChecker(list(permissions.MANAGER_ROLES)))
):
    schedule = permissions.require_schedule(db, current_user, schedule_id)
    vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == schedule.vehicle_id).first()

    schedule.vehicle = vehicle
    schedule.route = db.query(models.Route).filter(models.Route.id == schedule.route_id).first()
    schedule.conductor = db.query(models.User).filter(models.User.id == schedule.conductor_id).first()
    return schedule

@router.put("/{schedule_id}", response_model=schemas.TripScheduleResponse)
def update_schedule(
    schedule_id: UUID,
    schedule_in: schemas.TripScheduleUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(list(permissions.MANAGER_ROLES)))
):
    schedule = permissions.require_schedule(db, current_user, schedule_id)

    if schedule_in.vehicle_id is not None:
        new_vehicle = permissions.require_vehicle(db, current_user, schedule_in.vehicle_id)
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
        schedule.conductor_id = permissions.require_conductor(
            db, current_user, schedule_in.conductor_id
        ).id
    elif "conductor_id" in schedule_in.model_dump(exclude_unset=True):
        # Allow removing the assigned conductor if sent explicitly as None
        schedule.conductor_id = None
        
    # Retroactively update future trips generated from this schedule
    now = now_sl()
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
    current_user: models.User = Depends(auth.RoleChecker(list(permissions.MANAGER_ROLES)))
):
    """Flip `is_active` - whether this schedule keeps materialising new trips.

    Note this is *not* the temporary off switch: trips already generated from
    this schedule (up to 5 days ahead) stay on sale. Use
    `PATCH /{schedule_id}/booking` to take the service off sale immediately.
    """
    schedule = permissions.require_schedule(db, current_user, schedule_id)

    schedule.is_active = not schedule.is_active
    schedule.updated_at = datetime.datetime.utcnow()
    db.commit()
    db.refresh(schedule)

    schedule.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == schedule.vehicle_id).first()
    schedule.route = db.query(models.Route).filter(models.Route.id == schedule.route_id).first()
    return schedule


@router.patch("/{schedule_id}/booking", response_model=schemas.TripScheduleResponse)
def set_schedule_booking_enabled(
    schedule_id: UUID,
    body: schemas.BookingToggle,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(list(permissions.MANAGER_ROLES)))
):
    """Temporarily take a recurring service off sale, or put it back on.

    Covers the gap `toggle` leaves: turning a schedule inactive stops *future*
    materialisation but leaves the trips it already generated for the next few
    days fully bookable. This closes those too, in one call, and reopens them
    the same way.
    """
    schedule = permissions.require_schedule(db, current_user, schedule_id)

    schedule.booking_enabled = body.enabled
    schedule.suspension_reason = None if body.enabled else (body.reason or None)
    schedule.updated_at = datetime.datetime.utcnow()
    db.commit()

    if not body.enabled:
        # Free seats held on this service's live trips - those holds can no
        # longer turn into bookings.
        trip_ids = [
            t.id for t in db.query(models.Trip.id).filter(
                models.Trip.schedule_id == schedule.id,
                models.Trip.departure_time >= now_sl(),
            ).all()
        ]
        if trip_ids:
            db.query(models.SeatHold).filter(
                models.SeatHold.trip_id.in_(trip_ids),
                models.SeatHold.is_released == False,
            ).update({"is_released": True}, synchronize_session=False)
            db.commit()

    db.refresh(schedule)
    schedule.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == schedule.vehicle_id).first()
    schedule.route = db.query(models.Route).filter(models.Route.id == schedule.route_id).first()
    schedule.conductor = db.query(models.User).filter(models.User.id == schedule.conductor_id).first()
    return schedule


@router.delete("/{schedule_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_schedule(
    schedule_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(list(permissions.MANAGER_ROLES)))
):
    """Hard-delete a schedule. Refused while a paid booking rides on its trips.

    `trips.schedule_id` is ON DELETE SET NULL, but the admin UI's own warning
    ("this will delete all generated trips") reflects what operators expect, so
    guard the money the same way the trip and vehicle deletes do.
    """
    schedule = permissions.require_schedule(db, current_user, schedule_id)

    paid = db.query(models.Booking).join(
        models.Trip, models.Booking.trip_id == models.Trip.id
    ).filter(
        models.Trip.schedule_id == schedule.id,
        models.Booking.payment_status == "paid",
        models.Booking.booking_status.notin_(["cancelled", "expired"]),
    ).count()
    if paid:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"This schedule has {paid} paid booking(s) on its trips and cannot be "
                f"deleted. Switch off bookings for it instead, or cancel those trips."
            ),
        )

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
    current_user: models.User = Depends(auth.RoleChecker(list(permissions.MANAGER_ROLES)))
):
    # Both the schedule and the bus being swapped in must belong to the caller.
    permissions.require_schedule(db, current_user, schedule_id)
    rep_vehicle = permissions.require_vehicle(db, current_user, override_in.replacement_vehicle_id)
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
    current_user: models.User = Depends(auth.RoleChecker(list(permissions.MANAGER_ROLES)))
):
    permissions.require_schedule(db, current_user, schedule_id)

    overrides = db.query(models.BusOverride).filter(models.BusOverride.schedule_id == schedule_id).all()
    for o in overrides:
        o.replacement_vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == o.replacement_vehicle_id).first()
        
    return overrides

@router.delete("/overrides/{override_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_override(
    override_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(list(permissions.MANAGER_ROLES)))
):
    override = db.query(models.BusOverride).filter(models.BusOverride.id == override_id).first()
    if not override:
        raise HTTPException(status_code=404, detail="Override not found")

    # Scope on the schedule that owns the override, not on the replacement
    # vehicle: the replacement can legitimately be another company's bus, and
    # checking that one instead let its owner delete a swap they do not own.
    permissions.require_schedule(db, current_user, override.schedule_id)


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
