from pydantic import BaseModel, Field, EmailStr
from typing import List, Optional, Any
from uuid import UUID
import datetime

# ==========================================
# Token & Auth Schemas
# ==========================================
class Token(BaseModel):
    access_token: str
    token_type: str

class TokenData(BaseModel):
    username: Optional[str] = None
    role: Optional[str] = None

class UserRegister(BaseModel):
    email: EmailStr
    password: str
    full_name: str
    phone_number: Optional[str] = None
    role: str = Field(default="passenger", description="passenger, owner, or admin")
    company_id: Optional[UUID] = None

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class ConductorCreate(BaseModel):
    full_name: str
    phone_number: str

class PasswordChangeRequest(BaseModel):
    current_password: str
    new_password: str

# ==========================================
# User/Profile Schemas
# ==========================================
class UserResponse(BaseModel):
    id: UUID
    email: EmailStr
    full_name: str
    phone_number: Optional[str] = None
    nic_number: Optional[str] = None
    gender: Optional[str] = None
    role: str
    company_id: Optional[UUID] = None
    created_at: datetime.datetime
    updated_at: datetime.datetime

    class Config:
        from_attributes = True

class ProfileUpdate(BaseModel):
    full_name: Optional[str] = None
    nic_number: Optional[str] = None
    gender: Optional[str] = None
    phone_number: Optional[str] = None

# ==========================================
# Bus Company Schemas
# ==========================================
class BusCompanyCreate(BaseModel):
    name: str
    registration_number: Optional[str] = None
    contact_email: Optional[str] = None
    contact_phone: Optional[str] = None
    logo_url: Optional[str] = None
    address: Optional[str] = None

class BusCompanyUpdate(BaseModel):
    name: Optional[str] = None
    registration_number: Optional[str] = None
    contact_email: Optional[str] = None
    contact_phone: Optional[str] = None
    logo_url: Optional[str] = None
    address: Optional[str] = None
    is_active: Optional[bool] = None

class BusCompanyResponse(BaseModel):
    id: UUID
    name: str
    registration_number: Optional[str] = None
    contact_email: Optional[str] = None
    contact_phone: Optional[str] = None
    logo_url: Optional[str] = None
    address: Optional[str] = None
    is_active: bool
    created_at: datetime.datetime
    updated_at: datetime.datetime

    class Config:
        from_attributes = True

class BusCompanyDetailResponse(BusCompanyResponse):
    vehicle_count: int = 0
    owner_count: int = 0
    total_bookings: int = 0
    total_revenue: float = 0.0

# ==========================================
# Vehicle Schemas
# ==========================================
class VehicleCreate(BaseModel):
    name: str
    registration_number: str
    type: str = Field(default="bus", description="bus, train, or other")
    seat_layout: dict = Field(..., description="e.g. {'rows': 10, 'columns': 4, 'aisle_after_column': 2}")
    total_seats: int
    amenities: List[str] = []
    document_urls: List[str] = []
    contact_phone: Optional[str] = None
    main_image_url: Optional[str] = None
    gallery_image_urls: List[str] = []

class VehicleResponse(BaseModel):
    id: UUID
    owner_id: UUID
    company_id: Optional[UUID] = None
    name: str
    registration_number: str
    type: str
    seat_layout: dict
    total_seats: int
    amenities: List[str]
    is_verified: bool
    document_urls: List[str]
    contact_phone: Optional[str] = None
    main_image_url: Optional[str] = None
    gallery_image_urls: List[str] = []
    average_rating: Optional[float] = None
    created_at: datetime.datetime
    updated_at: datetime.datetime

    class Config:
        from_attributes = True

# ==========================================
# Favourite Schemas
# ==========================================
class FavouriteToggleRequest(BaseModel):
    vehicle_id: UUID
    schedule_id: Optional[UUID] = None

class FavouriteResponse(BaseModel):
    id: UUID
    user_id: UUID
    vehicle_id: UUID
    schedule_id: Optional[UUID] = None
    created_at: datetime.datetime

    class Config:
        from_attributes = True


# ==========================================
# Route Schemas
# ==========================================
class RouteCreate(BaseModel):
    origin: str
    destination: str
    stops: List[dict] = []  # [{"name": "Stop A", "offset_minutes": 30, "distance_km": 20}]
    total_distance: float
    estimated_duration_seconds: int  # Converted to interval in the database

class RouteResponse(BaseModel):
    id: UUID
    origin: str
    destination: str
    stops: List[Any]
    total_distance: float
    estimated_duration: Any
    created_at: datetime.datetime

    class Config:
        from_attributes = True

# ==========================================
# Trip Schemas
# ==========================================
class TripCreate(BaseModel):
    vehicle_id: UUID
    route_id: UUID
    departure_time: datetime.datetime
    arrival_time: datetime.datetime
    price_per_seat: float
    conductor_id: Optional[UUID] = None

