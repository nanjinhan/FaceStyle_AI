import uuid
from pathlib import Path

from fastapi import UploadFile

from .config import settings

ALLOWED_EXT = {".jpg", ".jpeg", ".png", ".heic"}


def save_photo(session_id: str, file: UploadFile) -> tuple[str, int]:
    ext = Path(file.filename or "").suffix.lower()
    if ext not in ALLOWED_EXT:
        raise ValueError(f"unsupported file type: {ext or 'unknown'}")

    dest_dir = settings.storage_dir / "sessions" / session_id
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest_path = dest_dir / f"{uuid.uuid4().hex}{ext}"

    max_bytes = settings.max_upload_mb * 1024 * 1024
    size = 0
    with dest_path.open("wb") as out:
        while chunk := file.file.read(1024 * 1024):
            size += len(chunk)
            if size > max_bytes:
                out.close()
                dest_path.unlink(missing_ok=True)
                raise ValueError(f"file exceeds {settings.max_upload_mb}MB limit")
            out.write(chunk)

    return f"/media/sessions/{session_id}/{dest_path.name}", size
