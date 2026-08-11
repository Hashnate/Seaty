import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    PROJECT_NAME: str = "Seaty Luxury Transport API"
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")

    # No defaults, deliberately. These used to fall back to a committed database
    # password and a committed signing key, so a missing or unparseable .env
    # started the app with a publicly known SECRET_KEY and nothing said so -
    # every token forgeable, silently. Absent config must stop the process, not
    # degrade it (docs/SECURITY.md #5).
    DATABASE_URL: str
    SECRET_KEY: str

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

    # ── Payments ──────────────────────────────────────────────────────────
    # PAYMENT_MODE: off | mock | live. Defaults to off so a deployment never
    # starts taking payments by accident. There is no "test" - Bancstac issues
    # a single live-only credential set for this merchant, so `mock` (local, no
    # network) is what stands in for a sandbox. See docs/PAYMENTS.md.
    PAYMENT_PROVIDER: str = os.getenv("PAYMENT_PROVIDER", "bancstac")
    PAYMENT_MODE: str = os.getenv("PAYMENT_MODE", "off")

    BANCSTAC_ENDPOINT: str = os.getenv("BANCSTAC_ENDPOINT", "")
    BANCSTAC_CLIENT_ID: str = os.getenv("BANCSTAC_CLIENT_ID", "")
    BANCSTAC_AUTH_TOKEN: str = os.getenv("BANCSTAC_AUTH_TOKEN", "")
    BANCSTAC_HMAC_SECRET: str = os.getenv("BANCSTAC_HMAC_SECRET", "")
    # Bancstac redirects the payer's browser here with ?reqid=. Must be
    # publicly reachable - the gateway, not our client, performs the redirect.
    BANCSTAC_RETURN_URL: str = os.getenv("BANCSTAC_RETURN_URL", "")
    BANCSTAC_CANCEL_URL: str = os.getenv("BANCSTAC_CANCEL_URL", "")

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
