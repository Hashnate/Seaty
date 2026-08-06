-- Seaty PostgreSQL Schema Design
-- Target Environment: Supabase PostgreSQL (or any standard PostgreSQL database with UUID/PostGIS extensions)

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Setup auth schema to mock Supabase helpers locally
CREATE SCHEMA IF NOT EXISTS auth;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID AS $$
    SELECT COALESCE(
        NULLIF(current_setting('request.jwt.claim.sub', true), ''),
        '00000000-0000-0000-0000-000000000000'
    )::uuid;
$$ LANGUAGE sql;

-- ==========================================
-- 1. Bus Companies Table (Transport Operators)
-- ==========================================
CREATE TABLE public.bus_companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    registration_number TEXT UNIQUE,
    contact_email TEXT,
    contact_phone TEXT,
    logo_url TEXT,
    address TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.bus_companies ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 2. Users Table (Self-contained authentication)
-- ==========================================
CREATE TABLE public.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL UNIQUE,
    hashed_password TEXT NOT NULL,
    full_name TEXT NOT NULL,
    phone_number TEXT,
    nic_number TEXT,
    gender TEXT,
    role TEXT NOT NULL DEFAULT 'passenger' CHECK (role IN ('passenger', 'owner', 'admin', 'conductor')),
    company_id UUID REFERENCES public.bus_companies(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable Row-Level Security
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 3. Vehicles Table
-- ==========================================
CREATE TABLE public.vehicles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    company_id UUID REFERENCES public.bus_companies(id) ON DELETE SET NULL,
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
-- 4. Routes Table
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
-- 4.5. Trip Schedules Table (Recurring routes)
-- ==========================================
CREATE TABLE public.trip_schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id UUID NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
    route_id UUID NOT NULL REFERENCES public.routes(id) ON DELETE CASCADE,
    departure_time TIME NOT NULL,
    arrival_time TIME NOT NULL,
    price_per_seat NUMERIC(10, 2) NOT NULL,
    schedule_type TEXT NOT NULL DEFAULT 'daily',
    custom_days INTEGER[] DEFAULT '{}',
    effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
    effective_until DATE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    conductor_id UUID REFERENCES public.users(id) ON DELETE SET NULL
);

ALTER TABLE public.trip_schedules ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 4.6. Bus Overrides Table
-- ==========================================
CREATE TABLE public.bus_overrides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    schedule_id UUID NOT NULL REFERENCES public.trip_schedules(id) ON DELETE CASCADE,
    override_date DATE NOT NULL,
    replacement_vehicle_id UUID NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.bus_overrides ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 5. Trips Table (Instances of scheduled journeys)
-- ==========================================
CREATE TABLE public.trips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id UUID NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
    route_id UUID NOT NULL REFERENCES public.routes(id) ON DELETE CASCADE,
    schedule_id UUID REFERENCES public.trip_schedules(id) ON DELETE SET NULL,
    departure_time TIMESTAMPTZ NOT NULL,
    arrival_time TIMESTAMPTZ NOT NULL,
    price_per_seat NUMERIC(10, 2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'ongoing', 'completed', 'cancelled')),
    boarded_seats TEXT[] NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    conductor_id UUID REFERENCES public.users(id) ON DELETE SET NULL
);

ALTER TABLE public.trips ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 6. Bookings Table
-- ==========================================
CREATE TABLE public.bookings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id UUID NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
    passenger_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    selected_seats TEXT[] NOT NULL, -- Array of seat labels: ['A1', 'A2']
    total_price NUMERIC(10, 2) NOT NULL,
    platform_fee NUMERIC(10, 2) NOT NULL DEFAULT 0, -- Commission charged by Seaty
    payment_status TEXT NOT NULL DEFAULT 'pending' CHECK (payment_status IN ('pending', 'awaiting_payment', 'paid', 'failed', 'refunded')),
    booking_status TEXT NOT NULL DEFAULT 'pending' CHECK (booking_status IN ('pending', 'confirmed', 'cancelled', 'completed', 'expired')),
    passenger_details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 7. Payments Table (Transaction records)
