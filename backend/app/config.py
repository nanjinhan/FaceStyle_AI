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

    # 명세 3장 실시간 방: 인원 제한 6명(렉 방지), 24시간 후 자동 만료(서버 부담·프라이버시)
    max_members: int = 6
    session_expire_hours: int = 24

    # 방 하나에 올릴 수 있는 사진 수 (명세 3장 "여러 장 업로드 후 컷 선택")
    max_photos_per_session: int = 20


settings = Settings()
settings.storage_dir.mkdir(parents=True, exist_ok=True)
