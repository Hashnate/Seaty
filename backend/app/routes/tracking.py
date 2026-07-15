from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends, Query, status
from sqlalchemy.orm import Session
from typing import Dict, List, Set
from uuid import UUID
import json
import datetime

from app.database import SessionLocal
from app import models, schemas, auth

router = APIRouter(prefix="/ws", tags=["Real-time Tracking"])

# =====================================================================
# WebSocket Connection Manager
# =====================================================================
class TrackingManager:
    def __init__(self):
        # Maps vehicle_id -> set of passenger WebSocket connections
        self.active_listeners: Dict[str, Set[WebSocket]] = {}
        # Maps vehicle_id -> driver WebSocket connection (only one driver can stream location per vehicle)
        self.active_drivers: Dict[str, WebSocket] = {}

    async def connect_passenger(self, vehicle_id: str, websocket: WebSocket):
        await websocket.accept()
        if vehicle_id not in self.active_listeners:
            self.active_listeners[vehicle_id] = set()
        self.active_listeners[vehicle_id].add(websocket)

    def disconnect_passenger(self, vehicle_id: str, websocket: WebSocket):
        if vehicle_id in self.active_listeners:
            self.active_listeners[vehicle_id].discard(websocket)
            if not self.active_listeners[vehicle_id]:
                del self.active_listeners[vehicle_id]

    async def connect_driver(self, vehicle_id: str, websocket: WebSocket):
        await websocket.accept()
        # Disconnect previous driver socket if one was active
        if vehicle_id in self.active_drivers:
            try:
                await self.active_drivers[vehicle_id].close(code=status.WS_1008_POLICY_VIOLATION)
            except Exception:
                pass
        self.active_drivers[vehicle_id] = websocket

    def disconnect_driver(self, vehicle_id: str):
        if vehicle_id in self.active_drivers:
            del self.active_drivers[vehicle_id]

    async def broadcast_location(self, vehicle_id: str, location_data: dict):
        if vehicle_id in self.active_listeners:
            closed_sockets = set()
            for connection in self.active_listeners[vehicle_id]:
                try:
                    await connection.send_json(location_data)
                except Exception:
                    closed_sockets.add(connection)
            
            # Clean up closed sockets
            for socket in closed_sockets:
                self.active_listeners[vehicle_id].discard(socket)

manager = TrackingManager()

# =====================================================================
# Real-Time WebSocket Endpoint
# =====================================================================
@router.websocket("/tracking/{vehicle_id}")
async def tracking_endpoint(
    websocket: WebSocket,
    vehicle_id: str,
    role: str = Query(..., description="driver or passenger"),
    token: str = Query(..., description="JWT authentication token")
):
    # Create manual DB session for this long-running socket thread
    db: Session = SessionLocal()
    
    try:
        # 1. Authenticate user via token query param
        try:
            user = auth.get_current_user(token=token, db=db)
        except Exception:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Authentication failed")
            return

        # 2. Check permissions based on requested role
        if role == "driver":
            vehicle = db.query(models.Vehicle).filter(
                models.Vehicle.id == vehicle_id
            ).first()
            if not vehicle:
                await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Vehicle not found")
                return
            
            # Check permission: user must be the owner of the vehicle, or a conductor/admin in the same company
            is_owner = (user.role == "owner" and vehicle.owner_id == user.id)
            is_company_conductor = (user.role == "conductor" and vehicle.company_id == user.company_id and user.company_id is not None)
            is_admin = (user.role == "admin")
            
            if not (is_owner or is_company_conductor or is_admin):
                await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Unauthorized vehicle stream")
                return
            
            await manager.connect_driver(vehicle_id, websocket)
            
            try:
                while True:
                    # Expect coordinates: {"latitude": 6.9271, "longitude": 79.8612, "speed": 45.0, "heading": 180.0}
                    data_str = await websocket.receive_text()
                    data = json.loads(data_str)
                    
                    # Validate coordinate fields
                    lat = float(data["latitude"])
                    lon = float(data["longitude"])
                    speed = float(data.get("speed", 0.0))
                    heading = float(data.get("heading", 0.0))
                    
                    # Save / Update location in database
                    db_location = db.query(models.VehicleLocation).filter(
                        models.VehicleLocation.vehicle_id == vehicle_id
                    ).first()
                    
                    if not db_location:
                        db_location = models.VehicleLocation(
                            vehicle_id=vehicle_id,
                            latitude=lat,
                            longitude=lon,
                            speed=speed,
                            heading=heading,
                            updated_at=datetime.datetime.utcnow()
                        )
                        db.add(db_location)
                    else:
                        db_location.latitude = lat
                        db_location.longitude = lon
                        db_location.speed = speed
                        db_location.heading = heading
                        db_location.updated_at = datetime.datetime.utcnow()
                    
                    db.commit()
                    
                    # Broadcast location update to passengers
                    broadcast_payload = {
                        "vehicle_id": vehicle_id,
                        "latitude": lat,
                        "longitude": lon,
                        "speed": speed,
                        "heading": heading,
                        "updated_at": datetime.datetime.utcnow().isoformat()
                    }
                    await manager.broadcast_location(vehicle_id, broadcast_payload)
            except WebSocketDisconnect:
                manager.disconnect_driver(vehicle_id)
            except Exception as e:
                # Catch JSON parsing / DB exceptions gracefully
                manager.disconnect_driver(vehicle_id)
                
        elif role == "passenger":
            await manager.connect_passenger(vehicle_id, websocket)
            
            # Send the last known location if it exists
            last_location = db.query(models.VehicleLocation).filter(
                models.VehicleLocation.vehicle_id == vehicle_id
            ).first()
            if last_location:
                try:
                    await websocket.send_json({
                        "vehicle_id": str(last_location.vehicle_id),
                        "latitude": float(last_location.latitude),
                        "longitude": float(last_location.longitude),
                        "speed": float(last_location.speed) if last_location.speed else 0.0,
                        "heading": float(last_location.heading) if last_location.heading else 0.0,
                        "updated_at": last_location.updated_at.isoformat()
                    })
                except Exception:
                    pass
            
            try:
                while True:
                    # Passengers only receive updates, but we keep the socket open by waiting for pings/messages
                    await websocket.receive_text()
            except WebSocketDisconnect:
                manager.disconnect_passenger(vehicle_id, websocket)
                
        else:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Invalid role specified")
            
    finally:
        db.close()
