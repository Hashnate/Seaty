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

    cur.close()
    conn.close()
    print("Database migration completed successfully!")
except Exception as e:
    print(f"Migration error: {e}")
