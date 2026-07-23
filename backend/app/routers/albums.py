import random
import string
from datetime import datetime

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from .. import models, schemas, security, storage
from ..database import get_db
from ..face_detection import image_size

router = APIRouter(prefix="/albums", tags=["albums"])


def _gen_invite_code() -> str:
    return "".join(random.choices(string.ascii_uppercase + string.digits, k=6))


def _membership(db: Session, album_id: str, user_id: str) -> models.AlbumMember:
    """앨범 멤버십을 확인한다. 멤버가 아니면 403."""
    m = (
        db.query(models.AlbumMember)
        .filter(models.AlbumMember.album_id == album_id, models.AlbumMember.user_id == user_id)
        .first()
    )
    if m is None:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "이 앨범의 멤버가 아니에요")
    return m


def _member_out(m: models.AlbumMember) -> schemas.AlbumMemberOut:
    return schemas.AlbumMemberOut(
        id=m.id, userId=m.user_id,
        nickname=m.user.nickname if m.user else "알 수 없음",
        role=m.role,
        color=m.user.color if m.user else None,
    )


def _photo_out(p: models.AlbumPhoto) -> schemas.AlbumPhotoOut:
    return schemas.AlbumPhotoOut(
        id=p.id, url=p.url, width=p.width, height=p.height,
        uploaderUserId=p.uploader_user_id,
        finalized=p.finalized_at is not None,
        createdAt=p.created_at,
    )


def _detail(db: Session, album: models.Album, me: models.User) -> schemas.AlbumDetail:
    my = next((m for m in album.members if m.user_id == me.id), None)
    photos = sorted(album.photos, key=lambda p: p.created_at, reverse=True)
    return schemas.AlbumDetail(
        id=album.id, name=album.name, ownerUserId=album.owner_user_id,
        inviteToken=album.invite_token, inviteCode=album.invite_code,
        myRole=my.role if my else "member",
        members=[_member_out(m) for m in album.members],
        photos=[_photo_out(p) for p in photos],
    )


@router.post("", response_model=schemas.AlbumDetail, status_code=status.HTTP_201_CREATED)
def create_album(
    payload: schemas.CreateAlbumRequest,
    current_user: models.User = Depends(security.get_current_user),
    db: Session = Depends(get_db),
):
    """그룹 앨범 생성 (명세 4장). 생성자가 방장(owner)이 된다."""
    name = payload.name.strip()
    if not name:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "앨범 이름을 정해주세요")

    album = models.Album(name=name, owner_user_id=current_user.id, invite_code=_gen_invite_code())
    db.add(album)
    db.flush()
    db.add(models.AlbumMember(album_id=album.id, user_id=current_user.id, role="owner"))
    db.commit()
    db.refresh(album)
    return _detail(db, album, current_user)


@router.get("", response_model=list[schemas.AlbumSummary])
def list_my_albums(
    current_user: models.User = Depends(security.get_current_user),
    db: Session = Depends(get_db),
):
    """내가 속한 앨범 목록 (홈 피드용)."""
    memberships = (
        db.query(models.AlbumMember)
        .filter(models.AlbumMember.user_id == current_user.id)
        .all()
    )
    out = []
    for m in memberships:
        album = m.album
        if album is None:
            continue
        photos = sorted(album.photos, key=lambda p: p.created_at, reverse=True)
        out.append(schemas.AlbumSummary(
            id=album.id, name=album.name, ownerUserId=album.owner_user_id,
            role=m.role, memberCount=len(album.members), photoCount=len(photos),
            coverUrl=photos[0].url if photos else None,
        ))
    out.sort(key=lambda a: a.id)
    return out


@router.get("/{album_id}", response_model=schemas.AlbumDetail)
def get_album(
    album_id: str,
    current_user: models.User = Depends(security.get_current_user),
    db: Session = Depends(get_db),
):
    album = db.get(models.Album, album_id)
    if album is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "앨범을 찾을 수 없어요")
    _membership(db, album_id, current_user.id)
    return _detail(db, album, current_user)


@router.post("/join", response_model=schemas.AlbumDetail)
def join_album(
    payload: schemas.AlbumJoinRequest,
    current_user: models.User = Depends(security.get_current_user),
    db: Session = Depends(get_db),
):
    """초대 토큰/코드로 앨범 참여 (명세 4장 — 멤버 초대)."""
    album = (
        db.query(models.Album)
        .filter(
            (models.Album.invite_token == payload.invite)
            | (models.Album.invite_code == payload.invite.upper())
        )
        .first()
    )
    if album is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "잘못된 초대예요")

    existing = next((m for m in album.members if m.user_id == current_user.id), None)
    if existing is None:
        db.add(models.AlbumMember(album_id=album.id, user_id=current_user.id, role="member"))
        db.commit()
        db.refresh(album)
    return _detail(db, album, current_user)


@router.post("/{album_id}/photos", response_model=schemas.AlbumDetail, status_code=status.HTTP_201_CREATED)
def upload_album_photos(
    album_id: str,
    files: list[UploadFile] = File(...),
    current_user: models.User = Depends(security.get_current_user),
    db: Session = Depends(get_db),
):
    """멤버 누구나 앨범에 사진 업로드 (명세 4장)."""
    album = db.get(models.Album, album_id)
    if album is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "앨범을 찾을 수 없어요")
    _membership(db, album_id, current_user.id)
    if not files:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "사진을 최소 1장 올려주세요")

    for f in files:
        try:
            url, _ = storage.save_photo(album_id, f)
        except ValueError as exc:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, str(exc)) from exc
        from ..config import settings
        w, h = image_size(settings.storage_dir / url.removeprefix("/media/"))
        db.add(models.AlbumPhoto(
            album_id=album_id, uploader_user_id=current_user.id,
            url=url, width=w, height=h,
        ))
    db.commit()
    db.refresh(album)
    return _detail(db, album, current_user)


@router.post("/{album_id}/leave", status_code=status.HTTP_204_NO_CONTENT)
def leave_album(
    album_id: str,
    current_user: models.User = Depends(security.get_current_user),
    db: Session = Depends(get_db),
):
    """멤버 스스로 앨범 탈퇴 (명세 4장). 방장은 위임 전엔 나갈 수 없다."""
    m = _membership(db, album_id, current_user.id)
    if m.role == "owner":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "방장은 위임 후에 나갈 수 있어요")
    db.delete(m)
    db.commit()


@router.delete("/{album_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_album(
    album_id: str,
    current_user: models.User = Depends(security.get_current_user),
    db: Session = Depends(get_db),
):
    """앨범 삭제 — 방장 전용 (명세 4장)."""
    album = db.get(models.Album, album_id)
    if album is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "앨범을 찾을 수 없어요")
    m = _membership(db, album_id, current_user.id)
    if m.role != "owner":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "방장만 삭제할 수 있어요")
    db.delete(album)
    db.commit()
