import psycopg2

password = ""
try:
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
        
    cur.close()
    conn.close()
    print("Database migration for conductor role constraint completed successfully!")
except Exception as e:
    print(f"Migration error: {e}")
