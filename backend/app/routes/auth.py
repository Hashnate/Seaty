from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
import uuid

from app.database import get_db
from app import models, schemas, auth
from app.config import settings

router = APIRouter(prefix="/auth", tags=["Authentication"])

@router.post("/register", response_model=schemas.UserResponse, status_code=status.HTTP_201_CREATED)
def register(
    user_in: schemas.UserRegister,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.RoleChecker(["admin"])),
):
    """Create an operator (owner) account. Admin only.

    Account creation is deliberately one-directional:

        admin    -> created out of band only (backend/create_admin.py)
        owner    -> created here, by an admin
        conductor-> created by their owner (POST /conductors)
        passenger-> self-service, phone + OTP (POST /auth/phone/register)

    Nothing in the API can create an admin. See docs/SECURITY.md #2.
    """
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
    """Email + password sign-in for the admin console.

    Restricted to the roles in `auth.PASSWORD_LOGIN_ROLES`. Passengers and
    conductors are phone + OTP only and must not be able to reach the API
    through a password, whichever client is calling.
    """
    user = db.query(models.User).filter(models.User.email == form_data.username).first()

    # Evaluated before either is acted on, and a disallowed role returns the
    # same 401 as a wrong password. A distinct error here would confirm which
    # phone numbers exist and what role they hold.
    password_ok = user is not None and auth.verify_password(
        form_data.password, user.hashed_password
    )
    role_ok = user is not None and user.role in auth.PASSWORD_LOGIN_ROLES

    if not (password_ok and role_ok):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Generate JWT
    access_token = auth.create_access_token(
        data={"sub": user.email, "role": user.role, "tv": user.token_version or 1}
    )
    return {"access_token": access_token, "token_type": "bearer"}

@router.get("/me", response_model=schemas.UserResponse)
def get_current_user_profile(current_user: models.User = Depends(auth.get_current_user)):
    return current_user

import random
import secrets
import time
from app.services.sms_service import send_sms

# In-memory OTP store:
#   normalized_phone -> {"code": str, "expires_at": float, "attempts": int}
# Module-level, so it is lost on restart and not shared between processes - the
# backend must stay single-process (see docs/DEPLOYMENT.md#capacity-and-scaling).
otp_store = {}

# normalized_phone -> [timestamps of recent sends], for send-rate limiting.
otp_send_log = {}

OTP_TTL_SECONDS = 300           # 5 minutes
MAX_VERIFY_ATTEMPTS = 5         # per issued code, then it is burned
RESEND_COOLDOWN_SECONDS = 60    # minimum gap between codes for one number
MAX_SENDS_PER_WINDOW = 5
SEND_WINDOW_SECONDS = 3600


def normalize_phone_digits(raw: str) -> str:
    if not raw:
        return ""
    digits = "".join(c for c in raw if c.isdigit())
    return digits[-9:] if len(digits) >= 9 else digits


def _test_otp_accounts() -> dict:
    """Fixed-code accounts, parsed from the TEST_OTP_ACCOUNTS setting.

    App Store and Play reviewers cannot receive our SMS, so they need a number
    whose code never changes. These are real credentials: they live in the
    environment, never in source, and should be removed once review is done.
    Format: "0771234567:123456,0777140803:123456".
    """
    accounts = {}
    for pair in (settings.TEST_OTP_ACCOUNTS or "").split(","):
        pair = pair.strip()
        if not pair or ":" not in pair:
            continue
        phone, code = pair.split(":", 1)
        norm, code = normalize_phone_digits(phone), code.strip()
        if norm and code:
            accounts[norm] = code
    return accounts


def _prune_otp_state(now: float) -> None:
    """Drop expired codes and stale send history so the dicts stay bounded."""
    for phone in [p for p, e in otp_store.items() if now > e["expires_at"]]:
        otp_store.pop(phone, None)
    for phone in list(otp_send_log):
        recent = [t for t in otp_send_log[phone] if now - t < SEND_WINDOW_SECONDS]
        if recent:
            otp_send_log[phone] = recent
        else:
            otp_send_log.pop(phone, None)


