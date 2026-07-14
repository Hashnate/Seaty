from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID
import uuid
import datetime

from app.database import get_db
from app import models, schemas, auth

router = APIRouter(prefix="/routes", tags=["Routes"])

@router.post("", response_model=schemas.RouteResponse, status_code=status.HTTP_201_CREATED)
def create_route(
    route_in: schemas.RouteCreate, 
    db: Session = Depends(get_db), 
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    # Convert duration in seconds to python timedelta for interval mapping
    duration = datetime.timedelta(seconds=route_in.estimated_duration_seconds)
    
    db_route = models.Route(
        id=uuid.uuid4(),
        origin=route_in.origin,
        destination=route_in.destination,
        stops=route_in.stops,
        total_distance=route_in.total_distance,
        estimated_duration=duration
    )
    db.add(db_route)
    db.commit()
    db.refresh(db_route)
    return db_route

@router.get("", response_model=List[schemas.RouteResponse])
def list_routes(db: Session = Depends(get_db)):
    return db.query(models.Route).all()

@router.get("/{route_id}", response_model=schemas.RouteResponse)
def get_route(route_id: UUID, db: Session = Depends(get_db)):
    route = db.query(models.Route).filter(models.Route.id == route_id).first()
    if not route:
        raise HTTPException(status_code=404, detail="Route not found")
    return route
