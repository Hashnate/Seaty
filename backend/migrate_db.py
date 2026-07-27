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

    cur.close()
    conn.close()
    print("Database migration completed successfully!")
except Exception as e:
    print(f"Migration error: {e}")
