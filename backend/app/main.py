import logging

# Uvicorn leaves the root logger at WARNING, so every logger.info in this
# codebase was silently discarded - including the Notify.lk response, the only
# record of whether an OTP was actually accepted for delivery.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
)

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.database import engine, Base
import os
from fastapi.staticfiles import StaticFiles
from app.routes import auth, vehicles, trips, bookings, tracking, routes_router, companies, payments, seat_holds, admin, conductors, notifications, schedules, reviews, favourites, uploads, banners

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
app.include_router(banners.router, prefix="/api/v1")

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
from app.timezone_utils import now_sl, to_sl

async def trip_reminder_scheduler():
    """Background task to send reminders 30 minutes before a trip starts."""
    while True:
        try:
            db = SessionLocal()
            try:
                now = now_sl()
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
                        departure = to_sl(trip.departure_time).strftime("%I:%M %p")
                        
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
                            noti_type="trip_reminder",
                            booking_id=booking.id
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
                now = now_sl()
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


async def payment_reconciliation_sweeper():
    """Resolve payments whose customer never made it back to us.

    Bancstac has no server-to-server callback: we only learn a payment
    succeeded because the payer's browser is redirected to our return URL. If
    the app is backgrounded, the connection drops, or the phone dies between
    paying and redirecting, that redirect never arrives - card charged, booking
    unconfirmed, seat released. On mobile data that is routine.

    This is the replacement for the webhook. Every pending payment gets
    re-asked until the gateway gives a verdict or its 30-minute session
    expires. See docs/PAYMENTS.md.
    """
    from app.services.payment_gateway import get_gateway, PaymentGatewayUnavailable

    while True:
        await asyncio.sleep(60)
        try:
            get_gateway()
        except PaymentGatewayUnavailable:
            continue
        except Exception:
            continue  # misconfigured; initiate_payment reports it properly

        db = SessionLocal()
        try:
            now = datetime.datetime.now(datetime.timezone.utc)
            # Give the normal return path a couple of minutes before stepping
            # in, and stop once Bancstac's session has expired.
            candidates = db.query(models.Payment).filter(
                models.Payment.status == "pending",
                models.Payment.gateway_transaction_id.isnot(None),
                models.Payment.created_at <= now - datetime.timedelta(minutes=2),
                models.Payment.created_at >= now - datetime.timedelta(minutes=35),
            ).all()

            if candidates:
                from app.routes.payments import finalise_payment
                print(f"[payment-sweeper] re-checking {len(candidates)} pending payment(s)")
                for payment in candidates:
                    try:
                        if await finalise_payment(db, payment):
                            print(f"[payment-sweeper] recovered payment {payment.id}")
                    except Exception as e:
                        print(f"[payment-sweeper] {payment.id}: {e}")
        except Exception as e:
            print(f"Error in payment_reconciliation_sweeper: {e}")
        finally:
            db.close()


@app.on_event("startup")
async def startup_event():
    asyncio.create_task(trip_reminder_scheduler())
    asyncio.create_task(auto_expire_bookings_scheduler())
    asyncio.create_task(payment_reconciliation_sweeper())
