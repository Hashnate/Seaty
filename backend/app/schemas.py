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

# ==========================================
# User/Profile Schemas
# ==========================================
class UserResponse(BaseModel):
    id: UUID
    email: EmailStr
    full_name: str
    phone_number: Optional[str] = None
    role: str
    company_id: Optional[UUID] = None
    created_at: datetime.datetime
    updated_at: datetime.datetime

    class Config:
        from_attributes = True

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
    created_at: datetime.datetime
    updated_at: datetime.datetime

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

class TripResponse(BaseModel):
    id: UUID
    vehicle_id: UUID
    route_id: UUID
    departure_time: datetime.datetime
    arrival_time: datetime.datetime
    price_per_seat: float
    status: str
    created_at: datetime.datetime
    updated_at: datetime.datetime
    # Nested components can be requested via specific endpoints or query params
    vehicle: Optional[VehicleResponse] = None
    route: Optional[RouteResponse] = None

    class Config:
        from_attributes = True

class TripSeatsResponse(BaseModel):
    """Response showing seat availability for a trip"""
    trip_id: UUID
    total_seats: int
    booked_seats: List[str]
    held_seats: List[str]
    available_seats: List[str]

# ==========================================
# Booking Schemas
# ==========================================
class BookingCreate(BaseModel):
    trip_id: UUID
    selected_seats: List[str]

class BookingResponse(BaseModel):
    id: UUID
    trip_id: UUID
    passenger_id: UUID
    selected_seats: List[str]
    total_price: float
    platform_fee: float
    payment_status: str
    booking_status: str
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

class PhoneRegisterRequest(BaseModel):
    phone_number: str
    full_name: str
    role: str