def _enforce_send_rate(norm: str, now: float) -> None:
    """Cap how often a code can be requested for one number.

    Without this, /auth/otp/send is an open tap on the Notify.lk balance and a
    way to flood someone's phone.
    """
    sends = otp_send_log.get(norm, [])
    if sends and now - sends[-1] < RESEND_COOLDOWN_SECONDS:
        wait = int(RESEND_COOLDOWN_SECONDS - (now - sends[-1])) + 1
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Please wait {wait} seconds before requesting another code.",
        )
    if len(sends) >= MAX_SENDS_PER_WINDOW:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many verification codes requested. Please try again later.",
        )


def _verify_otp_code(norm: str, submitted: str, consume: bool) -> None:
    """Check a submitted OTP for a phone number, raising on any failure.

    `consume=True` deletes the code on success, making it single-use. Login
    consumes; the interactive /otp/verify check does not, so the client can give
    immediate feedback and still complete the login with the same code.

    Fixed-code review accounts never consume - a reviewer may sign in repeatedly.
    """
    submitted = (submitted or "").strip()
    if not submitted:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Verification code is required.",
        )

    fixed = _test_otp_accounts().get(norm)
    if fixed is not None:
        if not secrets.compare_digest(submitted, fixed):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid verification code. Please check your SMS and try again.",
            )
        # Mark the stored entry verified so the two-request compatibility path
        # works for review accounts too, but never consume it - a reviewer
        # signs in repeatedly with the same fixed code.
        entry = otp_store.get(norm)
        if entry:
            entry["verified"] = True
        return

    entry = otp_store.get(norm)
    if not entry or time.time() > entry["expires_at"]:
        otp_store.pop(norm, None)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="OTP code has expired or was not requested. Please request a new code.",
        )

    entry["attempts"] += 1
    if entry["attempts"] > MAX_VERIFY_ATTEMPTS:
        # Burn the code rather than let a 6-digit space be walked at leisure.
        otp_store.pop(norm, None)
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many incorrect attempts. Please request a new code.",
        )

    if not secrets.compare_digest(entry["code"], submitted):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid verification code. Please check your SMS and try again.",
        )

    if consume:
        otp_store.pop(norm, None)
    else:
        # Record that this number cleared verification. Read by
        # _consume_verified_otp for clients that verify and sign in as two
        # separate requests.
        entry["verified"] = True


def _consume_verified_otp(norm: str) -> None:
    """Accept a sign-in whose OTP was proven by a prior /auth/otp/verify call.

    Compatibility path for app builds that predate `otp_code` on
    /auth/phone/login. Those clients verify the code and then sign in as two
    requests, so the code itself never reaches this endpoint.

    This is weaker than sending the code - the proof is split across two
    requests, held in server memory - but it is not the original hole: the
    client cannot set `verified`, only a correct code can, and it is consumed
    here so it works exactly once. An attacker who skips /auth/otp/verify still
    gets nothing.

    Remove once the build that sends `otp_code` is everywhere; see
    docs/SECURITY.md #1.
    """
    entry = otp_store.get(norm)
    if not entry or time.time() > entry["expires_at"] or not entry.get("verified"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Please verify your mobile number before signing in.",
        )
    # Review accounts keep their entry: a reviewer signs in more than once.
    if norm not in _test_otp_accounts():
        otp_store.pop(norm, None)

@router.post("/otp/send", response_model=schemas.SendOTPResponse)
def send_otp(payload: schemas.SendOTPRequest, db: Session = Depends(get_db)):
    target_norm = normalize_phone_digits(payload.phone_number)
    if not target_norm:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid mobile number provided."
        )

    now = time.time()
    _prune_otp_state(now)

    # Review accounts have a fixed code the reviewer already holds. Nothing to
    # generate, nothing to send - and crucially the code is not echoed back, or
    # the "credential" would be self-service for anyone who knows the number.
    fixed_code = _test_otp_accounts().get(target_norm)
    if fixed_code is not None:
        # An entry is stored so /auth/otp/verify behaves identically for review
        # accounts, which the two-request compatibility path depends on. No SMS
        # is sent and the code is never echoed - the reviewer already has it.
        otp_store[target_norm] = {
            "code": fixed_code,
            "expires_at": now + OTP_TTL_SECONDS,
            "attempts": 0,
        }
        return {
            "success": True,
            "message": f"Verification code sent via SMS to {payload.phone_number}",
            "phone_number": payload.phone_number,
            "otp_code": None,
        }

    _enforce_send_rate(target_norm, now)

    is_dev = settings.ENVIRONMENT.lower() in ["dev", "development"]
    otp_code = "123456" if is_dev else f"{secrets.randbelow(1000000):06d}"

    otp_store[target_norm] = {
        "code": otp_code,
        "expires_at": now + OTP_TTL_SECONDS,
        "attempts": 0,
    }
    otp_send_log.setdefault(target_norm, []).append(now)

    message = f"Your Seaty verification code is {otp_code}. Valid for 5 minutes."
    sent, detail = send_sms(payload.phone_number, message)

    if not sent and not is_dev:
        # The gateway's verdict used to be discarded and this always reported
        # success, so a rejected SMS left the user waiting for a code that was
        # never coming. The code stays in the store so a resend can still use
        # it, but the client is told the truth.
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="We could not send the verification code right now. Please try again.",
        )

    return {
        "success": True,
        "message": f"Verification code sent via SMS to {payload.phone_number}",
        "phone_number": payload.phone_number,
        # Echoed only in development, where there is no real SMS to read.
        "otp_code": otp_code if is_dev else None,
    }