class TripResponse(BaseModel):
    id: UUID
    vehicle_id: UUID
    route_id: UUID
    schedule_id: Optional[UUID] = None
    conductor_id: Optional[UUID] = None
    departure_time: datetime.datetime
    arrival_time: datetime.datetime
    price_per_seat: float
    status: str
    boarded_seats: List[str] = []
    booked_seats: List[str] = []
    created_at: datetime.datetime
    updated_at: datetime.datetime
    # Nested components can be requested via specific endpoints or query params
    vehicle: Optional[VehicleResponse] = None
    route: Optional[RouteResponse] = None
    conductor: Optional[UserResponse] = None

    class Config:
        from_attributes = True

# ==========================================
# Trip Schedule Schemas
# ==========================================
class TripScheduleCreate(BaseModel):
    vehicle_id: UUID
    route_id: UUID
    departure_time: datetime.time
    arrival_time: datetime.time
    price_per_seat: float
    schedule_type: str = Field(default="daily", description="daily, weekdays, weekends, custom")
    custom_days: Optional[List[int]] = []
    effective_from: datetime.date
    effective_until: Optional[datetime.date] = None
    conductor_id: Optional[UUID] = None

class TripScheduleUpdate(BaseModel):
    vehicle_id: Optional[UUID] = None
    route_id: Optional[UUID] = None
    departure_time: Optional[datetime.time] = None
    arrival_time: Optional[datetime.time] = None
    price_per_seat: Optional[float] = None
    schedule_type: Optional[str] = None
    custom_days: Optional[List[int]] = None
    effective_from: Optional[datetime.date] = None
    effective_until: Optional[datetime.date] = None
    is_active: Optional[bool] = None
    conductor_id: Optional[UUID] = None

class TripScheduleResponse(BaseModel):
    id: UUID
    vehicle_id: UUID
    route_id: UUID
    departure_time: datetime.time
    arrival_time: datetime.time
    price_per_seat: float
    schedule_type: str
    custom_days: List[int]
    effective_from: datetime.date
    effective_until: Optional[datetime.date] = None
    is_active: bool
    created_at: datetime.datetime
    updated_at: datetime.datetime
    vehicle: Optional[VehicleResponse] = None
    route: Optional[RouteResponse] = None
    conductor_id: Optional[UUID] = None
    conductor: Optional[UserResponse] = None

    class Config:
        from_attributes = True

# ==========================================
# Bus Override Schemas
# ==========================================
class BusOverrideCreate(BaseModel):
    override_date: datetime.date
    replacement_vehicle_id: UUID
    reason: Optional[str] = None

class BusOverrideResponse(BaseModel):
    id: UUID
    schedule_id: UUID
    override_date: datetime.date
    replacement_vehicle_id: UUID
    reason: Optional[str] = None
    created_at: datetime.datetime
    replacement_vehicle: Optional[VehicleResponse] = None

    class Config:
        from_attributes = True


class TripSeatsResponse(BaseModel):
    """Response showing seat availability for a trip"""
    trip_id: UUID
    total_seats: int
    booked_seats: List[str]
    held_seats: List[str]
    available_seats: List[str]
    seat_genders: Optional[dict] = None

# ==========================================
# Booking Schemas
# ==========================================
class BookingCreate(BaseModel):
    trip_id: UUID
    selected_seats: List[str]
    passenger_details: Optional[dict] = None

class BookingResponse(BaseModel):
    id: UUID
    trip_id: UUID
    passenger_id: UUID
    selected_seats: List[str]
    total_price: float
    platform_fee: float
    payment_status: str
    booking_status: str
    passenger_details: Optional[dict] = None
    created_at: datetime.datetime
    updated_at: datetime.datetime
    trip: Optional[TripResponse] = None
    passenger: Optional[UserResponse] = None

    class Config:
        from_attributes = True

# ==========================================
# Payment Schemas
# ==========================================
class PaymentInitiateRequest(BaseModel):
    booking_id: UUID

class PaymentResponse(BaseModel):
    id: UUID
    booking_id: UUID
    payment_gateway: str
    gateway_transaction_id: Optional[str] = None
    amount: float
    platform_fee: float
    currency: str
    status: str
    payment_url: Optional[str] = None
    paid_at: Optional[datetime.datetime] = None
    refunded_at: Optional[datetime.datetime] = None
    created_at: datetime.datetime

    class Config:
        from_attributes = True

class PaymentWebhookPayload(BaseModel):
    """Payload from payment gateway webhook callback"""
    transaction_id: str
    status: str  # 'completed', 'failed'
    amount: Optional[float] = None
    gateway_data: Optional[dict] = None

