from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.database import engine, Base
import os
from fastapi.staticfiles import StaticFiles
from app.routes import auth, vehicles, trips, bookings, tracking, routes_router, companies, payments, seat_holds, admin, conductors, notifications, schedules, reviews, favourites, uploads

# Create database tables at startup (Convenient for initial setups)
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title=settings.PROJECT_NAME,
    description="Backend API for Seaty - Luxury vehicle booking and real-time tracking platform in Sri Lanka",
    version="1.0.0",
)

# CORS configurations
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Restrict this in production to client domains
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Static Files for Uploads
upload_dir = os.getenv("UPLOAD_DIR", "/app/uploads")
os.makedirs(upload_dir, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=upload_dir), name="uploads")

# Include Routers
app.include_router(auth.router, prefix="/api/v1")
app.include_router(companies.router, prefix="/api/v1")
app.include_router(vehicles.router, prefix="/api/v1")
app.include_router(routes_router.router, prefix="/api/v1")
app.include_router(trips.router, prefix="/api/v1")
app.include_router(bookings.router, prefix="/api/v1")
app.include_router(payments.router, prefix="/api/v1")
app.include_router(seat_holds.router, prefix="/api/v1")
app.include_router(admin.router, prefix="/api/v1")
app.include_router(tracking.router, prefix="/api/v1")
app.include_router(conductors.router, prefix="/api/v1")
app.include_router(notifications.router, prefix="/api/v1")
app.include_router(schedules.router, prefix="/api/v1")
app.include_router(reviews.router, prefix="/api/v1")
app.include_router(favourites.router, prefix="/api/v1")
app.include_router(uploads.router, prefix="/api/v1")

@app.get("/")
def read_root():
    return {
        "status": "online",
        "service": settings.PROJECT_NAME,
        "docs_url": "/docs",
        "version": "1.0.0"
    }

from fastapi import Body

@app.post("/api/v1/public/log")
def public_log_root(payload: dict = Body(...)):
    msg = payload.get("message", "No message provided")
    print(f"[ios-native-log] {msg}")
    return {"ok": True}

import asyncio
import datetime
from app.database import SessionLocal
from app import models

async def trip_reminder_scheduler():
    """Background task to send reminders 30 minutes before a trip starts."""
    while True:
        try:
            db = SessionLocal()
            try:
                now = datetime.datetime.now()
                thirty_mins_from_now = now + datetime.timedelta(minutes=30)
                
                # Fetch confirmed bookings for scheduled trips starting in the next 30 minutes
                upcoming_bookings = db.query(models.Booking).join(models.Trip).filter(
                    models.Booking.booking_status == "confirmed",
                    models.Trip.departure_time > now,
                    models.Trip.departure_time <= thirty_mins_from_now
                ).all()
                
                for booking in upcoming_bookings:
                    # Check if reminder already sent for this booking
                    sent_check = db.query(models.Notification).filter(
                        models.Notification.user_id == booking.passenger_id,
                        models.Notification.type == "trip_reminder",
                        models.Notification.message.like(f"%Booking ID: {booking.id}%")
                    ).first()
                    
                    if not sent_check:
                        from app.routes.notifications import create_and_send_notification
                        
                        trip = booking.trip
                        origin = trip.route.origin if (trip and trip.route) else "Colombo"
                        dest = trip.route.destination if (trip and trip.route) else "Galle"
                        departure = trip.departure_time.strftime("%I:%M %p")
                        
                        title = "Trip Reminder - 30 Mins to Departure"
                        message = (
                            f"Friendly reminder: Your trip from {origin} to {dest} starts at {departure}. "
                            f"Please make sure to be on your pickup point at least 15-30 minutes before departure. "
                            f"Booking ID: {booking.id}"
                        )
                        
                        await create_and_send_notification(
                            db=db,
                            user_id=booking.passenger_id,
                            title=title,
                            message=message,
                            noti_type="trip_reminder"
                        )
            finally:
                db.close()
        except Exception as e:
            print(f"Error in trip_reminder_scheduler: {e}")
            
        # Run every 30 seconds
        await asyncio.sleep(30)

async def auto_expire_bookings_scheduler():
    """Background task to auto-expire past bookings periodically."""
    while True:
        try:
            db = SessionLocal()
            try:
                now = datetime.datetime.now(datetime.timezone.utc)
                candidates = db.query(models.Booking).join(models.Trip).filter(
                    models.Booking.booking_status == "confirmed",
                    models.Trip.departure_time < now
                ).all()

                for b in candidates:
                    boarded = set(b.trip.boarded_seats or [])
                    seats = set(b.selected_seats or [])
                    if seats and seats.issubset(boarded):
                        b.booking_status = "completed"
                    else:
                        b.booking_status = "expired"

                db.commit()
            finally:
                db.close()
        except Exception as e:
            print(f"Error in auto_expire_bookings_scheduler: {e}")

        # Run every 60 seconds
        await asyncio.sleep(60)


@app.on_event("startup")
async def startup_event():
    asyncio.create_task(trip_reminder_scheduler())
    asyncio.create_task(auto_expire_bookings_scheduler())
