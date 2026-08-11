from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, DateTime, Numeric, Interval, Text, Time, Date
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, UUID
from sqlalchemy.orm import relationship
import datetime
import uuid
from app.database import Base

# A seat stays taken once its ticket is scanned. `booking_status` flips from
# "confirmed" to "completed" at boarding time, so treating only "confirmed" as
# occupied made boarded passengers disappear from seat counts, the conductor's
# manifest and the revenue total - and briefly freed their seat for rebooking.
OCCUPIED_BOOKING_STATUSES = ("confirmed", "completed")


class BusCompany(Base):
    __tablename__ = "bus_companies"

    id = Column(UUID(as_uuid=True), primary_key=True, default=lambda: uuid.uuid4())
    name = Column(String, nullable=False)
    registration_number = Column(String, unique=True, nullable=True)
    contact_email = Column(String, nullable=True)
    contact_phone = Column(String, nullable=True)
    logo_url = Column(String, nullable=True)
    address = Column(String, nullable=True)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)

    # Relationships
    users = relationship("User", back_populates="company")
    vehicles = relationship("Vehicle", back_populates="company")


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=lambda: uuid.uuid4())
    email = Column(String, unique=True, nullable=False, index=True)
    hashed_password = Column(String, nullable=False)
    full_name = Column(String, nullable=False)
    phone_number = Column(String, nullable=True)
    nic_number = Column(String, nullable=True)
    gender = Column(String, nullable=True)
    role = Column(String, nullable=False, default="passenger")
    company_id = Column(UUID(as_uuid=True), ForeignKey("bus_companies.id", ondelete="SET NULL"), nullable=True)
    fcm_token = Column(String, nullable=True)
    # Bumped on sign-out. Every JWT carries the value it was minted with, so a
    # bump kills every token already issued for this user. Without it, logging
    # out only cleared the device - the token stayed valid until it expired,
    # and a device whose local state survived a force-close stayed signed in.
    token_version = Column(Integer, nullable=False, default=1, server_default="1")
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)

    # Relationships
    company = relationship("BusCompany", back_populates="users")
    vehicles = relationship("Vehicle", back_populates="owner")
    bookings = relationship("Booking", back_populates="passenger")
    seat_holds = relationship("SeatHold", back_populates="user")


class Vehicle(Base):
    __tablename__ = "vehicles"

    id = Column(UUID(as_uuid=True), primary_key=True, index=True)
    owner_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    company_id = Column(UUID(as_uuid=True), ForeignKey("bus_companies.id", ondelete="SET NULL"), nullable=True)
    name = Column(String, nullable=False)
    registration_number = Column(String, unique=True, nullable=False)
    type = Column(String, nullable=False, default="bus")  # 'bus', 'train', 'other'
    seat_layout = Column(JSONB, nullable=False)  # JSON representation of seat layout
    total_seats = Column(Integer, nullable=False)
    amenities = Column(ARRAY(String), default=[])
    is_verified = Column(Boolean, default=False)
    document_urls = Column(ARRAY(String), default=[])
    contact_phone = Column(String, nullable=True)
    main_image_url = Column(String, nullable=True)
    gallery_image_urls = Column(ARRAY(String), default=[])
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)

    # Relationships
    owner = relationship("User", back_populates="vehicles")
    company = relationship("BusCompany", back_populates="vehicles")
    trips = relationship("Trip", back_populates="vehicle")
    location = relationship("VehicleLocation", back_populates="vehicle", uselist=False)


class UserFavourite(Base):
    __tablename__ = "user_favourites"

    id = Column(UUID(as_uuid=True), primary_key=True, default=lambda: uuid.uuid4())
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    schedule_id = Column(UUID(as_uuid=True), ForeignKey("trip_schedules.id", ondelete="CASCADE"), nullable=True)
    vehicle_id = Column(UUID(as_uuid=True), ForeignKey("vehicles.id", ondelete="CASCADE"), nullable=False)
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)

    # Relationships
    user = relationship("User", backref="favourites")
    schedule = relationship("TripSchedule")
    vehicle = relationship("Vehicle")



class Route(Base):
    __tablename__ = "routes"

    id = Column(UUID(as_uuid=True), primary_key=True, index=True)
    origin = Column(String, nullable=False)
    destination = Column(String, nullable=False)
    stops = Column(JSONB, default=[])  # List of intermediate stops
    total_distance = Column(Numeric(6, 2), nullable=False)
    estimated_duration = Column(Interval, nullable=False)
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)

    # Relationships
    trips = relationship("Trip", back_populates="route")


