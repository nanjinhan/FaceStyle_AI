import time
from typing import Optional

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from . import models
from .config import settings
from .database import get_db

bearer_scheme = HTTPBearer(auto_error=False)


def _encode(payload: dict, expire_seconds: int) -> str:
    payload = {**payload, "exp": int(time.time()) + expire_seconds}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def create_user_token(user_id: str) -> str:
    return _encode({"typ": "user", "sub": user_id}, settings.access_token_expire_minutes * 60)


def create_member_token(member_id: str, session_id: str) -> str:
    return _encode(
        {"typ": "member", "sub": member_id, "session_id": session_id},
        settings.member_token_expire_hours * 3600,
    )


def decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except jwt.PyJWTError as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid or expired token") from exc


def get_current_user(
    creds: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> models.User:
    if creds is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "missing token")
    payload = decode_token(creds.credentials)
    if payload.get("typ") != "user":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "user token required")
    user = db.get(models.User, payload["sub"])
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "user not found")
    return user


def get_optional_user(
    creds: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> Optional[models.User]:
    if creds is None:
        return None
    try:
        payload = decode_token(creds.credentials)
    except HTTPException:
        return None
    if payload.get("typ") != "user":
        return None
    return db.get(models.User, payload["sub"])


def get_current_member(
    creds: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> models.Member:
    if creds is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "missing token")
    payload = decode_token(creds.credentials)
    if payload.get("typ") != "member":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "member token required")
    member = db.get(models.Member, payload["sub"])
    if member is None or member.left_at is not None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "member not found")
    return member
