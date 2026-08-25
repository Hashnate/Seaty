from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends, Query, HTTPException, status, Body
from sqlalchemy.orm import Session
from typing import Dict, List, Set
from uuid import UUID
import json
import datetime

from starlette.concurrency import run_in_threadpool

from app.database import get_db, session_scope
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

def send_fcm_push(fcm_token: str, title: str, message: str, data: dict = None,
                  badge: int = None):
    """Sends native FCM push notification via firebase_admin SDK.

    `badge` is the recipient's unread count. iOS keeps whatever number APNs
    last wrote until the app clears it, so a constant here would pin the
    app-icon badge at that value for good - through reading, sign-out, and
    into the next user's session. Pass the real count, or None to leave the
    badge untouched.
    """
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
        
        # Configure high-priority delivery and system tray alerts for Android
        android_config = messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                sound="default",
                priority="high",
                default_vibrate_timings=True,
                default_sound=True,
            ),
        )

        # Configure high-priority delivery, sound and badges for iOS APNs.
        #
        # No `content_available`: it marks an alert as *also* a silent
        # background push, which iOS throttles against a per-app budget, and
        # nothing here consumes a background wake - the handler only logs. It
        # bought nothing and risked delivery.
        apns_config = messaging.APNSConfig(
            headers={"apns-priority": "10"},
            payload=messaging.APNSPayload(
                aps=messaging.Aps(
                    alert=messaging.ApsAlert(title=title, body=message),
                    sound="default",
                    badge=badge,
                )
            ),
        )

        msg = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=message,
            ),
            data={k: str(v) for k, v in (data or {}).items()},
            token=fcm_token,
            android=android_config,
            apns=apns_config,
        )
        response = messaging.send(msg)
        print(f"FCM Push sent successfully: {response}")
    except Exception as e:
        print(f"FCM Push notification error: {e}")

def unread_count(db: Session, user_id: UUID) -> int:
    """How many notifications this user has not read yet.

    Sent as the APNs badge so the app icon shows the recipient's real state.
    """
    return db.query(models.Notification).filter(
        models.Notification.user_id == user_id,
        models.Notification.is_read.is_(False),
    ).count()

# =====================================================================
# Database Saver and Broadcaster Utility
# =====================================================================
async def create_and_send_notification(
    db: Session,
    user_id: UUID,
    title: str,
    message: str,
    noti_type: str,
    booking_id: UUID = None,
    vehicle_id: UUID = None
):
    """Save notification to Postgres, broadcast live via WS, and send FCM Push."""
    db_noti = models.Notification(
        user_id=user_id,
        title=title,
        message=message,
        type=noti_type,
        booking_id=booking_id,
        vehicle_id=vehicle_id,
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
        "booking_id": str(db_noti.booking_id) if db_noti.booking_id else None,
        "vehicle_id": str(db_noti.vehicle_id) if db_noti.vehicle_id else None,
        "is_read": db_noti.is_read,
        "created_at": db_noti.created_at.isoformat()
    }
    await manager.send_to_user(user_id, payload)

    # Send native FCM Push Notification if user has registered FCM token
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if user and user.fcm_token:
        fcm_data = {"type": noti_type, "id": str(db_noti.id)}
        if booking_id:
            fcm_data["booking_id"] = str(booking_id)
        if vehicle_id:
            fcm_data["vehicle_id"] = str(vehicle_id)
        # `send_fcm_push` is a blocking HTTPS round-trip to Google. One event
        # loop serves every WebSocket in this process, so calling it directly
        # from an `async def` stalls every socket and every in-flight request
        # until Firebase answers.
        await run_in_threadpool(
            send_fcm_push, user.fcm_token, title, message, fcm_data,
            unread_count(db, user_id),
        )

    return db_noti

# =====================================================================
# WebSocket Endpoint
# =====================================================================
@router.websocket("/ws")
async def notifications_websocket_endpoint(
    websocket: WebSocket,
    token: str = Query(..., description="JWT authentication token")
):
    # The session lives exactly as long as the authentication query. Holding it
    # for the life of the socket - as this did - kept a pooled connection and an
    # open transaction per signed-in user, so the pool ran out long before the
    # server did. See `session_scope`.
    with session_scope() as db:
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
        pass
    finally:
        # In `finally`, not just on WebSocketDisconnect: any other error left
        # the socket registered in the manager, and every later notification
        # tried to write to it.
        manager.disconnect(user_id_str, websocket)

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
            await run_in_threadpool(
                send_fcm_push,
                user_obj.fcm_token,
                payload.title,
                payload.message,
                {"type": "system", "id": str(db_noti.id)},
                unread_count(db, db_noti.user_id),
            )

    return {"status": "success", "message": f"Notification broadcasted to {len(users)} users"}


@router.post("/send-direct")
async def send_direct_notification(
    payload: schemas.NotificationDirectSend,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"]))
):
    """Send a direct push notification to a specific user by user_id or phone_number."""
    user = None
    if payload.user_id:
        user = db.query(models.User).filter(models.User.id == payload.user_id).first()
    elif payload.phone_number:
        target_norm = auth.normalize_phone_digits(payload.phone_number)
        users = db.query(models.User).all()
        for u in users:
            if u.phone_number and auth.normalize_phone_digits(u.phone_number) == target_norm:
                user = u
                break

    if not user:
        raise HTTPException(status_code=404, detail="User not found.")

    await create_and_send_notification(
        db=db,
        user_id=user.id,
        title=payload.title,
        message=payload.message,
        noti_type="system"
    )
    return {"status": "success", "message": f"Notification sent to {user.full_name}"}


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
