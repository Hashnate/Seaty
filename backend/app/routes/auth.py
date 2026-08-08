from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
import uuid

from app.database import get_db
from app import models, schemas, auth
from app.config import settings

router = APIRouter(prefix="/auth", tags=["Authentication"])

@router.post("/register", response_model=schemas.UserResponse, status_code=status.HTTP_201_CREATED)
def register(user_in: schemas.UserRegister, db: Session = Depends(get_db)):
    # Check if user already exists
    existing_user = db.query(models.User).filter(models.User.email == user_in.email).first()
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A user with this email is already registered."
        )

    # Create new user
    db_user = models.User(
        id=uuid.uuid4(),
        email=user_in.email,
        hashed_password=auth.get_password_hash(user_in.password),
        full_name=user_in.full_name,
        phone_number=user_in.phone_number,
        role=user_in.role,
        company_id=user_in.company_id
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user

@router.post("/login", response_model=schemas.Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    # Authenticate user
    user = db.query(models.User).filter(models.User.email == form_data.username).first()
    if not user or not auth.verify_password(form_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Generate JWT
    access_token = auth.create_access_token(
        data={"sub": user.email, "role": user.role}
    )
    return {"access_token": access_token, "token_type": "bearer"}

@router.get("/me", response_model=schemas.UserResponse)
def get_current_user_profile(current_user: models.User = Depends(auth.get_current_user)):
    return current_user

import random
import time
from app.services.sms_service import send_sms

# In-memory OTP store: normalized_phone -> {"code": str, "expires_at": float, "verified": bool}
otp_store = {}

def normalize_phone_digits(raw: str) -> str:
    if not raw:
        return ""
    digits = "".join(c for c in raw if c.isdigit())
    return digits[-9:] if len(digits) >= 9 else digits

@router.post("/otp/send", response_model=schemas.SendOTPResponse)
def send_otp(payload: schemas.SendOTPRequest, db: Session = Depends(get_db)):
    target_norm = normalize_phone_digits(payload.phone_number)
    if not target_norm:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid mobile number provided."
        )

    is_dev = settings.ENVIRONMENT.lower() in ["dev", "development"]
    is_test_phone = target_norm in [
        normalize_phone_digits("0771234567"),
        normalize_phone_digits("+94771234567"),
        normalize_phone_digits("0777140803"),
        normalize_phone_digits("+94777140803"),
    ]
    # Generate dynamic 6-digit OTP code (or 123456 in dev mode or for test accounts)
    otp_code = "123456" if (is_dev or is_test_phone) else str(random.randint(100000, 999999))
    expires_at = time.time() + 300  # Valid for 5 minutes

    otp_store[target_norm] = {
        "code": otp_code,
        "expires_at": expires_at,
        "verified": False
    }

    message = f"Your Seaty verification code is {otp_code}. Valid for 5 minutes."
    send_sms(payload.phone_number, message)

    res = {
        "success": True,
        "message": f"Verification code sent via SMS to {payload.phone_number}",
        "phone_number": payload.phone_number,
    }
    # Return otp_code only in development environment or for test accounts
    if is_dev or is_test_phone:
        res["otp_code"] = otp_code
    else:
        res["otp_code"] = None

    return res

@router.post("/otp/verify", response_model=schemas.VerifyOTPResponse)
def verify_otp(payload: schemas.VerifyOTPRequest):
    target_norm = normalize_phone_digits(payload.phone_number)
    is_dev = settings.ENVIRONMENT.lower() in ["dev", "development"]
    is_test_phone = target_norm in [
        normalize_phone_digits("0771234567"),
        normalize_phone_digits("+94771234567"),
        normalize_phone_digits("0777140803"),
        normalize_phone_digits("+94777140803"),
    ]

    # Auto-approve if code is '123456' or 'AUTO' for test accounts or dev environment
    if payload.otp_code.strip() in ["123456", "AUTO"] and (is_dev or is_test_phone):
        if target_norm in otp_store:
            otp_store[target_norm]["verified"] = True
        return {
            "success": True,
            "message": "OTP verification successful."
        }

    entry = otp_store.get(target_norm)
    if not entry or time.time() > entry["expires_at"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="OTP code has expired or was not requested. Please request a new code."
        )

    if entry["code"] != payload.otp_code.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid verification code. Please check your SMS and try again."
        )

    entry["verified"] = True
    return {
        "success": True,
        "message": "OTP verification successful."
    }

@router.post("/phone/check", response_model=schemas.PhoneCheckResponse)
def check_phone(payload: schemas.PhoneCheckRequest, db: Session = Depends(get_db)):
    target_norm = normalize_phone_digits(payload.phone_number)
    users = db.query(models.User).all()
    
    matching_user = None
    roles = ["owner", "conductor"] if payload.role in ["owner", "conductor"] else [payload.role]
    
    # 1. Try matching target phone + role group first
    for u in users:
        if u.phone_number and normalize_phone_digits(u.phone_number) == target_norm:
            if u.role in roles:
                matching_user = u
                break
                
    # 2. Fallback to any user matching target phone (auto-detect role)
    if not matching_user:
        for u in users:
            if u.phone_number and normalize_phone_digits(u.phone_number) == target_norm:
                matching_user = u
                break

    if matching_user:
        return {"exists": True, "name": matching_user.full_name, "role": matching_user.role}
    return {"exists": False}

@router.post("/phone/register", response_model=schemas.UserResponse, status_code=status.HTTP_201_CREATED)
def register_phone(payload: schemas.PhoneRegisterRequest, db: Session = Depends(get_db)):
    email = f"{payload.phone_number}@seaty.lk"
    target_norm = normalize_phone_digits(payload.phone_number)
    
    # OTP Validation check if OTP code provided
    if payload.otp_code:
        entry = otp_store.get(target_norm)
        if not entry or time.time() > entry["expires_at"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="OTP code has expired or was not requested."
            )
        if entry["code"] != payload.otp_code.strip():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid OTP verification code."
            )
        # Clear used OTP
        otp_store.pop(target_norm, None)

    users = db.query(models.User).all()
    for u in users:
        if u.phone_number and normalize_phone_digits(u.phone_number) == target_norm and u.role == payload.role:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="A user with this mobile number is already registered under this role."
            )

    existing_email = db.query(models.User).filter(models.User.email == email).first()
    if existing_email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email identifier already registered."
        )

    db_user = models.User(
        id=uuid.uuid4(),
        email=email,
        hashed_password=auth.get_password_hash("seaty_phone_auth_dummy_pass"),
        full_name=payload.full_name,
        phone_number=payload.phone_number,
        role=payload.role
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user

@router.post("/phone/login", response_model=schemas.Token)
def login_phone(payload: schemas.PhoneCheckRequest, db: Session = Depends(get_db)):
    target_norm = normalize_phone_digits(payload.phone_number)
    users = db.query(models.User).all()
    
    matching_user = None
    roles = ["owner", "conductor"] if payload.role in ["owner", "conductor"] else [payload.role]
    
    for u in users:
        if u.phone_number and normalize_phone_digits(u.phone_number) == target_norm:
            if u.role in roles:
                matching_user = u
                break
                
    if not matching_user:
        for u in users:
            if u.phone_number and normalize_phone_digits(u.phone_number) == target_norm:
                matching_user = u
                break

    if not matching_user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found."
        )

    access_token = auth.create_access_token(
        data={"sub": matching_user.email, "role": matching_user.role}
    )
    return {"access_token": access_token, "token_type": "bearer", "role": matching_user.role}