# ==========================================
# Seat Hold Schemas
# ==========================================
class SeatHoldCreate(BaseModel):
    trip_id: UUID
    seat_labels: List[str]

class SeatHoldResponse(BaseModel):
    id: UUID
    trip_id: UUID
    user_id: UUID
    seat_labels: List[str]
    expires_at: datetime.datetime
    is_released: bool
    created_at: datetime.datetime

    class Config:
        from_attributes = True

# ==========================================
# Platform Settings Schemas
# ==========================================
class PlatformSettingResponse(BaseModel):
    id: UUID
    key: str
    value: str
    description: Optional[str] = None
    updated_at: datetime.datetime

    class Config:
        from_attributes = True

class PlatformSettingUpdate(BaseModel):
    value: str

# ==========================================
# Hero Banner Schemas
# ==========================================
class HeroBannerBase(BaseModel):
    image_url: str
    title: Optional[str] = None
    subtitle: Optional[str] = None
    sort_order: int = 0
    is_active: bool = True

class HeroBannerCreate(HeroBannerBase):
    pass

class HeroBannerUpdate(BaseModel):
    image_url: Optional[str] = None
    title: Optional[str] = None
    subtitle: Optional[str] = None
    sort_order: Optional[int] = None
    is_active: Optional[bool] = None

class HeroBannerResponse(HeroBannerBase):
    id: UUID
    created_at: datetime.datetime
    updated_at: datetime.datetime

    class Config:
        from_attributes = True

# ==========================================
# Admin Dashboard Schemas
# ==========================================
class AdminDashboardStats(BaseModel):
    total_companies: int
    active_companies: int
    total_vehicles: int
    verified_vehicles: int
    pending_approvals: int
    total_bookings: int
    confirmed_bookings: int
    total_revenue: float
    platform_fees_earned: float
    total_passengers: int
    total_owners: int
    active_trips: int

class RevenueDataPoint(BaseModel):
    date: str
    revenue: float
    bookings: int
    platform_fee: float

# ==========================================
# Live Location Schemas (GPS Telemetry)
# ==========================================
class VehicleLocationUpdate(BaseModel):
    latitude: float
    longitude: float
    speed: Optional[float] = None
    heading: Optional[float] = None

class VehicleLocationResponse(BaseModel):
    vehicle_id: UUID
    latitude: float
    longitude: float
    speed: Optional[float]
    heading: Optional[float]
    updated_at: datetime.datetime

    class Config:
        from_attributes = True

# ==========================================
# Phone & OTP Verification Schemas
# ==========================================
class PhoneCheckRequest(BaseModel):
    phone_number: str
    role: str

class PhoneCheckResponse(BaseModel):
    exists: bool
    name: Optional[str] = None
    role: Optional[str] = None

class PhoneRegisterRequest(BaseModel):
    phone_number: str
    full_name: str
    role: str
    otp_code: Optional[str] = None

class SendOTPRequest(BaseModel):
    phone_number: str
    purpose: Optional[str] = "auth"

class SendOTPResponse(BaseModel):
    success: bool
    message: str
    phone_number: str
    otp_code: Optional[str] = None

class VerifyOTPRequest(BaseModel):
    phone_number: str
    otp_code: str

class VerifyOTPResponse(BaseModel):
    success: bool
    message: str


# ==========================================
# Notification Schemas
# ==========================================
class NotificationResponse(BaseModel):
    id: UUID
    user_id: UUID
    title: str
    message: str
    type: str
    booking_id: Optional[UUID] = None
    vehicle_id: Optional[UUID] = None
    is_read: bool
    created_at: datetime.datetime

    class Config:
        from_attributes = True


class NotificationBroadcast(BaseModel):
    title: str
    message: str
    target_role: str = Field(default="passenger", description="passenger, owner, conductor, admin, or all")


class NotificationDirectSend(BaseModel):
    user_id: Optional[UUID] = None
    phone_number: Optional[str] = None
    title: str
    message: str


class FCMTokenUpdate(BaseModel):
    fcm_token: str


# ==========================================
# Review Schemas
# ==========================================
class ReviewCreate(BaseModel):
    rating: int = Field(..., ge=1, le=5)
    comment: Optional[str] = None
    passenger_name: Optional[str] = "Anonymous Passenger"
    booking_id: Optional[UUID] = None

class ReviewResponse(BaseModel):
    id: UUID
    vehicle_id: UUID
    user_id: UUID
    booking_id: Optional[UUID] = None
    passenger_name: str
    rating: int
    comment: Optional[str] = None
    is_verified: bool = True
    created_at: datetime.datetime

    class Config:
        from_attributes = True

class ReviewSummaryResponse(BaseModel):
    average_rating: float
    total_reviews: int
    reviews: List[ReviewResponse]

