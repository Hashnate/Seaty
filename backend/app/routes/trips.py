from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import UUID
import uuid
import datetime

from app.database import get_db
from app import models, schemas, auth

router = APIRouter(prefix="/trips", tags=["Trips"])

@router.post("", response_model=schemas.TripResponse, status_code=status.HTTP_201_CREATED)
def create_trip(
    trip_in: schemas.TripCreate, 
    db: Session = Depends(get_db), 
    current_user: models.User = Depends(auth.RoleChecker(["owner", "admin"]))
):
    # If owner, verify the vehicle belongs to their company
    if current_user.role == "owner":
        vehicle = db.query(models.Vehicle).filter(
            models.Vehicle.id == trip_in.vehicle_id,
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
    route = db.query(models.Route).filter(models.Route.id == trip_in.route_id).first()
    if not route:
        raise HTTPException(status_code=404, detail="Route not found")

    db_trip = models.Trip(
        id=uuid.uuid4(),
        vehicle_id=trip_in.vehicle_id,
        route_id=trip_in.route_id,
        departure_time=trip_in.departure_time,
        arrival_time=trip_in.arrival_time,
        price_per_seat=trip_in.price_per_seat,
        status="scheduled"
    )
    db.add(db_trip)
    db.commit()
    db.refresh(db_trip)
    return db_trip

@router.get("", response_model=List[schemas.TripResponse])
def list_trips(
    origin: Optional[str] = Query(None, description="Start terminal location"),
    destination: Optional[str] = Query(None, description="End terminal location"),
    date: Optional[str] = Query(None, description="Trip date in YYYY-MM-DD format"),
    db: Session = Depends(get_db),
    current_user: Optional[models.User] = Depends(auth.get_optional_current_user)
):
    query = db.query(models.Trip).join(models.Route).join(models.Vehicle)
    
    if current_user and current_user.role == "owner":
        query = query.filter(models.Vehicle.company_id == current_user.company_id)
    
    # Filter by date
    if date:
        try:
            target_date = datetime.datetime.strptime(date, "%Y-%m-%d").date()
            start_time = datetime.datetime.combine(target_date, datetime.time.min)
            end_time = datetime.datetime.combine(target_date, datetime.time.max)
            
            # Generate trips from active schedules if date is within next 5 days
            today = datetime.date.today()
            max_future_date = today + datetime.timedelta(days=5)
            
            if today <= target_date <= max_future_date:
                sched_query = db.query(models.TripSchedule).filter(
                    models.TripSchedule.is_active == True,
                    models.TripSchedule.effective_from <= target_date
                )
                sched_query = sched_query.filter(
                    (models.TripSchedule.effective_until == None) | (models.TripSchedule.effective_until >= target_date)
                )
                
                # If owner, filter schedules by their company
                if current_user and current_user.role == "owner":
                    sched_query = sched_query.join(models.Vehicle).filter(
                        models.Vehicle.company_id == current_user.company_id
                    )
                    
                schedules = sched_query.all()
                weekday = target_date.weekday()  # 0=Mon, 6=Sun
                
                for sched in schedules:
                    match = False
                    if sched.schedule_type == "daily":
                        match = True
                    elif sched.schedule_type == "weekdays":
                        match = weekday < 5
                    elif sched.schedule_type == "weekends":
                        match = weekday >= 5
                    elif sched.schedule_type == "custom":
                        match = weekday in (sched.custom_days or [])
                        
                    if match:
                        # Check if trip already exists for this schedule and target date
                        existing_trip = db.query(models.Trip).filter(
                            models.Trip.schedule_id == sched.id,
                            models.Trip.departure_time >= start_time,
                            models.Trip.departure_time <= end_time
                        ).first()
                        
                        if not existing_trip:
                            # Check for a bus override
                            override = db.query(models.BusOverride).filter(
                                models.BusOverride.schedule_id == sched.id,
                                models.BusOverride.override_date == target_date
                            ).first()
                            
                            veh_id = override.replacement_vehicle_id if override else sched.vehicle_id
                            
                            # Construct departure/arrival times
                            dep_time = datetime.datetime.combine(target_date, sched.departure_time)
                            if sched.arrival_time < sched.departure_time:
                                arr_time = datetime.datetime.combine(target_date + datetime.timedelta(days=1), sched.arrival_time)
                            else:
                                arr_time = datetime.datetime.combine(target_date, sched.arrival_time)
                                
                            new_trip = models.Trip(
                                id=uuid.uuid4(),
                                vehicle_id=veh_id,
                                route_id=sched.route_id,
                                schedule_id=sched.id,
                                departure_time=dep_time,
                                arrival_time=arr_time,
                                price_per_seat=sched.price_per_seat,
                                status="scheduled"
                            )
                            db.add(new_trip)
                            db.commit()
            
            query = query.filter(
                models.Trip.departure_time >= start_time,
                models.Trip.departure_time <= end_time
            )
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid date format. Use YYYY-MM-DD"
            )
            
    trips = query.all()
    
    # Preload nested structures and filter matching routes (including intermediate stops)
    filtered_trips = []
    for trip in trips:
        trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
        trip.route = db.query(models.Route).filter(models.Route.id == trip.route_id).first()
        
        # Verify route match with intermediate stops
        if trip.route:
            match = True
            
            # Helper to find position of a location in route stops (-1 = origin, index = stop index, 100000 = destination)
            def find_stop_position(search_loc: str) -> Optional[int]:
                search_normalized = search_loc.lower().strip()
                if search_normalized in trip.route.origin.lower():
                    return -1
                
                # Check intermediate stops
                stops = trip.route.stops or []
                for idx, stop in enumerate(stops):
                    if search_normalized in stop.get("name", "").lower():
                        return idx
                
                if search_normalized in trip.route.destination.lower():
                    return 100000
                return None

            if origin:
                origin_pos = find_stop_position(origin)
                if origin_pos is None:
                    match = False
                
            if destination:
                dest_pos = find_stop_position(destination)
                if dest_pos is None:
                    match = False
                
            # If both are specified, ensure origin comes before destination
            if origin and destination and match:
                o_pos = find_stop_position(origin)
                d_pos = find_stop_position(destination)
                if o_pos is not None and d_pos is not None and o_pos >= d_pos:
                    match = False
                    
            if match:
                filtered_trips.append(trip)
        else:
            # If no route exists (should not happen), keep it if no filters are specified
            if not origin and not destination:
                filtered_trips.append(trip)
                
    return filtered_trips

