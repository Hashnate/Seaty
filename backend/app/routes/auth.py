from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
import uuid

from app.database import get_db
from app import models, schemas, auth

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

@router.post("/phone/check", response_model=schemas.PhoneCheckResponse)
def check_phone(payload: schemas.PhoneCheckRequest, db: Session = Depends(get_db)):
    roles = ["owner", "conductor"] if payload.role in ["owner", "conductor"] else [payload.role]
    user = db.query(models.User).filter(
        models.User.phone_number == payload.phone_number,
        models.User.role.in_(roles)
    ).first()
    if user:
        return {"exists": True, "name": user.full_name}
    return {"exists": False}

@router.post("/phone/register", response_model=schemas.UserResponse, status_code=status.HTTP_201_CREATED)
def register_phone(payload: schemas.PhoneRegisterRequest, db: Session = Depends(get_db)):
    email = f"{payload.phone_number}@seaty.lk"
    
    existing_user = db.query(models.User).filter(
        models.User.phone_number == payload.phone_number,
        models.User.role == payload.role
    ).first()
    if existing_user:
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
    roles = ["owner", "conductor"] if payload.role in ["owner", "conductor"] else [payload.role]
    user = db.query(models.User).filter(
        models.User.phone_number == payload.phone_number,
        models.User.role.in_(roles)
    ).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found."
        )

    access_token = auth.create_access_token(
        data={"sub": user.email, "role": user.role}
    )
    return {"access_token": access_token, "token_type": "bearer"}

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

