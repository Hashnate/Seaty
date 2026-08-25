"""Is this trip on sale right now?

One question, asked from five different places (search results, seat map, seat
hold, booking creation, payment initiation). Each of those used to answer it
with its own subset of the rules, which is how a trip could be hidden from
search and still bookable by anyone who kept the seat-map screen open.

The switches, outermost first. The first one that says no, wins - and the
reason it gives is the one the passenger sees:

    1. platform_settings['bookings_enabled']  - global kill switch
    2. bus_companies.is_active                - company suspended by admin
    3. vehicles.is_verified                   - documents not approved
    4. vehicles.booking_enabled               - whole bus temporarily off
    5. trip_schedules.booking_enabled         - this recurring run temporarily off
    6. trips.booking_enabled                  - this one instance temporarily off
    7. trips.status                           - cancelled / completed / ongoing

Levels 4-6 are the reversible "temporarily off" switches. Turning any of them
back on restores the trip to passenger search immediately, with its bookings
intact - that is the whole point of keeping them separate from
`status='cancelled'`, which is one-way and refunds everybody.
"""
from typing import Optional

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app import models


def bookings_globally_enabled(db: Session) -> bool:
    setting = db.query(models.PlatformSetting).filter(
        models.PlatformSetting.key == "bookings_enabled"
    ).first()
    if setting is None:
        # Absent setting means an older database that predates the switch.
        # Fail open: the platform was selling seats before this existed.
        return True
    return str(setting.value).strip().lower() not in ("false", "0", "no", "off")


def sale_block_reason(
    db: Session,
    trip: models.Trip,
    vehicle: Optional[models.Vehicle] = None,
    schedule: Optional[models.TripSchedule] = None,
) -> Optional[str]:
    """Why this trip cannot be sold, or None if it can.

    `vehicle` and `schedule` may be passed in by callers that have already
    loaded them (the search listing loads a vehicle per trip anyway), to keep
    this off the per-row query path.
    """
    if not bookings_globally_enabled(db):
        return "Bookings are temporarily unavailable. Please try again later."

    if vehicle is None:
        vehicle = db.query(models.Vehicle).filter(
            models.Vehicle.id == trip.vehicle_id
        ).first()
    if vehicle is None:
        return "This bus is no longer available."

    if vehicle.company_id is not None:
        company = db.query(models.BusCompany).filter(
            models.BusCompany.id == vehicle.company_id
        ).first()
        if company is not None and not company.is_active:
            return "This operator is not currently accepting bookings."

    if not vehicle.is_verified:
        return "This bus is not currently available for booking."

    if not vehicle.booking_enabled:
        return vehicle.suspension_reason or "This bus is temporarily not accepting bookings."

    if schedule is None and trip.schedule_id is not None:
        schedule = db.query(models.TripSchedule).filter(
            models.TripSchedule.id == trip.schedule_id
        ).first()
    if schedule is not None and not schedule.booking_enabled:
        return schedule.suspension_reason or "This service is temporarily suspended."

    if not trip.booking_enabled:
        return trip.suspension_reason or "This trip is temporarily unavailable."

    if trip.status == "cancelled":
        return "This trip has been cancelled."
    if trip.status == "completed":
        return "This trip has already been completed."
    if trip.status == "ongoing":
        return "This trip has already departed."

    return None


def is_on_sale(
    db: Session,
    trip: models.Trip,
    vehicle: Optional[models.Vehicle] = None,
    schedule: Optional[models.TripSchedule] = None,
) -> bool:
    return sale_block_reason(db, trip, vehicle, schedule) is None


def assert_bookable(
    db: Session,
    trip: models.Trip,
    vehicle: Optional[models.Vehicle] = None,
    schedule: Optional[models.TripSchedule] = None,
) -> None:
    """Raise 409 with the passenger-facing reason if this trip is not on sale.

    409 rather than 400: the request is well-formed, the resource state is what
    refuses it, and the mobile app already treats 409 on the booking path as
    "show this message and refresh the seat map".
    """
    reason = sale_block_reason(db, trip, vehicle, schedule)
    if reason is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=reason)
