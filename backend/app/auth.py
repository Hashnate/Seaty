from datetime import datetime, timedelta
from typing import Optional, List
from jose import JWTError, jwt
from passlib.context import CryptContext
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from uuid import UUID

import bcrypt
import secrets
from app.config import settings
from app.database import get_db
from app import models, schemas

# Setup oauth2 scheme
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="api/v1/auth/login")

# Roles permitted to use the email + password path (POST /auth/login), i.e. the
# admin console. Passengers and conductors authenticate by phone + OTP in the
# mobile app; owners use both. Enforced in routes/auth.py:login - the console's
# own role guards are UI only and stop nothing at the API.
PASSWORD_LOGIN_ROLES = ("admin", "owner")

def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))
    except Exception:
        return False

def get_password_hash(password: str) -> str:
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')

def unusable_password_hash() -> str:
    """Hash of a random secret that is discarded immediately.

    OTP-only accounts still need a non-null `hashed_password`. This used to be a
    shared string literal, which made that literal a working credential for
    every phone account through POST /auth/login - the email is derivable from
    the phone number, so knowing a number was enough to sign in as that user.
    Randomising it makes the password path structurally unusable for these
    accounts rather than relying on the role check alone.
    """
    return get_password_hash(secrets.token_urlsafe(32))

def token_version_matches(payload: dict, user: "models.User") -> bool:
    """Is this token from the user's current session generation?

    Tokens minted before `token_version` existed carry no `tv` claim; those are
    treated as version 1, so introducing this does not sign everyone out. Once a
    user logs out their version moves past 1 and those old tokens stop matching.
    """
    return int(payload.get("tv", 1)) == int(getattr(user, "token_version", 1) or 1)


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    return encoded_jwt

def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> models.User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
        token_data = schemas.TokenData(username=username, role=payload.get("role"))
    except JWTError:
        raise credentials_exception

    user = db.query(models.User).filter(models.User.email == token_data.username).first()
    if user is None:
        raise credentials_exception

    # Signed out since this token was issued.
    if not token_version_matches(payload, user):
        raise credentials_exception

    return user

oauth2_scheme_optional = OAuth2PasswordBearer(tokenUrl="api/v1/auth/login", auto_error=False)

def get_optional_current_user(token: Optional[str] = Depends(oauth2_scheme_optional), db: Session = Depends(get_db)) -> Optional[models.User]:
    if not token:
        return None
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            return None
        user = db.query(models.User).filter(models.User.email == username).first()
        if user is not None and not token_version_matches(payload, user):
            return None
        return user
    except JWTError:
        return None

class RoleChecker:
    def __init__(self, allowed_roles: List[str]):
        self.allowed_roles = allowed_roles

    def __call__(self, current_user: models.User = Depends(get_current_user)) -> models.User:
        if current_user.role not in self.allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"The role '{current_user.role}' is not authorized to access this resource. Allowed: {self.allowed_roles}"
            )
        return current_user
