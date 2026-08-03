import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    PROJECT_NAME: str = "Seaty Luxury Transport API"
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
    DATABASE_URL: str = os.getenv("DATABASE_URL", "postgresql://postgres:seaty_secure_password_987@db:5432/seaty")
    SECRET_KEY: str = os.getenv("SECRET_KEY", "SUPER_SECRET_KEY_SEATY_1234567890_CHANGEME_IN_PRODUCTION")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440  # 24 Hours

    # Notify.lk SMS Gateway Settings - loaded from .env / environment variables
    NOTIFYLK_USER_ID: str = os.getenv("NOTIFYLK_USER_ID", "")
    NOTIFYLK_API_KEY: str = os.getenv("NOTIFYLK_API_KEY", "")
    NOTIFYLK_SENDER_ID: str = os.getenv("NOTIFYLK_SENDER_ID", "NotifyDEMO")
    NOTIFYLK_API_URL: str = os.getenv("NOTIFYLK_API_URL", "https://app.notify.lk/api/v1/send")

    class Config:
        case_sensitive = True
        env_file = ".env"
        extra = "ignore"

settings = Settings()