@router.post("/otp/verify", response_model=schemas.VerifyOTPResponse)
def verify_otp(payload: schemas.VerifyOTPRequest):
    """Interactive check so the client can flag a wrong code immediately.

    Deliberately does **not** consume the code - the client calls this and then
    completes sign-in with the same code, which is where it is consumed. This
    endpoint is not an authorisation step on its own; nothing downstream trusts
    the fact that it was called. Attempts still count towards the per-code cap.
    """
    target_norm = normalize_phone_digits(payload.phone_number)
    _verify_otp_code(target_norm, payload.otp_code, consume=False)
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

    # Unconditional. This used to be `if payload.otp_code:`, so omitting the
    # field entirely skipped verification and let anyone register an account
    # against a number they did not control - see docs/SECURITY.md #4.
    # Not consumed here: the client registers and then immediately signs in with
    # the same code, and it is sign-in that burns it.
    _verify_otp_code(target_norm, payload.otp_code, consume=False)

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
        hashed_password=auth.unusable_password_hash(),
        full_name=payload.full_name,
        phone_number=payload.phone_number,
        role=payload.role
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user

@router.post("/phone/login", response_model=schemas.Token)
def login_phone(payload: schemas.PhoneLoginRequest, db: Session = Depends(get_db)):
    """Phone + OTP sign-in for the mobile app.

    The OTP is verified **here**, server-side, and consumed on success. It used
    to be checked only by a separate /otp/verify call whose result was written
    to a flag nothing ever read - so a client that skipped that call got a token
    for any phone number. See docs/SECURITY.md #1.
    """
    target_norm = normalize_phone_digits(payload.phone_number)

    # Before the user lookup, so a wrong code cannot be used to probe which
    # numbers exist (the lookup 404s on an unknown number).
    if payload.otp_code:
        _verify_otp_code(target_norm, payload.otp_code, consume=True)
    else:
        # Older app builds verify and sign in as two requests. See
        # _consume_verified_otp - still requires a real OTP, just proven earlier.
        _consume_verified_otp(target_norm)

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
        data={"sub": matching_user.email, "role": matching_user.role,
              "tv": matching_user.token_version or 1}
    )
    return {"access_token": access_token, "token_type": "bearer", "role": matching_user.role}

@router.post("/logout", status_code=status.HTTP_200_OK)
def logout(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    """Invalidate every token issued to the caller.

    Signing out used to be purely local: the device forgot the token, but the
    token itself stayed valid until it expired - up to 7 days. A device whose
    local state did not survive (an iOS force-close can lose an unflushed
    UserDefaults write) came back signed in, and a captured token kept working.

    Bumping token_version kills them all, so sign-out no longer depends on the
    client succeeding at anything. It signs the user out on every device, which
    is the right default for a phone-and-OTP account.
    """
    current_user.token_version = (current_user.token_version or 1) + 1
    db.commit()
    return {"status": "success", "message": "Signed out on all devices."}


@router.put("/profile", response_model=schemas.UserResponse)
def update_profile(
    payload: schemas.ProfileUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    if payload.full_name is not None:
        current_user.full_name = payload.full_name
    if payload.nic_number is not None:
        nic_val = payload.nic_number.strip().upper()
        if nic_val:
            import re
            if not re.match(r"^(\d{9}[VX]|\d{12})$", nic_val):
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid NIC format. Must be 12 digits or 9 digits followed by V/X."
                )
            current_user.nic_number = nic_val
        else:
            current_user.nic_number = ""
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

