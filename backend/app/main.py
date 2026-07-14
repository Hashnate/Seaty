from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.database import engine, Base
from app.routes import auth, vehicles, trips, bookings, tracking, routes_router, companies, payments, seat_holds, admin, contractors

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
app.include_router(contractors.router, prefix="/api/v1")

@app.get("/")
def read_root():
    return {
        "status": "online",
        "service": settings.PROJECT_NAME,
        "docs_url": "/docs",
        "version": "1.0.0"
    }
