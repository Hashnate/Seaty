import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    PROJECT_NAME: str = "Seaty Luxury Transport API"
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
    DATABASE_URL: str = os.getenv("DATABASE_URL", "postgresql://postgres:seaty_secure_password_987@db:5432/seaty")
    SECRET_KEY: str = os.getenv("SECRET_KEY", "SUPER_SECRET_KEY_SEATY_1234567890_CHANGEME_IN_PRODUCTION")
    ALGORITHM: str = "HS256"
    # 7 days. Raised from 24 h because every re-login costs a real SMS: with no
    # refresh token, expiry is the only thing forcing one, so a 1-day life meant
    # roughly one OTP per active user per day.
    #
    # The trade-off is that a leaked token now stays valid for a week. There is
    # no revocation list and logout only clears the client, so nothing can cut a
    # session short before this expires. Overridable per environment.
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 10080

    # Fixed-OTP accounts for App Store / Play review, whose reviewers cannot
    # receive our SMS. Format: "0771234567:123456,0777140803:123456".
    # These are live credentials - they belong in .env, never in source, and
    # should be emptied once review is complete. Point them at throwaway
    # passenger accounts only.
    TEST_OTP_ACCOUNTS: str = os.getenv("TEST_OTP_ACCOUNTS", "")

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
