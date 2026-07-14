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
    
    print("Adding new constraint users_role_check to support contractor role...")
    cur.execute("ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('passenger', 'owner', 'admin', 'contractor'))")
    
    cur.close()
    conn.close()
    print("Database migration for contractor role constraint completed successfully!")
except Exception as e:
    print(f"Migration error: {e}")
