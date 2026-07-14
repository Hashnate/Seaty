-- Seaty PostgreSQL Schema Design
-- Target Environment: Supabase PostgreSQL (or any standard PostgreSQL database with UUID/PostGIS extensions)

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ==========================================
-- 1. Users Table (Self-contained authentication)
-- ==========================================
CREATE TABLE public.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL UNIQUE,
    hashed_password TEXT NOT NULL,
    full_name TEXT NOT NULL,
    phone_number TEXT,
    role TEXT NOT NULL DEFAULT 'passenger' CHECK (role IN ('passenger', 'owner', 'admin')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable Row-Level Security
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 2. Vehicles Table
-- ==========================================
CREATE TABLE public.vehicles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL, -- e.g. "Colombo-Galle Luxury Express"
    registration_number TEXT NOT NULL UNIQUE, -- e.g. "WP-ND-1234"
    type TEXT NOT NULL DEFAULT 'bus' CHECK (type IN ('bus', 'train', 'other')),
    seat_layout JSONB NOT NULL, -- Structure of seats: e.g. {"rows": 10, "columns": 4, "aisle_after_column": 2}
    total_seats INTEGER NOT NULL,
    amenities TEXT[] NOT NULL DEFAULT '{}', -- e.g. {'AC', 'WiFi', 'Charging Ports', 'Reclining Seats'}
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    document_urls TEXT[] NOT NULL DEFAULT '{}', -- Links to registration certificates, insurance docs
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 3. Routes Table
-- ==========================================
CREATE TABLE public.routes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    origin TEXT NOT NULL, -- e.g. "Colombo Fort"
    destination TEXT NOT NULL, -- e.g. "Galle"
    stops JSONB NOT NULL DEFAULT '[]', -- List of intermediate stops: [{"name": "Aluthgama", "offset_minutes": 60, "distance_km": 50}]
    total_distance NUMERIC(6, 2) NOT NULL, -- km
    estimated_duration INTERVAL NOT NULL, -- e.g. '02:30:00'
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.routes ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 4. Trips Table (Instances of scheduled journeys)
-- ==========================================
CREATE TABLE public.trips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id UUID NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
    route_id UUID NOT NULL REFERENCES public.routes(id) ON DELETE CASCADE,
    departure_time TIMESTAMPTZ NOT NULL,
    arrival_time TIMESTAMPTZ NOT NULL,
    price_per_seat NUMERIC(10, 2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'ongoing', 'completed', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.trips ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 5. Bookings Table
-- ==========================================
CREATE TABLE public.bookings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id UUID NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
    passenger_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    selected_seats TEXT[] NOT NULL, -- Array of seat labels: ['A1', 'A2']
    total_price NUMERIC(10, 2) NOT NULL,
    payment_status TEXT NOT NULL DEFAULT 'pending' CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded')),
    booking_status TEXT NOT NULL DEFAULT 'confirmed' CHECK (booking_status IN ('confirmed', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 6. Vehicle Locations Table (For real-time GPS tracking)
-- ==========================================
CREATE TABLE public.vehicle_locations (
    vehicle_id UUID PRIMARY KEY REFERENCES public.vehicles(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    speed NUMERIC(5, 2), -- Speed in km/h
    heading NUMERIC(5, 2), -- Bearing/Heading angle in degrees (0 - 360)
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.vehicle_locations ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- Trigger Functions for automatic `updated_at`
-- ==========================================
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_vehicles_updated_at BEFORE UPDATE ON public.vehicles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_trips_updated_at BEFORE UPDATE ON public.trips FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_bookings_updated_at BEFORE UPDATE ON public.bookings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ==========================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ==========================================

-- Users policies
CREATE POLICY "Public profiles are viewable by everyone" ON public.users
    FOR SELECT USING (true);

CREATE POLICY "Users can update their own profile" ON public.users
    FOR UPDATE USING (auth.uid() = id);

-- Vehicles policies
CREATE POLICY "Anyone can view verified vehicles" ON public.vehicles
    FOR SELECT USING (is_verified = true OR (auth.uid() = owner_id));

CREATE POLICY "Owners can insert their own vehicles" ON public.vehicles
    FOR INSERT WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Owners can update their own vehicles" ON public.vehicles
    FOR UPDATE USING (auth.uid() = owner_id);

-- Routes policies
CREATE POLICY "Routes are viewable by everyone" ON public.routes
    FOR SELECT USING (true);

CREATE POLICY "Only admins can insert/modify routes" ON public.routes
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.users
            WHERE users.id = auth.uid() AND users.role = 'admin'
        )
    );

-- Trips policies
CREATE POLICY "Trips are viewable by everyone" ON public.trips
    FOR SELECT USING (true);

CREATE POLICY "Owners can manage trips for their vehicles" ON public.trips
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.vehicles
            WHERE vehicles.id = vehicle_id AND vehicles.owner_id = auth.uid()
        )
    );

-- Bookings policies
CREATE POLICY "Passengers can view their own bookings" ON public.bookings
    FOR SELECT USING (auth.uid() = passenger_id);

CREATE POLICY "Owners can view bookings for their vehicles" ON public.bookings
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.trips
            JOIN public.vehicles ON trips.vehicle_id = vehicles.id
            WHERE trips.id = trip_id AND vehicles.owner_id = auth.uid()
        )
    );

CREATE POLICY "Passengers can create their own bookings" ON public.bookings
    FOR INSERT WITH CHECK (auth.uid() = passenger_id);

CREATE POLICY "Passengers can update/cancel their own bookings" ON public.bookings
    FOR UPDATE USING (auth.uid() = passenger_id);

-- Vehicle Locations policies (GPS tracking)
CREATE POLICY "Anyone can view live vehicle locations" ON public.vehicle_locations
    FOR SELECT USING (true);

CREATE POLICY "Owners can update their own vehicle locations" ON public.vehicle_locations
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.vehicles
            WHERE vehicles.id = vehicle_id AND vehicles.owner_id = auth.uid()
        )
    );