@router.put("/profile", response_model=schemas.UserResponse)
def update_profile(
    payload: schemas.ProfileUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    if payload.full_name is not None:
        current_user.full_name = payload.full_name
    if payload.nic_number is not None:
        current_user.nic_number = payload.nic_number
    if payload.gender is not None:
        current_user.gender = payload.gender
    if payload.phone_number is not None:
        existing = db.query(models.User).filter(
            models.User.phone_number == payload.phone_number,
            models.User.role == current_user.role,
            models.User.id != current_user.id
        ).first()
        if existing:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="A user with this mobile number is already registered under this role."
            )
        current_user.phone_number = payload.phone_number

    db.commit()
    db.refresh(current_user)
    return current_user

@router.post("/change-password", status_code=status.HTTP_200_OK)
def change_password(
    payload: schemas.PasswordChangeRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    # Verify current password
    if not auth.verify_password(payload.current_password, current_user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Incorrect current password."
        )
    # Hash and save new password
    current_user.hashed_password = auth.get_password_hash(payload.new_password)
    db.commit()
    return {"message": "Password changed successfully."}


@router.api_route("/fcm-token", methods=["POST", "PUT"])
@router.api_route("/me/fcm-token", methods=["POST", "PUT"])
def update_fcm_token_auth_alias(
    payload: schemas.FCMTokenUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    """Compatibility alias endpoint for FCM device token registration under /auth."""
    old_token = current_user.fcm_token
    current_user.fcm_token = payload.fcm_token
    db.commit()
    print(f"FCM token updated via auth endpoint alias for user {current_user.id} ({current_user.full_name}): "
          f"had_previous={'yes' if old_token else 'no'}, new_token={payload.fcm_token[:20]}...")
    return {"status": "success", "message": "FCM token updated successfully"}