@router.get("/{trip_id}", response_model=schemas.TripResponse)
def get_trip(trip_id: UUID, db: Session = Depends(get_db)):
    trip = db.query(models.Trip).filter(models.Trip.id == trip_id).first()
    if not trip:
        raise HTTPException(status_code=404, detail="Trip not found")
        
    trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
    trip.route = db.query(models.Route).filter(models.Route.id == trip.route_id).first()
    return trip

@router.patch("/{trip_id}/status", response_model=schemas.TripResponse)
async def update_trip_status(
    trip_id: UUID, 
    status: str = Query(..., description="scheduled, ongoing, completed, cancelled"), 
    db: Session = Depends(get_db), 
    current_user: models.User = Depends(auth.RoleChecker(["owner", "admin"]))
):
    trip = db.query(models.Trip).filter(models.Trip.id == trip_id).first()
    if not trip:
        raise HTTPException(status_code=404, detail="Trip not found")
        
    # Verify owner permissions
    if current_user.role == "owner":
        vehicle = db.query(models.Vehicle).filter(
            models.Vehicle.id == trip.vehicle_id,
            models.Vehicle.company_id == current_user.company_id
        ).first()
        if not vehicle:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You are not authorized to update trips for this vehicle."
            )
            
    if status not in ["scheduled", "ongoing", "completed", "cancelled"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid status type."
        )
        
    old_status = trip.status
    trip.status = status
    db.commit()
    db.refresh(trip)
    
    # Notify passengers if status goes from scheduled -> ongoing / cancelled
    if status != old_status and status in ["ongoing", "cancelled"]:
        bookings = db.query(models.Booking).filter(
            models.Booking.trip_id == trip.id,
            models.Booking.booking_status == "confirmed"
        ).all()
        for b in bookings:
            try:
                from app.routes.notifications import create_and_send_notification
                route = db.query(models.Route).filter(models.Route.id == trip.route_id).first()
                origin = route.origin if route else "Origin"
                destination = route.destination if route else "Destination"
                date_str = trip.departure_time.strftime("%Y-%m-%d %H:%M")
                
                title = f"Trip {status.capitalize()}!"
                if status == "cancelled":
                    msg = f"Your trip from {origin} to {destination} scheduled for {date_str} has been cancelled. A refund has been initiated."
                else: # ongoing
                    msg = f"Your trip from {origin} to {destination} is now active (ongoing)! Safe travels."
                    
                await create_and_send_notification(
                    db=db,
                    user_id=b.passenger_id,
                    title=title,
                    message=msg,
                    noti_type="trip_update"
                )
            except Exception as noti_err:
                print(f"Notification Error: {noti_err}")

    trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
    trip.route = db.query(models.Route).filter(models.Route.id == trip.route_id).first()
    return trip

