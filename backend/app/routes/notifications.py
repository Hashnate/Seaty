from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends, Query, HTTPException, status
from sqlalchemy.orm import Session
from typing import Dict, List, Set
from uuid import UUID
import json
import datetime

from app.database import get_db, SessionLocal
from app import models, schemas, auth

router = APIRouter(prefix="/notifications", tags=["Notifications"])

# =====================================================================
# Real-Time WebSocket Connection Manager
# =====================================================================
class NotificationManager:
    def __init__(self):
        # Maps user_id -> set of active WebSockets
        self.active_connections: Dict[str, Set[WebSocket]] = {}

    async def connect(self, user_id: str, websocket: WebSocket):
        await websocket.accept()
        if user_id not in self.active_connections:
            self.active_connections[user_id] = set()
        self.active_connections[user_id].add(websocket)

    def disconnect(self, user_id: str, websocket: WebSocket):
        if user_id in self.active_connections:
            self.active_connections[user_id].discard(websocket)
            if not self.active_connections[user_id]:
                del self.active_connections[user_id]

    async def send_to_user(self, user_id: str, notification_payload: dict):
        uid_str = str(user_id)
        if uid_str in self.active_connections:
            closed = set()
            for ws in self.active_connections[uid_str]:
                try:
                    await ws.send_json(notification_payload)
                except Exception:
                    closed.add(ws)
            for ws in closed:
                self.active_connections[uid_str].discard(ws)

manager = NotificationManager()

# =====================================================================
# Database Saver and Broadcaster Utility
# =====================================================================
async def create_and_send_notification(
    db: Session,
    user_id: UUID,
    title: str,
    message: str,
    noti_type: str
):
    """Save notification to Postgres and broadcast live if user online."""
    db_noti = models.Notification(
        user_id=user_id,
        title=title,
        message=message,
        type=noti_type,
        is_read=False
    )
    db.add(db_noti)
    db.commit()
    db.refresh(db_noti)

    payload = {
        "id": str(db_noti.id),
        "user_id": str(db_noti.user_id),
        "title": db_noti.title,
        "message": db_noti.message,
        "type": db_noti.type,
        "is_read": db_noti.is_read,
        "created_at": db_noti.created_at.isoformat()
    }
    await manager.send_to_user(user_id, payload)
    return db_noti

# =====================================================================
# WebSocket Endpoint
# =====================================================================
@router.websocket("/ws")
async def notifications_websocket_endpoint(
    websocket: WebSocket,
    token: str = Query(..., description="JWT authentication token")
):
    db: Session = SessionLocal()
    user_id_str = None
    try:
        try:
            user = auth.get_current_user(token=token, db=db)
            user_id_str = str(user.id)
        except Exception:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Authentication failed")
            return

        await manager.connect(user_id_str, websocket)
        try:
            while True:
                # Keep socket alive by listening to incoming texts (e.g. pings)
                await websocket.receive_text()
        except WebSocketDisconnect:
            if user_id_str:
                manager.disconnect(user_id_str, websocket)
    finally:
        db.close()

# =====================================================================
# REST Endpoints for History and Marking Read
# =====================================================================
@router.get("", response_model=List[schemas.NotificationResponse])
def get_notifications(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    """Retrieve history of notifications for current logged in user."""
    return db.query(models.Notification).filter(
        models.Notification.user_id == current_user.id
    ).order_by(models.Notification.created_at.desc()).all()

@router.post("/{notification_id}/read", response_model=schemas.NotificationResponse)
def mark_as_read(
    notification_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    """Mark a single notification as read."""
    noti = db.query(models.Notification).filter(
        models.Notification.id == notification_id,
        models.Notification.user_id == current_user.id
    ).first()
    if not noti:
        raise HTTPException(status_code=404, detail="Notification not found")
    
    noti.is_read = True
    db.commit()
    db.refresh(noti)
    return noti

@router.post("/read-all")
def mark_all_as_read(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    """Mark all notifications of the current user as read."""
    db.query(models.Notification).filter(
        models.Notification.user_id == current_user.id,
        models.Notification.is_read == False
    ).update({"is_read": True})
    db.commit()
    return {"status": "success", "message": "All notifications marked as read"}
