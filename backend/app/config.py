import os
from pathlib import Path


class Settings:
    database_url: str = os.getenv("DATABASE_URL", "sqlite:///./togethersnap.db")

    jwt_secret: str = os.getenv("JWT_SECRET", "dev-secret-change-me")
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 7
    member_token_expire_hours: int = 72

    storage_dir: Path = Path(os.getenv("STORAGE_DIR", "./storage")).resolve()
    max_upload_mb: int = 20

    max_members_mvp: int = 4
    session_expire_hours: int = 72


settings = Settings()
settings.storage_dir.mkdir(parents=True, exist_ok=True)