@router.put("/{trip_id}", response_model=schemas.TripResponse)
async def update_trip(
    trip_id: UUID,
    trip_in: schemas.TripCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    trip = db.query(models.Trip).filter(models.Trip.id == trip_id).first()
    if not trip:
        raise HTTPException(status_code=404, detail="Trip not found")
        
    # Verify owner permissions
    if current_user.role == "owner":
        # Check current vehicle owner
        current_vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
        if not current_vehicle or current_vehicle.company_id != current_user.company_id:
            raise HTTPException(status_code=403, detail="Unauthorized to update this trip")
            
        # Check new vehicle owner
        new_vehicle = db.query(models.Vehicle).filter(
            models.Vehicle.id == trip_in.vehicle_id,
            models.Vehicle.company_id == current_user.company_id
        ).first()
        if not new_vehicle:
            raise HTTPException(status_code=403, detail="You can only schedule trips for vehicles you own.")
        if not new_vehicle.is_verified:
            raise HTTPException(status_code=400, detail="You cannot schedule trips for an unverified vehicle.")
            
    # Verify route exists
    route = db.query(models.Route).filter(models.Route.id == trip_in.route_id).first()
    if not route:
        raise HTTPException(status_code=404, detail="Route not found")
        
    old_dep_time = trip.departure_time
    trip.vehicle_id = trip_in.vehicle_id
    trip.route_id = trip_in.route_id
    trip.departure_time = trip_in.departure_time
    trip.arrival_time = trip_in.arrival_time
    trip.price_per_seat = trip_in.price_per_seat
    
    db.commit()
    db.refresh(trip)
    
    # Notify if departure time rescheduled
    if old_dep_time != trip.departure_time:
        bookings = db.query(models.Booking).filter(
            models.Booking.trip_id == trip.id,
            models.Booking.booking_status == "confirmed"
        ).all()
        for b in bookings:
            try:
                from app.routes.notifications import create_and_send_notification
                origin = route.origin
                destination = route.destination
                new_date_str = trip.departure_time.strftime("%Y-%m-%d %H:%M")
                
                await create_and_send_notification(
                    db=db,
                    user_id=b.passenger_id,
                    title="Trip Rescheduled!",
                    message=f"Your trip from {origin} to {destination} has been rescheduled. New departure time: {new_date_str}.",
                    noti_type="trip_update"
                )
            except Exception as noti_err:
                print(f"Notification Error: {noti_err}")
                
    trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
    trip.route = db.query(models.Route).filter(models.Route.id == trip.route_id).first()
    return trip

@router.delete("/{trip_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_trip(
    trip_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    trip = db.query(models.Trip).filter(models.Trip.id == trip_id).first()
    if not trip:
        raise HTTPException(status_code=404, detail="Scheduled trip not found")
        
    vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
    if current_user.role != "admin" and (current_user.role != "owner" or not vehicle or vehicle.company_id != current_user.company_id):
        raise HTTPException(status_code=403, detail="Unauthorized to delete this scheduled trip")
        
    db.delete(trip)
    db.commit()
    return {}
