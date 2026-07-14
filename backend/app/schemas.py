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
    created_at: datetime.datetime
    updated_at: datetime.datetime

    class Config:
        from_attributes = True

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
    payment_status: str
    booking_status: str
    created_at: datetime.datetime
    updated_at: datetime.datetime
    trip: Optional[TripResponse] = None
    passenger: Optional[UserResponse] = None

    class Config:
        from_attributes = True

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
