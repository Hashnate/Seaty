from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import List
from uuid import UUID

from app.database import get_db
from app import models, schemas, auth

router = APIRouter(prefix="/admin", tags=["Admin Dashboard"])


@router.get("/dashboard", response_model=schemas.AdminDashboardStats)
def get_dashboard_stats(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin", "owner"]))
):
    """Get aggregated dashboard statistics for the Seaty admin or bus owner."""
    if current_user.role == "owner":
        company_id = current_user.company_id
        
        total_companies = 1
        active_companies = 1 if db.query(models.BusCompany).filter(
            models.BusCompany.id == company_id, 
            models.BusCompany.is_active == True
        ).first() else 0
        
        total_vehicles = db.query(models.Vehicle).filter(models.Vehicle.company_id == company_id).count()
        verified_vehicles = db.query(models.Vehicle).filter(
            models.Vehicle.company_id == company_id,
            models.Vehicle.is_verified == True
        ).count()
        pending_approvals = total_vehicles - verified_vehicles
        
        total_bookings = db.query(models.Booking).join(models.Trip).join(models.Vehicle).filter(
            models.Vehicle.company_id == company_id
        ).count()
        confirmed_bookings = db.query(models.Booking).join(models.Trip).join(models.Vehicle).filter(
            models.Vehicle.company_id == company_id,
            models.Booking.booking_status == "confirmed"
        ).count()
        
        revenue_result = db.query(
            func.coalesce(func.sum(models.Booking.total_price), 0)
        ).join(models.Trip).join(models.Vehicle).filter(
            models.Vehicle.company_id == company_id,
            models.Booking.payment_status == "paid"
        ).scalar()
        
        platform_fee_result = db.query(
            func.coalesce(func.sum(models.Booking.platform_fee), 0)
        ).join(models.Trip).join(models.Vehicle).filter(
            models.Vehicle.company_id == company_id,
            models.Booking.payment_status == "paid"
        ).scalar()
        
        total_passengers = db.query(models.Booking.passenger_id).join(models.Trip).join(models.Vehicle).filter(
            models.Vehicle.company_id == company_id
        ).distinct().count()
        
        total_owners = 1
        
        active_trips = db.query(models.Trip).join(models.Vehicle).filter(
            models.Vehicle.company_id == company_id,
            models.Trip.status.in_(["scheduled", "ongoing"])
        ).count()
    else:
        total_companies = db.query(models.BusCompany).count()
        active_companies = db.query(models.BusCompany).filter(
            models.BusCompany.is_active == True
        ).count()

        total_vehicles = db.query(models.Vehicle).count()
        verified_vehicles = db.query(models.Vehicle).filter(
            models.Vehicle.is_verified == True
        ).count()
        pending_approvals = total_vehicles - verified_vehicles

        total_bookings = db.query(models.Booking).count()
        confirmed_bookings = db.query(models.Booking).filter(
            models.Booking.booking_status == "confirmed"
        ).count()

        revenue_result = db.query(
            func.coalesce(func.sum(models.Booking.total_price), 0)
        ).filter(
            models.Booking.payment_status == "paid"
        ).scalar()

        platform_fee_result = db.query(
            func.coalesce(func.sum(models.Booking.platform_fee), 0)
        ).filter(
            models.Booking.payment_status == "paid"
        ).scalar()

        total_passengers = db.query(models.User).filter(
            models.User.role == "passenger"
        ).count()

        total_owners = db.query(models.User).filter(
            models.User.role == "owner"
        ).count()

        active_trips = db.query(models.Trip).filter(
            models.Trip.status.in_(["scheduled", "ongoing"])
        ).count()

    return schemas.AdminDashboardStats(
        total_companies=total_companies,
        active_companies=active_companies,
        total_vehicles=total_vehicles,
        verified_vehicles=verified_vehicles,
        pending_approvals=pending_approvals,
        total_bookings=total_bookings,
        confirmed_bookings=confirmed_bookings,
        total_revenue=float(revenue_result),
        platform_fees_earned=float(platform_fee_result),
        total_passengers=total_passengers,
        total_owners=total_owners,
        active_trips=active_trips
    )


