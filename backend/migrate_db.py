import os
import psycopg2

try:
    database_url = os.getenv("DATABASE_URL")
    if database_url:
        conn = psycopg2.connect(database_url)
    else:
        password = ""
        conn = psycopg2.connect(
            dbname="seaty",
            user="postgres",
            password=password,
            host="localhost",
            port=5432
        )
    conn.autocommit = True
    cur = conn.cursor()
    
    # 1. Update user role check constraint
    print("Dropping old constraint users_role_check if exists...")
    cur.execute("ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check")
    
    print("Updating existing contractor roles to conductor...")
    cur.execute("UPDATE users SET role = 'conductor' WHERE role = 'contractor'")
    
    print("Adding new constraint users_role_check to support conductor role...")
    cur.execute("ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('passenger', 'owner', 'admin', 'conductor'))")
    
    # 2. Add conductor_id to trips
    print("Adding conductor_id column to trips...")
    try:
        cur.execute("ALTER TABLE trips ADD COLUMN conductor_id UUID REFERENCES users(id) ON DELETE SET NULL")
    except Exception as e:
        print(f"trips column might already exist: {e}")
        
    # 3. Add conductor_id to trip_schedules
    print("Adding conductor_id column to trip_schedules...")
    try:
        cur.execute("ALTER TABLE trip_schedules ADD COLUMN conductor_id UUID REFERENCES users(id) ON DELETE SET NULL")
    except Exception as e:
        print(f"trip_schedules column might already exist: {e}")
        
    # 4. Convert all vehicle seat_layouts to purely numeric seat labels (1, 2, 3... N)
    print("Migrating vehicle seat layouts to purely numeric labels...")
    cur.execute("SELECT id, name, registration_number, total_seats, seat_layout FROM vehicles")
    rows = cur.fetchall()
    import json
    for row in rows:
        v_id, name, reg, total, layout = row
        if not layout:
            layout = {}
        seats = layout.get('seats', [])
        new_seats = []
        if seats:
            for i, s in enumerate(seats, start=1):
                new_seats.append({
                    'col': s.get('col', 0),
                    'row': s.get('row', 1),
                    'label': str(i)
                })
        else:
            tot = total or 40
            r_count = (tot + 3) // 4
            s_num = 1
            for r in range(1, r_count + 1):
                for c in range(5):
                    if c == 2 and r < r_count:
                        continue
                    if s_num <= tot:
                        new_seats.append({'col': c, 'row': r, 'label': str(s_num)})
                        s_num += 1
        layout['seats'] = new_seats
        cur.execute("UPDATE vehicles SET seat_layout = %s WHERE id = %s", (json.dumps(layout), v_id))
    print("Vehicle seat layout migration to numeric labels completed!")

    # 5. Add new vehicle columns (contact_phone, main_image_url, gallery_image_urls)
    print("Adding vehicle columns (contact_phone, main_image_url, gallery_image_urls)...")
    for col_def in [
        "contact_phone TEXT",
        "main_image_url TEXT",
        "gallery_image_urls TEXT[] DEFAULT '{}'"
    ]:
        col_name = col_def.split()[0]
        try:
            cur.execute(f"ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS {col_def}")
        except Exception as e:
            print(f"Error adding {col_name} to vehicles: {e}")

    # 6. Create user_favourites table
    print("Creating user_favourites table if not exists...")
    cur.execute("""
        CREATE TABLE IF NOT EXISTS user_favourites (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            schedule_id UUID REFERENCES trip_schedules(id) ON DELETE CASCADE,
            vehicle_id UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT unique_user_favourite UNIQUE (user_id, vehicle_id, schedule_id)
        );
    """)

    # 7. Update bookings booking_status check constraint to support 'completed' and 'expired'
    print("Updating bookings_booking_status_check constraint...")
    try:
        cur.execute("ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_booking_status_check")
        cur.execute("ALTER TABLE bookings ADD CONSTRAINT bookings_booking_status_check CHECK (booking_status IN ('pending', 'confirmed', 'cancelled', 'completed', 'expired'))")
    except Exception as e:
        print(f"Error updating bookings_booking_status_check: {e}")

    # 8. Add booking_id and is_verified columns to reviews table
    print("Adding booking_id and is_verified columns to reviews table...")
    try:
        cur.execute("ALTER TABLE reviews ADD COLUMN IF NOT EXISTS booking_id UUID REFERENCES bookings(id) ON DELETE SET NULL")
        cur.execute("ALTER TABLE reviews ADD COLUMN IF NOT EXISTS is_verified BOOLEAN NOT NULL DEFAULT TRUE")
    except Exception as e:
        print(f"Error updating reviews table: {e}")

    # 9. Add booking_id and vehicle_id columns to notifications table
    print("Adding booking_id and vehicle_id columns to notifications table...")
    try:
        cur.execute("ALTER TABLE notifications ADD COLUMN IF NOT EXISTS booking_id UUID REFERENCES bookings(id) ON DELETE SET NULL")
        cur.execute("ALTER TABLE notifications ADD COLUMN IF NOT EXISTS vehicle_id UUID REFERENCES vehicles(id) ON DELETE SET NULL")
    except Exception as e:
        print(f"Error updating notifications table: {e}")

    # 10. Seed support_phone platform setting
    print("Upserting support_phone setting...")
    try:
        cur.execute("INSERT INTO platform_settings (key, value, description) VALUES ('support_phone', '0262237803', 'Customer support contact phone number') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value")
    except Exception as e:
        print(f"Error upserting support_phone: {e}")

    # 11. Create vehicle_location_history table (breadcrumb trail for live tracking)
    print("Creating vehicle_location_history table if not exists...")
    try:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS vehicle_location_history (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                vehicle_id UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
                latitude DOUBLE PRECISION NOT NULL,
                longitude DOUBLE PRECISION NOT NULL,
                speed NUMERIC(5, 2),
                heading NUMERIC(5, 2),
                recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            );
        """)
        cur.execute("""
            CREATE INDEX IF NOT EXISTS idx_vehicle_location_history_vehicle_time
            ON vehicle_location_history(vehicle_id, recorded_at);
        """)
    except Exception as e:
        print(f"Error creating vehicle_location_history table: {e}")

    # 12. Create hero_banners table (admin-managed passenger home carousel)
    print("Creating hero_banners table if not exists...")
    try:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS hero_banners (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                image_url TEXT NOT NULL,
                title TEXT,
                subtitle TEXT,
                sort_order INTEGER NOT NULL DEFAULT 0,
                is_active BOOLEAN NOT NULL DEFAULT TRUE,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            );
        """)
        cur.execute("""
            CREATE INDEX IF NOT EXISTS idx_hero_banners_active_order
            ON hero_banners(is_active, sort_order);
        """)
    except Exception as e:
        print(f"Error creating hero_banners table: {e}")

    # 13. Idempotency guard for the payment gateway reference. The return
    # handler and the reconciliation sweeper both look a payment up by
    # gateway_transaction_id; two rows sharing one reqid would make that
    # lookup ambiguous and could double-confirm a booking.
    print("Adding unique constraint on payments.gateway_transaction_id...")
    try:
        cur.execute("""
            DELETE FROM payments a USING payments b
            WHERE a.ctid < b.ctid
              AND a.gateway_transaction_id = b.gateway_transaction_id
              AND a.gateway_transaction_id IS NOT NULL
        """)
        cur.execute("""
            CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_gateway_txn
            ON payments(gateway_transaction_id)
            WHERE gateway_transaction_id IS NOT NULL
        """)
    except Exception as e:
        print(f"Error adding unique index on payments.gateway_transaction_id: {e}")

    # 14. Server-side session invalidation. Bumped on logout; every JWT carries
    # the value it was minted with, so a bump kills tokens already issued.
    print("Adding users.token_version...")
    try:
        cur.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS token_version INTEGER NOT NULL DEFAULT 1")
    except Exception as e:
        print(f"Error adding users.token_version: {e}")

    # 15. The reversible "temporarily off" switch, at all three levels a bus can
    # be taken out of sale: one trip instance, one recurring schedule, or the
    # whole vehicle. Defaults to TRUE so every existing row stays on sale.
    #
    # This is deliberately not the same thing as trips.status='cancelled'
    # (irreversible, cancels bookings, triggers refunds/SMS) or
    # vehicles.is_verified (admin document approval) or trip_schedules.is_active
    # (stops materialising future trips but leaves generated ones bookable).
    print("Adding booking_enabled / suspension_reason off switches...")
    for table, cols in (
        ("trips", ("booking_enabled BOOLEAN NOT NULL DEFAULT TRUE", "suspension_reason TEXT")),
        ("trip_schedules", ("booking_enabled BOOLEAN NOT NULL DEFAULT TRUE", "suspension_reason TEXT")),
        ("vehicles", ("booking_enabled BOOLEAN NOT NULL DEFAULT TRUE", "suspension_reason TEXT")),
    ):
        for col_def in cols:
            try:
                cur.execute(f"ALTER TABLE {table} ADD COLUMN IF NOT EXISTS {col_def}")
            except Exception as e:
                print(f"Error adding {col_def.split()[0]} to {table}: {e}")

    # 16. Global sales kill switch, read by app/services/availability.py.
    # Seeded as 'true' so an existing deployment is unaffected by the upgrade.
    print("Seeding bookings_enabled platform setting...")
    try:
        cur.execute(
            "INSERT INTO platform_settings (key, value, description) "
            "VALUES ('bookings_enabled', 'true', "
            "'Global switch. Set to false to stop all new seat bookings platform-wide.') "
            "ON CONFLICT (key) DO NOTHING"
        )
    except Exception as e:
        print(f"Error seeding bookings_enabled: {e}")

    # NOTE: step 12 (a one-time -5:30 shift of existing trips.departure_time/
    # arrival_time) was removed here. It assumed the Postgres session timezone
    # defaulted to UTC, which was never confirmed against the live database and
    # turned out to be wrong - existing trip times were already correct.
    # See app/timezone_utils.py for the (still valid) going-forward write/read
    # helpers; do not reintroduce a blind historical-data shift without first
    # confirming `SHOW timezone;` against production and getting explicit sign-off.

    cur.close()
    conn.close()
    print("Database migration completed successfully!")
except Exception as e:
    print(f"Migration error: {e}")
