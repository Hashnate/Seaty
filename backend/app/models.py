from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, DateTime, Numeric, Interval, Table
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, UUID
from sqlalchemy.orm import relationship
import datetime
import uuid
from app.database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=lambda: uuid.uuid4())
    email = Column(String, unique=True, nullable=False, index=True)
    hashed_password = Column(String, nullable=False)
    full_name = Column(String, nullable=False)
    phone_number = Column(String, nullable=True)
    role = Column(String, nullable=False, default="passenger")
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)

    # Relationships
    vehicles = relationship("Vehicle", back_populates="owner")
    bookings = relationship("Booking", back_populates="passenger")


class Vehicle(Base):
    __tablename__ = "vehicles"

    id = Column(UUID(as_uuid=True), primary_key=True, index=True)
    owner_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    name = Column(String, nullable=False)
    registration_number = Column(String, unique=True, nullable=False)
    type = Column(String, nullable=False, default="bus")  # 'bus', 'train', 'other'
    seat_layout = Column(JSONB, nullable=False)  # JSON representation of seat layout
    total_seats = Column(Integer, nullable=False)
    amenities = Column(ARRAY(String), default=[])
    is_verified = Column(Boolean, default=False)
    document_urls = Column(ARRAY(String), default=[])
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)

    # Relationships
    owner = relationship("User", back_populates="vehicles")
    trips = relationship("Trip", back_populates="vehicle")
    location = relationship("VehicleLocation", back_populates="vehicle", uselist=False)


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


class Trip(Base):
    __tablename__ = "trips"

    id = Column(UUID(as_uuid=True), primary_key=True, index=True)
    vehicle_id = Column(UUID(as_uuid=True), ForeignKey("vehicles.id", ondelete="CASCADE"), nullable=False)
    route_id = Column(UUID(as_uuid=True), ForeignKey("routes.id", ondelete="CASCADE"), nullable=False)
    departure_time = Column(DateTime(timezone=True), nullable=False)
    arrival_time = Column(DateTime(timezone=True), nullable=False)
    price_per_seat = Column(Numeric(10, 2), nullable=False)
    status = Column(String, default="scheduled")  # 'scheduled', 'ongoing', 'completed', 'cancelled'
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)

    # Relationships
    vehicle = relationship("Vehicle", back_populates="trips")
    route = relationship("Route", back_populates="trips")
    bookings = relationship("Booking", back_populates="trip")


class Booking(Base):
    __tablename__ = "bookings"

    id = Column(UUID(as_uuid=True), primary_key=True, index=True)
    trip_id = Column(UUID(as_uuid=True), ForeignKey("trips.id", ondelete="CASCADE"), nullable=False)
    passenger_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    selected_seats = Column(ARRAY(String), nullable=False)
    total_price = Column(Numeric(10, 2), nullable=False)
    payment_status = Column(String, default="pending")  # 'pending', 'paid', 'failed', 'refunded'
    booking_status = Column(String, default="confirmed")  # 'confirmed', 'cancelled'
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow)

    # Relationships
    trip = relationship("Trip", back_populates="bookings")
    passenger = relationship("User", back_populates="bookings")


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
