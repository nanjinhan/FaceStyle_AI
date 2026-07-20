from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, ConfigDict


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    nickname: str
    profile_image: Optional[str] = None


class SocialLoginRequest(BaseModel):
    provider: str  # kakao | apple | google
    provider_id: str
    nickname: str
    profile_image: Optional[str] = None


class AuthResponse(BaseModel):
    access_token: str
    user: UserOut


class FaceOut(BaseModel):
    id: str
    faceIndex: int
    bbox: list[int]
    claimedByMemberId: Optional[str] = None


class PhotoOut(BaseModel):
    id: str
    url: str
    width: int
    height: int
    faces: list[FaceOut]
    editState: dict[str, Any]
    # 완료 확정 현황 — completedBy ⊇ requiredBy 가 되면 서버가 자동 확정한다
    completedBy: list[str] = []
    requiredBy: list[str] = []
    finalized: bool = False


class MemberOut(BaseModel):
    id: str
    nickname: str
    role: str
    connected: bool


class SessionDetail(BaseModel):
    id: str
    status: str
    inviteToken: str
    inviteCode: str
    maxMembers: int
    expiresAt: datetime
    globalEditPolicy: str  # host_only | everyone — 공용 영역 편집 권한
    members: list[MemberOut]
    photos: list[PhotoOut]


class JoinRequest(BaseModel):
    invite: str  # invite_token 또는 invite_code
    nickname: Optional[str] = None


class JoinResponse(BaseModel):
    memberToken: str
    session: SessionDetail


class ExportOut(BaseModel):
    id: str
    photoId: str
    url: str
    createdAt: datetime