-- ==========================================
CREATE TABLE public.payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id UUID NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
    payment_gateway TEXT NOT NULL DEFAULT 'sandbox', -- 'sandbox', 'payhere', 'stripe'
    gateway_transaction_id TEXT,
    amount NUMERIC(10, 2) NOT NULL,
    platform_fee NUMERIC(10, 2) NOT NULL DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'LKR',
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'refunded')),
    payment_url TEXT, -- Redirect URL for payment gateway
    paid_at TIMESTAMPTZ,
    refunded_at TIMESTAMPTZ,
    gateway_response JSONB, -- Raw response from payment gateway
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 8. Seat Holds Table (Temporary locks during payment)
-- ==========================================
CREATE TABLE public.seat_holds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id UUID NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    seat_labels TEXT[] NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    is_released BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.seat_holds ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 9. Platform Settings Table (Configurable parameters)
-- ==========================================
CREATE TABLE public.platform_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT NOT NULL UNIQUE,
    value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed default platform settings
INSERT INTO public.platform_settings (key, value, description) VALUES
    ('commission_percentage', '3.0', 'Percentage commission on each booking (e.g. 3.0 = 3%)'),
    ('commission_fixed_fee', '25.00', 'Fixed fee in LKR added to each booking'),
    ('seat_hold_duration_minutes', '10', 'How long seats are held during payment (minutes)'),
    ('payment_gateway', 'sandbox', 'Active payment gateway: sandbox, payhere, stripe'),
    ('currency', 'LKR', 'Default currency for all transactions'),
    ('support_phone', '0262237803', 'Customer support contact phone number');

-- ==========================================
-- 10. Vehicle Locations Table (For real-time GPS tracking)
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
-- 11. Notifications Table
-- ==========================================
CREATE TABLE public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    type TEXT NOT NULL,
    booking_id UUID REFERENCES public.bookings(id) ON DELETE SET NULL,
    vehicle_id UUID REFERENCES public.vehicles(id) ON DELETE SET NULL,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own notifications" ON public.notifications
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own notifications" ON public.notifications
    FOR UPDATE USING (auth.uid() = user_id);

-- ==========================================
-- Indexes for performance
-- ==========================================
CREATE INDEX idx_users_company ON public.users(company_id);
CREATE INDEX idx_users_phone ON public.users(phone_number);
CREATE INDEX idx_vehicles_company ON public.vehicles(company_id);
CREATE INDEX idx_vehicles_owner ON public.vehicles(owner_id);
CREATE INDEX idx_trips_vehicle ON public.trips(vehicle_id);
CREATE INDEX idx_trips_route ON public.trips(route_id);
CREATE INDEX idx_trips_departure ON public.trips(departure_time);
CREATE INDEX idx_trips_status ON public.trips(status);
CREATE INDEX idx_bookings_trip ON public.bookings(trip_id);
CREATE INDEX idx_bookings_passenger ON public.bookings(passenger_id);
CREATE INDEX idx_bookings_status ON public.bookings(booking_status);
CREATE INDEX idx_payments_booking ON public.payments(booking_id);
CREATE INDEX idx_payments_status ON public.payments(status);
CREATE INDEX idx_seat_holds_trip ON public.seat_holds(trip_id);
CREATE INDEX idx_seat_holds_expires ON public.seat_holds(expires_at);

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

CREATE TRIGGER update_bus_companies_updated_at BEFORE UPDATE ON public.bus_companies FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
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

-- Bus Companies policies
CREATE POLICY "Anyone can view active companies" ON public.bus_companies
    FOR SELECT USING (is_active = true);

CREATE POLICY "Admins can manage companies" ON public.bus_companies
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.users
            WHERE users.id = auth.uid() AND users.role = 'admin'
        )
    );

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

-- Payments policies
CREATE POLICY "Users can view their own payments" ON public.payments
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.bookings
            WHERE bookings.id = booking_id AND bookings.passenger_id = auth.uid()
        )
    );

-- Seat Holds policies
CREATE POLICY "Users can view their own holds" ON public.seat_holds
    FOR SELECT USING (auth.uid() = user_id);

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
