import random
import string
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from .. import models, schemas, security, storage
from ..collab.manager import connection_manager
from ..collab.state import edit_state_store
from ..config import settings
from ..database import get_db
from ..face_detection import detect_faces

router = APIRouter(prefix="/sessions", tags=["sessions"])


def _gen_invite_code() -> str:
    return "".join(random.choices(string.ascii_uppercase + string.digits, k=6))


def _get_session_or_404(db: Session, session_id: str) -> models.EditSession:
    session = db.get(models.EditSession, session_id)
    if session is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "session not found")
    return session


def _require_membership(session_id: str, member: models.Member) -> None:
    if member.session_id != session_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "not a member of this session")


def _session_to_detail(db: Session, session: models.EditSession) -> schemas.SessionDetail:
    photos = []
    for photo in session.photos:
        state = edit_state_store.get(db, photo.id)
        photos.append(schemas.PhotoOut(
            id=photo.id, url=photo.url, width=photo.width, height=photo.height,
            faces=[
                schemas.FaceOut(
                    id=f.id, faceIndex=f.face_index,
                    bbox=[f.bbox_x, f.bbox_y, f.bbox_w, f.bbox_h],
                    claimedByMemberId=f.claimed_by_member_id,
                )
                for f in photo.faces
            ],
            editState=state.as_dict(),
        ))
    return schemas.SessionDetail(
        id=session.id,
        status=session.status,
        inviteToken=session.invite_token,
        inviteCode=session.invite_code,
        maxMembers=session.max_members,
        expiresAt=session.expires_at,
        members=[
            schemas.MemberOut(id=m.id, nickname=m.nickname, role=m.role, connected=m.connected)
            for m in session.members
            if m.left_at is None
        ],
        photos=photos,
    )


@router.post("", response_model=schemas.SessionDetail, status_code=status.HTTP_201_CREATED)
def create_session(
    file: UploadFile = File(...),
    current_user: models.User = Depends(security.get_current_user),
    db: Session = Depends(get_db),
):
    """사진 업로드(SES-01) + 세션 자동 생성(SES-02, MVP는 세션당 사진 1장)."""
    now = datetime.utcnow()
    session = models.EditSession(
        host_user_id=current_user.id,
        invite_code=_gen_invite_code(),
        max_members=settings.max_members_mvp,
        expires_at=now + timedelta(hours=settings.session_expire_hours),
    )
    db.add(session)
    db.flush()

    try:
        url, _size = storage.save_photo(session.id, file)
    except ValueError as exc:
        db.rollback()
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(exc)) from exc

    photo = models.Photo(session_id=session.id, url=url, order_index=0)
    db.add(photo)
    db.flush()

    image_path = settings.storage_dir / url.removeprefix("/media/")
    for idx, (x, y, w, h) in enumerate(detect_faces(image_path)):
        db.add(models.Face(photo_id=photo.id, face_index=idx, bbox_x=x, bbox_y=y, bbox_w=w, bbox_h=h))

    host_member = models.Member(
        session_id=session.id, user_id=current_user.id,
        nickname=current_user.nickname, role="host", connected=False,
    )
    db.add(host_member)
    db.commit()
    db.refresh(session)

    edit_state_store.get(db, photo.id)
    return _session_to_detail(db, session)


@router.get("/{session_id}", response_model=schemas.SessionDetail)
def get_session(
    session_id: str,
    member: models.Member = Depends(security.get_current_member),
    db: Session = Depends(get_db),
):
    session = _get_session_or_404(db, session_id)
    _require_membership(session_id, member)
    return _session_to_detail(db, session)