class TripSchedule(Base):
    __tablename__ = "trip_schedules"

    id = Column(UUID(as_uuid=True), primary_key=True, default=lambda: uuid.uuid4())
    vehicle_id = Column(UUID(as_uuid=True), ForeignKey("vehicles.id", ondelete="CASCADE"), nullable=False)
    route_id = Column(UUID(as_uuid=True), ForeignKey("routes.id", ondelete="CASCADE"), nullable=False)
    departure_time = Column(Time, nullable=False)
    arrival_time = Column(Time, nullable=False)
    price_per_seat = Column(Numeric(10, 2), nullable=False)
    schedule_type = Column(String, nullable=False, default="daily")  # 'daily', 'weekdays', 'weekends', 'custom'
    custom_days = Column(ARRAY(Integer), default=[])  # 0=Monday, 6=Sunday
    effective_from = Column(Date, nullable=False, default=lambda: datetime.date.today())
    effective_until = Column(Date, nullable=True)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)

    conductor_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

    # Relationships
    vehicle = relationship("Vehicle")
    route = relationship("Route")
    trips = relationship("Trip", back_populates="schedule", cascade="all, delete-orphan")
    overrides = relationship("BusOverride", back_populates="schedule", cascade="all, delete-orphan")
    conductor = relationship("User", foreign_keys=[conductor_id])


class BusOverride(Base):
    __tablename__ = "bus_overrides"

    id = Column(UUID(as_uuid=True), primary_key=True, default=lambda: uuid.uuid4())
    schedule_id = Column(UUID(as_uuid=True), ForeignKey("trip_schedules.id", ondelete="CASCADE"), nullable=False)
    override_date = Column(Date, nullable=False)
    replacement_vehicle_id = Column(UUID(as_uuid=True), ForeignKey("vehicles.id", ondelete="CASCADE"), nullable=False)
    reason = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)

    # Relationships
    schedule = relationship("TripSchedule", back_populates="overrides")
    replacement_vehicle = relationship("Vehicle")


class Trip(Base):
    __tablename__ = "trips"

    id = Column(UUID(as_uuid=True), primary_key=True, index=True)
    vehicle_id = Column(UUID(as_uuid=True), ForeignKey("vehicles.id", ondelete="CASCADE"), nullable=False)
    route_id = Column(UUID(as_uuid=True), ForeignKey("routes.id", ondelete="CASCADE"), nullable=False)
    schedule_id = Column(UUID(as_uuid=True), ForeignKey("trip_schedules.id", ondelete="SET NULL"), nullable=True)
    departure_time = Column(DateTime(timezone=True), nullable=False)
    arrival_time = Column(DateTime(timezone=True), nullable=False)
    price_per_seat = Column(Numeric(10, 2), nullable=False)
    status = Column(String, default="scheduled")  # 'scheduled', 'ongoing', 'completed', 'cancelled'
    boarded_seats = Column(ARRAY(String), default=list, nullable=False)
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)

    conductor_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

    # Relationships
    vehicle = relationship("Vehicle", back_populates="trips")
    route = relationship("Route", back_populates="trips")
    schedule = relationship("TripSchedule", back_populates="trips")
    bookings = relationship("Booking", back_populates="trip")
    seat_holds = relationship("SeatHold", back_populates="trip")
    conductor = relationship("User", foreign_keys=[conductor_id])



class Booking(Base):
    __tablename__ = "bookings"

    id = Column(UUID(as_uuid=True), primary_key=True, index=True)
    trip_id = Column(UUID(as_uuid=True), ForeignKey("trips.id", ondelete="CASCADE"), nullable=False)
    passenger_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    selected_seats = Column(ARRAY(String), nullable=False)
    total_price = Column(Numeric(10, 2), nullable=False)
    platform_fee = Column(Numeric(10, 2), nullable=False, default=0)
    payment_status = Column(String, default="pending")  # 'pending', 'awaiting_payment', 'paid', 'failed', 'refunded'
    booking_status = Column(String, default="pending")  # 'pending', 'confirmed', 'cancelled', 'completed', 'expired'
    passenger_details = Column(JSONB, nullable=True)
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)

    # Relationships
    trip = relationship("Trip", back_populates="bookings")
    passenger = relationship("User", back_populates="bookings")
    payments = relationship("Payment", back_populates="booking")


