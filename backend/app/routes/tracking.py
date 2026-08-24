from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends, Query, status
from typing import Dict, List, Set
from uuid import UUID
import json
import datetime
import math

from app.database import session_scope
from app import models, schemas, auth

router = APIRouter(prefix="/ws", tags=["Real-time Tracking"])

# A Sri Lankan inter-city bus realistically never exceeds ~110 km/h; anything implying
# more than this between two fixes is a GPS glitch/jump, not real travel.
MAX_PLAUSIBLE_SPEED_KMH = 150.0


def _as_utc(dt: datetime.datetime | None) -> datetime.datetime | None:
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=datetime.timezone.utc)
    return dt.astimezone(datetime.timezone.utc)


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))

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
    # Authenticate and authorise on a session that is released before the
    # socket starts, and do the per-fix work on a session that lives no longer
    # than the fix. The previous version held one Session for the whole socket,
    # which pinned a pooled connection for the entire journey. See
    # `session_scope`.
    with session_scope() as db:
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
        elif role != "passenger":
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Invalid role specified")
            return

    if role == "driver":
        await manager.connect_driver(vehicle_id, websocket)

        try:
            while True:
                # Expect coordinates: {"latitude": 6.9271, "longitude": 79.8612, "speed": 45.0, "heading": 180.0}
                data_str = await websocket.receive_text()

                try:
                    data = json.loads(data_str)

                    # Validate coordinate fields
                    lat = float(data["latitude"])
                    lon = float(data["longitude"])
                    speed = float(data.get("speed", 0.0))
                    heading = float(data.get("heading", 0.0))

                    if not (-90.0 <= lat <= 90.0) or not (-180.0 <= lon <= 180.0):
                        continue

                    now = datetime.datetime.now(datetime.timezone.utc)

                    with session_scope() as db:
                        # Save / Update location in database
                        db_location = db.query(models.VehicleLocation).filter(
                            models.VehicleLocation.vehicle_id == vehicle_id
                        ).first()

                        if db_location:
                            # Reject implausible GPS jumps (glitch/spoofed fix) instead of
                            # broadcasting a teleporting bus to passengers.
                            elapsed = (now - _as_utc(db_location.updated_at)).total_seconds()
                            if elapsed > 0.5:
                                jump_km = _haversine_km(
                                    float(db_location.latitude), float(db_location.longitude), lat, lon
                                )
                                implied_speed_kmh = jump_km / (elapsed / 3600)
                                if implied_speed_kmh > MAX_PLAUSIBLE_SPEED_KMH:
                                    continue

                            db_location.latitude = lat
                            db_location.longitude = lon
                            db_location.speed = speed
                            db_location.heading = heading
                            db_location.updated_at = now
                        else:
                            db_location = models.VehicleLocation(
                                vehicle_id=vehicle_id,
                                latitude=lat,
                                longitude=lon,
                                speed=speed,
                                heading=heading,
                                updated_at=now
                            )
                            db.add(db_location)

                        # Breadcrumb trail - one row per accepted fix, never overwritten
                        db.add(models.VehicleLocationHistory(
                            vehicle_id=vehicle_id,
                            latitude=lat,
                            longitude=lon,
                            speed=speed,
                            heading=heading,
                            recorded_at=now,
                        ))

                        db.commit()

                    # Broadcast location update to passengers
                    broadcast_payload = {
                        "vehicle_id": vehicle_id,
                        "latitude": lat,
                        "longitude": lon,
                        "speed": speed,
                        "heading": heading,
                        "updated_at": now.isoformat()
                    }
                    await manager.broadcast_location(vehicle_id, broadcast_payload)
                except (KeyError, ValueError, TypeError, json.JSONDecodeError):
                    # A single malformed or implausible fix shouldn't kill the whole
                    # GPS stream - skip it and keep listening for the next one.
                    # The session was closed on the way out of its `with`, which
                    # rolls back anything half-written.
                    continue
        except WebSocketDisconnect:
            pass
        except Exception:
            pass
        finally:
            manager.disconnect_driver(vehicle_id)

    else:
        await manager.connect_passenger(vehicle_id, websocket)

        # Send the last known location if it exists. Read it out into a plain
        # dict inside the scope - the ORM object is detached once the session
        # closes, and touching it afterwards raises.
        with session_scope() as db:
            last_location = db.query(models.VehicleLocation).filter(
                models.VehicleLocation.vehicle_id == vehicle_id
            ).first()
            last_known = {
                "vehicle_id": str(last_location.vehicle_id),
                "latitude": float(last_location.latitude),
                "longitude": float(last_location.longitude),
                "speed": float(last_location.speed) if last_location.speed else 0.0,
                "heading": float(last_location.heading) if last_location.heading else 0.0,
                "updated_at": last_location.updated_at.isoformat()
            } if last_location else None

        if last_known:
            try:
                await websocket.send_json(last_known)
            except Exception:
                pass

        try:
            while True:
                # Passengers only receive updates, but we keep the socket open by waiting for pings/messages
                await websocket.receive_text()
        except WebSocketDisconnect:
            pass
        finally:
            manager.disconnect_passenger(vehicle_id, websocket)
