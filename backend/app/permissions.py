"""Company scoping for the admin console.

Role gating (`auth.RoleChecker`) answers "may this *kind* of user call this
endpoint". It is never enough on its own: an owner is allowed to manage trips,
but only *their* trips. This module answers the second half - "does this
specific row belong to the caller's company" - in one place, so every route
enforces it identically.

Two hazards this exists to remove:

1. `a.company_id != b.company_id` is `False` when both are `NULL`, so the
   obvious inline check silently grants access. An admin-created vehicle has a
   NULL `company_id` and a passenger has a NULL `company_id`, which made that
   an exploitable pairing rather than a theoretical one. `same_company()`
   treats `None` as matching nothing, ever.

2. `get_current_user` plus an inline `if role in [...]` block drifts per route.
   Every helper below takes an already role-gated user and only decides
   ownership, so the two concerns cannot be confused.

Access model:

    admin      - every company, every row
    owner      - rows belonging to their own company_id
    conductor  - operational only; may read/act on trips assigned to them, and
                 may never reach the management helpers here
    passenger  - never
"""
from typing import Optional
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app import models

# Roles that may manage fleet resources at all. Conductors are deliberately
# absent: they operate trips (manifest, boarding, ongoing/completed) but do not
# create, edit, delete, or suspend them. See CLAUDE.md's account hierarchy.
MANAGER_ROLES = ("admin", "owner")


def same_company(a: Optional[UUID], b: Optional[UUID]) -> bool:
    """True only when both sides name the same real company.

    `None` never matches, including `None` against `None`. Do not replace this
    with `==`; an unassigned row must not be visible to an unassigned user.
    """
    return a is not None and b is not None and a == b


def is_admin(user: models.User) -> bool:
    return user.role == "admin"


def _deny(what: str) -> HTTPException:
    # Same shape for "belongs to another company" and "does not exist" so the
    # endpoint cannot be used to probe for IDs outside the caller's company.
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail=f"{what} not found",
    )


def require_vehicle(db: Session, user: models.User, vehicle_id: UUID) -> models.Vehicle:
    """Load a vehicle the caller is allowed to manage, or raise."""
    vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == vehicle_id).first()
    if not vehicle:
        raise _deny("Vehicle")
    if is_admin(user):
        return vehicle
    if not same_company(vehicle.company_id, user.company_id):
        raise _deny("Vehicle")
    return vehicle


def require_trip(db: Session, user: models.User, trip_id: UUID) -> models.Trip:
    """Load a trip the caller is allowed to manage, or raise.

    A trip belongs to whoever owns its vehicle. Conductors are handled by
    `require_operable_trip` instead - they get a narrower door.
    """
    trip = db.query(models.Trip).filter(models.Trip.id == trip_id).first()
    if not trip:
        raise _deny("Trip")
    if is_admin(user):
        return trip
    vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
    if not vehicle or not same_company(vehicle.company_id, user.company_id):
        raise _deny("Trip")
    return trip


def require_operable_trip(db: Session, user: models.User, trip_id: UUID) -> models.Trip:
    """Load a trip the caller may *operate* (manifest, boarding, run status).

    Wider than `require_trip` by exactly one case: the conductor assigned to
    this trip. It grants nothing else - a conductor still cannot reach the
    management helpers.
    """
    trip = db.query(models.Trip).filter(models.Trip.id == trip_id).first()
    if not trip:
        raise _deny("Trip")
    if is_admin(user):
        return trip
    if user.role == "conductor":
        if trip.conductor_id is not None and trip.conductor_id == user.id:
            return trip
        raise _deny("Trip")
    vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
    if not vehicle or not same_company(vehicle.company_id, user.company_id):
        raise _deny("Trip")
    return trip


def require_schedule(db: Session, user: models.User, schedule_id: UUID) -> models.TripSchedule:
    """Load a schedule the caller is allowed to manage, or raise."""
    schedule = db.query(models.TripSchedule).filter(
        models.TripSchedule.id == schedule_id
    ).first()
    if not schedule:
        raise _deny("Schedule")
    if is_admin(user):
        return schedule
    vehicle = db.query(models.Vehicle).filter(
        models.Vehicle.id == schedule.vehicle_id
    ).first()
    if not vehicle or not same_company(vehicle.company_id, user.company_id):
        raise _deny("Schedule")
    return schedule


def require_conductor(db: Session, user: models.User, conductor_id: UUID) -> models.User:
    """Load a conductor account the caller is allowed to manage, or raise."""
    conductor = db.query(models.User).filter(
        models.User.id == conductor_id,
        models.User.role == "conductor",
    ).first()
    if not conductor:
        raise _deny("Conductor")
    if is_admin(user):
        return conductor
    if not same_company(conductor.company_id, user.company_id):
        raise _deny("Conductor")
    return conductor


def scope_vehicles(query, user: models.User):
    """Restrict a `Vehicle` query to what the caller may see."""
    if is_admin(user):
        return query
    if user.company_id is None:
        # An owner with no company owns nothing. Without this the NULL-vs-NULL
        # comparison below would match every unassigned vehicle on the platform.
        return query.filter(False)
    return query.filter(models.Vehicle.company_id == user.company_id)
