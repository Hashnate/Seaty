import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT

password = ""
print(f"Connecting to PostgreSQL with password: '{password}'...")

try:
    conn = psycopg2.connect(
        dbname="postgres",
        user="postgres",
        password=password,
        host="localhost",
        port=5432,
        connect_timeout=5
    )
    
    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    cur = conn.cursor()
    
    # Check if database 'seaty' exists
    cur.execute("SELECT 1 FROM pg_catalog.pg_database WHERE datname = 'seaty'")
    exists = cur.fetchone()
    if not exists:
        cur.execute("CREATE DATABASE seaty")
        print("Successfully created database 'seaty'!")
    else:
        print("Database 'seaty' already exists.")
        
    cur.close()
    conn.close()

    # Update .env
    env_content = f"""# Database connection settings
# Format: postgresql://[user]:[password]@[host]:[port]/[database]
DATABASE_URL=postgresql://postgres:{password}@localhost:5432/seaty

# Secret key for JWT signing
SECRET_KEY=SUPER_SECRET_KEY_SEATY_1234567890_CHANGEME_IN_PRODUCTION
"""
    with open(".env", "w") as f:
        f.write(env_content)
    print("Updated .env file with correct password and database settings.")

except Exception as e:
    print(f"Error setting up database: {e}")