@router.post("/join", response_model=schemas.JoinResponse)
def join_session(
    payload: schemas.JoinRequest,
    db: Session = Depends(get_db),
    current_user: Optional[models.User] = Depends(security.get_optional_user),
):
    """초대 링크/코드로 참여(SES-04). 로그인 없이 닉네임만으로도 참여 가능(AUTH-02)."""
    session = (
        db.query(models.EditSession)
        .filter(
            (models.EditSession.invite_token == payload.invite)
            | (models.EditSession.invite_code == payload.invite.upper())
        )
        .first()
    )
    if session is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "invalid invite")
    if session.status != "active" or session.expires_at < datetime.utcnow():
        raise HTTPException(status.HTTP_410_GONE, "session expired or locked")

    active_members = [m for m in session.members if m.left_at is None]

    if current_user is not None:
        existing = next((m for m in active_members if m.user_id == current_user.id), None)
        if existing is not None:
            token = security.create_member_token(existing.id, session.id)
            return schemas.JoinResponse(memberToken=token, session=_session_to_detail(db, session))
        nickname = payload.nickname or current_user.nickname
    else:
        if not payload.nickname:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "nickname is required for guest join")
        nickname = payload.nickname

    if len(active_members) >= session.max_members:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "session is full")  # SES-05

    member = models.Member(
        session_id=session.id,
        user_id=current_user.id if current_user else None,
        nickname=nickname,
        role="guest",
    )
    db.add(member)
    session.last_activity_at = datetime.utcnow()
    db.commit()
    db.refresh(member)

    token = security.create_member_token(member.id, session.id)
    return schemas.JoinResponse(memberToken=token, session=_session_to_detail(db, session))


@router.post("/{session_id}/lock", response_model=schemas.SessionDetail)
def toggle_lock(
    session_id: str,
    locked: bool,
    member: models.Member = Depends(security.get_current_member),
    db: Session = Depends(get_db),
):
    """호스트가 세션을 보기 전용으로 전환(SES-07)."""
    session = _get_session_or_404(db, session_id)
    _require_membership(session_id, member)
    if member.role != "host":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "host only")
    session.status = "locked" if locked else "active"
    db.commit()
    return _session_to_detail(db, session)


@router.post("/{session_id}/members/{target_member_id}/kick", status_code=status.HTTP_204_NO_CONTENT)
async def kick_member(
    session_id: str,
    target_member_id: str,
    member: models.Member = Depends(security.get_current_member),
    db: Session = Depends(get_db),
):
    """호스트가 게스트를 강퇴(SES-07). 강퇴 시 클레임한 얼굴은 해제된다."""
    _get_session_or_404(db, session_id)
    _require_membership(session_id, member)
    if member.role != "host":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "host only")

    target = db.get(models.Member, target_member_id)
    if target is None or target.session_id != session_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "member not found")

    target.left_at = datetime.utcnow()
    for face in (
        db.query(models.Face)
        .join(models.Photo)
        .filter(models.Photo.session_id == session_id, models.Face.claimed_by_member_id == target_member_id)
    ):
        face.claimed_by_member_id = None
    db.commit()

    connection_manager.disconnect(session_id, target_member_id)
    await connection_manager.broadcast(session_id, {"type": "member_kicked", "memberId": target_member_id})


@router.post("/{session_id}/photos/{photo_id}/save", response_model=schemas.ExportOut)
async def save_photo_endpoint(
    session_id: str,
    photo_id: str,
    member: models.Member = Depends(security.get_current_member),
    db: Session = Depends(get_db),
):
    """최종 저장(OUT-01) + 전원 배포(OUT-02).

    풀해상도 렌더링(문서 5장 "최종 렌더링 일관성")은 호스트 기기 또는 서버 렌더러가
    수행해 최종 파일을 만든 뒤 이 엔드포인트로 결과 URL을 넘기는 것을 전제로 한다.
    여기서는 그 렌더링 결과를 기록하고 세션 전원에게 브로드캐스트하는 배포 로직만 담당한다.
    """
    _get_session_or_404(db, session_id)
    _require_membership(session_id, member)
    if member.role != "host":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "저장 확정은 호스트만 가능합니다 (OUT-03 기본 정책)")

    photo = db.get(models.Photo, photo_id)
    if photo is None or photo.session_id != session_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "photo not found")

    state = edit_state_store.get(db, photo_id)
    export = models.ExportResult(session_id=session_id, photo_id=photo_id, url=photo.url)
    db.add(export)
    db.commit()
    db.refresh(export)

    await connection_manager.broadcast(session_id, {
        "type": "export_ready", "photoId": photo_id, "exportId": export.id,
        "url": export.url, "version": state.version,
    })
    return schemas.ExportOut(id=export.id, photoId=photo_id, url=export.url, createdAt=export.created_at)
