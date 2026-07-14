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
    # If owner, verify they own the vehicle
    if current_user.role == "owner":
        vehicle = db.query(models.Vehicle).filter(
            models.Vehicle.id == trip_in.vehicle_id,
            models.Vehicle.owner_id == current_user.id
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
    db: Session = Depends(get_db)
):
    query = db.query(models.Trip).join(models.Route).join(models.Vehicle)
    
    # Filter by date
    if date:
        try:
            target_date = datetime.datetime.strptime(date, "%Y-%m-%d").date()
            start_time = datetime.datetime.combine(target_date, datetime.time.min)
            end_time = datetime.datetime.combine(target_date, datetime.time.max)
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
def update_trip_status(
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
            models.Vehicle.owner_id == current_user.id
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
        
    trip.status = status
    db.commit()
    db.refresh(trip)
    
    trip.vehicle = db.query(models.Vehicle).filter(models.Vehicle.id == trip.vehicle_id).first()
    trip.route = db.query(models.Route).filter(models.Route.id == trip.route_id).first()
    return trip