class Payment(Base):
    __tablename__ = "payments"

    id = Column(UUID(as_uuid=True), primary_key=True, default=lambda: uuid.uuid4())
    booking_id = Column(UUID(as_uuid=True), ForeignKey("bookings.id", ondelete="CASCADE"), nullable=False)
    payment_gateway = Column(String, nullable=False, default="sandbox")
    gateway_transaction_id = Column(String, nullable=True)
    amount = Column(Numeric(10, 2), nullable=False)
    platform_fee = Column(Numeric(10, 2), nullable=False, default=0)
    currency = Column(String, nullable=False, default="LKR")
    status = Column(String, default="pending")  # 'pending', 'processing', 'completed', 'failed', 'refunded'
    payment_url = Column(String, nullable=True)
    paid_at = Column(DateTime(timezone=True), nullable=True)
    refunded_at = Column(DateTime(timezone=True), nullable=True)
    gateway_response = Column(JSONB, nullable=True)
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)

    # Relationships
    booking = relationship("Booking", back_populates="payments")


class SeatHold(Base):
    __tablename__ = "seat_holds"

    id = Column(UUID(as_uuid=True), primary_key=True, default=lambda: uuid.uuid4())
    trip_id = Column(UUID(as_uuid=True), ForeignKey("trips.id", ondelete="CASCADE"), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    seat_labels = Column(ARRAY(String), nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    is_released = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)

    # Relationships
    trip = relationship("Trip", back_populates="seat_holds")
    user = relationship("User", back_populates="seat_holds")


class Notification(Base):
    __tablename__ = "notifications"

    id = Column(UUID(as_uuid=True), primary_key=True, default=lambda: uuid.uuid4())
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    title = Column(String, nullable=False)
    message = Column(Text, nullable=False)
    type = Column(String, nullable=False)  # 'booking', 'trip_ongoing', 'trip_cancelled', 'trip_rescheduled', 'trip_reminder', 'verification', 'system'
    booking_id = Column(UUID(as_uuid=True), ForeignKey("bookings.id", ondelete="SET NULL"), nullable=True)
    vehicle_id = Column(UUID(as_uuid=True), ForeignKey("vehicles.id", ondelete="SET NULL"), nullable=True)
    is_read = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)

    # Relationships
    user = relationship("User", backref="notifications")


class PlatformSetting(Base):
    __tablename__ = "platform_settings"

    id = Column(UUID(as_uuid=True), primary_key=True, default=lambda: uuid.uuid4())
    key = Column(String, unique=True, nullable=False)
    value = Column(String, nullable=False)
    description = Column(String, nullable=True)
    updated_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)


class VehicleLocation(Base):
    __tablename__ = "vehicle_locations"

    vehicle_id = Column(UUID(as_uuid=True), ForeignKey("vehicles.id", ondelete="CASCADE"), primary_key=True)
    latitude = Column(Numeric, nullable=False)
    longitude = Column(Numeric, nullable=False)
    speed = Column(Numeric(5, 2), nullable=True)
    heading = Column(Numeric(5, 2), nullable=True)
    updated_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)

    # Relationships
    vehicle = relationship("Vehicle", back_populates="location")


class HeroBanner(Base):
    """Hero carousel images shown on the passenger home screen.

    Managed by admins so marketing imagery can change without an app release.
    """
    __tablename__ = "hero_banners"

    id = Column(UUID(as_uuid=True), primary_key=True, default=lambda: uuid.uuid4())
    image_url = Column(String, nullable=False)
    title = Column(String, nullable=True)
    subtitle = Column(String, nullable=True)
    sort_order = Column(Integer, nullable=False, default=0)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)


class VehicleLocationHistory(Base):
    __tablename__ = "vehicle_location_history"

    id = Column(UUID(as_uuid=True), primary_key=True, default=lambda: uuid.uuid4())
    vehicle_id = Column(UUID(as_uuid=True), ForeignKey("vehicles.id", ondelete="CASCADE"), nullable=False, index=True)
    latitude = Column(Numeric, nullable=False)
    longitude = Column(Numeric, nullable=False)
    speed = Column(Numeric(5, 2), nullable=True)
    heading = Column(Numeric(5, 2), nullable=True)
    recorded_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow, index=True)


class Review(Base):
    __tablename__ = "reviews"

    id = Column(UUID(as_uuid=True), primary_key=True, default=lambda: uuid.uuid4())
    vehicle_id = Column(UUID(as_uuid=True), ForeignKey("vehicles.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    booking_id = Column(UUID(as_uuid=True), ForeignKey("bookings.id", ondelete="SET NULL"), nullable=True)
    passenger_name = Column(String, nullable=False)
    rating = Column(Integer, nullable=False)
    comment = Column(Text, nullable=True)
    is_verified = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)

    # Relationships
    vehicle = relationship("Vehicle", backref="reviews")
    user = relationship("User", backref="reviews")
    booking = relationship("Booking", backref="reviews")