@router.get("/analytics/revenue", response_model=List[schemas.RevenueDataPoint])
def get_revenue_analytics(
    days: int = 30,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    """Get daily revenue breakdown for the last N days."""
    import datetime

    data_points = []
    today = datetime.date.today()

    for i in range(days - 1, -1, -1):
        target_date = today - datetime.timedelta(days=i)
        start_time = datetime.datetime.combine(target_date, datetime.time.min)
        end_time = datetime.datetime.combine(target_date, datetime.time.max)

        result = db.query(
            func.count(models.Booking.id).label("count"),
            func.coalesce(func.sum(models.Booking.total_price), 0).label("revenue"),
            func.coalesce(func.sum(models.Booking.platform_fee), 0).label("platform_fee")
        ).filter(
            models.Booking.created_at >= start_time,
            models.Booking.created_at <= end_time,
            models.Booking.payment_status == "paid"
        ).first()

        data_points.append(schemas.RevenueDataPoint(
            date=target_date.isoformat(),
            revenue=float(result.revenue) if result else 0.0,
            bookings=result.count if result else 0,
            platform_fee=float(result.platform_fee) if result else 0.0
        ))

    return data_points


def validate_and_normalize_setting(key: str, raw_value: str) -> str:
    """Validate and normalize platform configuration values before persisting."""
    val = raw_value.strip()

    if key == "commission_percentage":
        clean_val = val
        if clean_val.endswith("%"):
            clean_val = clean_val[:-1].strip()
        try:
            num = float(clean_val)
        except (ValueError, TypeError):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="commission_percentage must be a valid number between 0 and 100",
            )
        if not (0.0 <= num <= 100.0):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="commission_percentage must be between 0 and 100",
            )
        return f"{num:.2f}".rstrip("0").rstrip(".") if "." in f"{num:.2f}" else f"{num:.2f}"

    elif key == "commission_fixed_fee":
        try:
            num = float(val)
        except (ValueError, TypeError):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="commission_fixed_fee must be a valid non-negative number",
            )
        if num < 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="commission_fixed_fee cannot be negative",
            )
        return f"{num:.2f}"

    elif key == "seat_hold_duration_minutes":
        clean_val = val.lower().strip()
        for suffix in ("minutes", "minute", "mins", "min", "m"):
            if clean_val.endswith(suffix):
                clean_val = clean_val[:-len(suffix)].strip()
                break
        try:
            num = int(clean_val)
        except (ValueError, TypeError):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="seat_hold_duration_minutes must be an integer (e.g. 10)",
            )
        if not (1 <= num <= 120):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="seat_hold_duration_minutes must be between 1 and 120 minutes",
            )
        return str(num)

    elif key == "bookings_enabled":
        lower = val.lower()
        if lower in ("true", "1", "yes", "on"):
            return "true"
        elif lower in ("false", "0", "no", "off"):
            return "false"
        else:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="bookings_enabled must be 'true' or 'false'",
            )

    elif key == "payment_gateway":
        lower = val.lower()
        valid_gateways = {"sandbox", "bancstac", "payhere", "stripe", "off", "test", "live"}
        if lower not in valid_gateways:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"payment_gateway must be one of: {', '.join(sorted(valid_gateways))}",
            )
        return lower

    elif key == "currency":
        upper = val.upper()
        if len(upper) != 3 or not upper.isalpha():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="currency must be a 3-letter currency code (e.g. LKR)",
            )
        return upper

    elif key == "support_phone":
        if not val:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="support_phone cannot be empty",
            )
        return val

    return val


@router.get("/settings", response_model=List[schemas.PlatformSettingResponse])
def get_platform_settings(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    """Get all platform configuration settings."""
    return db.query(models.PlatformSetting).all()


@router.put("/settings/{key}", response_model=schemas.PlatformSettingResponse)
def update_platform_setting(
    key: str,
    setting_in: schemas.PlatformSettingUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    """Update a specific platform setting."""
    setting = db.query(models.PlatformSetting).filter(
        models.PlatformSetting.key == key
    ).first()
    if not setting:
        raise HTTPException(status_code=404, detail=f"Setting '{key}' not found")

    validated_value = validate_and_normalize_setting(key, setting_in.value)
    setting.value = validated_value
    db.commit()
    db.refresh(setting)
    return setting


@router.get("/users", response_model=List[schemas.UserResponse])
def list_all_users(
    role: str = None,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    """List all users, optionally filtered by role."""
    query = db.query(models.User)
    if role:
        query = query.filter(models.User.role == role)
    return query.all()
