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

def send_fcm_push(fcm_token: str, title: str, message: str, data: dict = None):
    """Sends native FCM push notification via firebase_admin SDK."""
    if not fcm_token:
        print("FCM Push skipped: no FCM token provided")
        return
    try:
        import os
        import firebase_admin
        from firebase_admin import messaging, credentials

        if not firebase_admin._apps:
            cred_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
            if cred_path and os.path.exists(cred_path):
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred)
                print(f"Firebase Admin SDK initialized with credentials from {cred_path}")
            else:
                print(f"WARNING: Firebase credentials not found at {cred_path}. FCM push will fail.")
                return
        
        msg = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=message,
            ),
            data={k: str(v) for k, v in (data or {}).items()},
            token=fcm_token,
        )
        response = messaging.send(msg)
        print(f"FCM Push sent successfully: {response}")
    except Exception as e:
        print(f"FCM Push notification error: {e}")

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
    """Save notification to Postgres, broadcast live via WS, and send FCM Push."""
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

    # Send native FCM Push Notification if user has registered FCM token
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if user and user.fcm_token:
        send_fcm_push(user.fcm_token, title, message, {"type": noti_type, "id": str(db_noti.id)})

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


@router.post("/broadcast")
async def broadcast_notification(
    payload: schemas.NotificationBroadcast,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    """Broadcast a push notification to all users of a specific role, or all users."""
    query = db.query(models.User)
    if payload.target_role != "all":
        query = query.filter(models.User.role == payload.target_role)
    users = query.all()

    db_notifications = []
    for user in users:
        db_noti = models.Notification(
            user_id=user.id,
            title=payload.title,
            message=payload.message,
            type="system",
            is_read=False
        )
        db.add(db_noti)
        db_notifications.append(db_noti)

    db.commit()

    # Refresh notifications to populate DB-generated fields before sending to WebSocket
    for db_noti in db_notifications:
        db.refresh(db_noti)
        ws_payload = {
            "id": str(db_noti.id),
            "user_id": str(db_noti.user_id),
            "title": db_noti.title,
            "message": db_noti.message,
            "type": db_noti.type,
            "is_read": db_noti.is_read,
            "created_at": db_noti.created_at.isoformat()
        }
        await manager.send_to_user(db_noti.user_id, ws_payload)

        # Trigger native FCM push
        user_obj = next((u for u in users if u.id == db_noti.user_id), None)
        if user_obj and user_obj.fcm_token:
            send_fcm_push(user_obj.fcm_token, payload.title, payload.message, {"type": "system", "id": str(db_noti.id)})

    return {"status": "success", "message": f"Notification broadcasted to {len(users)} users"}


@router.post("/fcm-token")
def update_fcm_token(
    payload: schemas.FCMTokenUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    """Update current user's FCM device token for native push notifications."""
    old_token = current_user.fcm_token
    current_user.fcm_token = payload.fcm_token
    db.commit()
    print(f"FCM token updated for user {current_user.id} ({current_user.full_name}): "
          f"had_previous={'yes' if old_token else 'no'}, new_token={payload.fcm_token[:20]}...")
    return {"status": "success", "message": "FCM token updated successfully"}


@router.get("/fcm-status")
def fcm_status(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    """Diagnostic: Check FCM configuration and token status across all users."""
    import os
    cred_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "NOT SET")
    cred_exists = os.path.exists(cred_path) if cred_path != "NOT SET" else False

    users = db.query(models.User).all()
    users_with_tokens = [u for u in users if u.fcm_token]
    users_without_tokens = [u for u in users if not u.fcm_token]

    return {
        "firebase_credentials_env": cred_path,
        "firebase_credentials_file_exists": cred_exists,
        "total_users": len(users),
        "users_with_fcm_token": len(users_with_tokens),
        "users_without_fcm_token": len(users_without_tokens),
        "users_detail": [
            {
                "id": str(u.id),
                "name": u.full_name,
                "role": u.role,
                "has_fcm_token": bool(u.fcm_token),
            }
            for u in users
        ],
    }


@router.post("/public/log")
def public_log(payload: dict = Body(...)):
    """Public logging endpoint for native iOS and client diagnostics."""
    msg = payload.get("message", "No message provided")
    print(f"[client-log] {msg}")
    return {"ok": True}
