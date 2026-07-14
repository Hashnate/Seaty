from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import List
from uuid import UUID
import uuid

from app.database import get_db
from app import models, schemas, auth

router = APIRouter(prefix="/companies", tags=["Bus Companies"])


@router.post("", response_model=schemas.BusCompanyResponse, status_code=status.HTTP_201_CREATED)
def create_company(
    company_in: schemas.BusCompanyCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    """Register a new bus company (admin only)."""
    if company_in.registration_number:
        existing = db.query(models.BusCompany).filter(
            models.BusCompany.registration_number == company_in.registration_number
        ).first()
        if existing:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="A company with this registration number already exists."
            )

    db_company = models.BusCompany(
        id=uuid.uuid4(),
        name=company_in.name,
        registration_number=company_in.registration_number,
        contact_email=company_in.contact_email,
        contact_phone=company_in.contact_phone,
        logo_url=company_in.logo_url,
        address=company_in.address,
        is_active=True
    )
    db.add(db_company)
    db.commit()
    db.refresh(db_company)
    return db_company


@router.get("", response_model=List[schemas.BusCompanyResponse])
def list_companies(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    """List all bus companies. Admins see all, owners see their own company."""
    if current_user.role == "admin":
        return db.query(models.BusCompany).all()
    elif current_user.role == "owner" and current_user.company_id:
        return db.query(models.BusCompany).filter(
            models.BusCompany.id == current_user.company_id
        ).all()
    else:
        # Passengers see only active companies
        return db.query(models.BusCompany).filter(
            models.BusCompany.is_active == True
        ).all()


@router.get("/{company_id}", response_model=schemas.BusCompanyDetailResponse)
def get_company(
    company_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    """Get detailed company info with stats."""
    company = db.query(models.BusCompany).filter(models.BusCompany.id == company_id).first()
    if not company:
        raise HTTPException(status_code=404, detail="Company not found")

    # Only admin or company owner can see detailed info
    if current_user.role == "owner" and current_user.company_id != company_id:
        raise HTTPException(status_code=403, detail="Unauthorized to view this company")

    # Compute stats
    vehicle_count = db.query(models.Vehicle).filter(models.Vehicle.company_id == company_id).count()
    owner_count = db.query(models.User).filter(
        models.User.company_id == company_id,
        models.User.role == "owner"
    ).count()

    # Get total bookings and revenue for vehicles belonging to this company
    company_vehicle_ids = db.query(models.Vehicle.id).filter(
        models.Vehicle.company_id == company_id
    ).subquery()
    company_trip_ids = db.query(models.Trip.id).filter(
        models.Trip.vehicle_id.in_(company_vehicle_ids)
    ).subquery()

    booking_stats = db.query(
        func.count(models.Booking.id).label("total_bookings"),
        func.coalesce(func.sum(models.Booking.total_price), 0).label("total_revenue")
    ).filter(
        models.Booking.trip_id.in_(company_trip_ids),
        models.Booking.booking_status == "confirmed"
    ).first()

    response = schemas.BusCompanyDetailResponse(
        id=company.id,
        name=company.name,
        registration_number=company.registration_number,
        contact_email=company.contact_email,
        contact_phone=company.contact_phone,
        logo_url=company.logo_url,
        address=company.address,
        is_active=company.is_active,
        created_at=company.created_at,
        updated_at=company.updated_at,
        vehicle_count=vehicle_count,
        owner_count=owner_count,
        total_bookings=booking_stats.total_bookings if booking_stats else 0,
        total_revenue=float(booking_stats.total_revenue) if booking_stats else 0.0
    )
    return response


@router.patch("/{company_id}", response_model=schemas.BusCompanyResponse)
def update_company(
    company_id: UUID,
    company_in: schemas.BusCompanyUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    """Update company details (admin only)."""
    company = db.query(models.BusCompany).filter(models.BusCompany.id == company_id).first()
    if not company:
        raise HTTPException(status_code=404, detail="Company not found")

    update_data = company_in.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(company, field, value)

    db.commit()
    db.refresh(company)
    return company


@router.patch("/{company_id}/toggle", response_model=schemas.BusCompanyResponse)
def toggle_company_status(
    company_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    """Enable or disable a bus company (admin only)."""
    company = db.query(models.BusCompany).filter(models.BusCompany.id == company_id).first()
    if not company:
        raise HTTPException(status_code=404, detail="Company not found")

    company.is_active = not company.is_active
    db.commit()
    db.refresh(company)
    return company
