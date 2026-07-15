#!/bin/sh

# Wait for database to be ready
echo "Waiting for database..."
until python -c "import os, psycopg2; psycopg2.connect(os.environ['DATABASE_URL'])" 2>/dev/null; do
  sleep 1
done
echo "Database is ready!"

# Run database migrations
echo "Running migrations..."
python migrate_db.py

# Start the FastAPI application
echo "Starting FastAPI backend..."
exec uvicorn app.main:app --host 0.0.0.0 --port 8000
