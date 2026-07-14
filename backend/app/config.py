import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    PROJECT_NAME: str = "Seaty Luxury Transport API"
    DATABASE_URL: str = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/seaty")
    SECRET_KEY: str = os.getenv("SECRET_KEY", "SUPER_SECRET_KEY_SEATY_1234567890_CHANGEME_IN_PRODUCTION")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440  # 24 Hours

    class Config:
        case_sensitive = True
        env_file = ".env"

settings = Settings()
