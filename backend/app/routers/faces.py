from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from .. import models, security
from ..collab.manager import connection_manager
from ..database import get_db

router = APIRouter(prefix="/sessions/{session_id}/photos/{photo_id}/faces", tags=["faces"])


def _get_face(db: Session, photo_id: str, face_id: str) -> models.Face:
    face = db.get(models.Face, face_id)
    if face is None or face.photo_id != photo_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "face not found")
    return face


@router.post("/{face_id}/claim")
async def claim_face(
    session_id: str,
    photo_id: str,
    face_id: str,
    member: models.Member = Depends(security.get_current_member),
    db: Session = Depends(get_db),
):
    """"이 얼굴은 나" 지정(FACE-02). 이미 다른 사람이 클레임했으면 거부한다."""
    if member.session_id != session_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "not a member of this session")
    face = _get_face(db, photo_id, face_id)
    if face.claimed_by_member_id and face.claimed_by_member_id != member.id:
        raise HTTPException(status.HTTP_409_CONFLICT, "face already claimed by another member")

    face.claimed_by_member_id = member.id
    db.commit()
    await connection_manager.broadcast(session_id, {
        "type": "face_claimed", "faceId": face_id, "memberId": member.id,
    })
    return {"faceId": face_id, "claimedByMemberId": member.id}


@router.post("/{face_id}/unclaim")
async def unclaim_face(
    session_id: str,
    photo_id: str,
    face_id: str,
    member: models.Member = Depends(security.get_current_member),
    db: Session = Depends(get_db),
):
    if member.session_id != session_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "not a member of this session")
    face = _get_face(db, photo_id, face_id)
    if face.claimed_by_member_id != member.id and member.role != "host":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "can only release your own claim")

    face.claimed_by_member_id = None
    db.commit()
    await connection_manager.broadcast(session_id, {"type": "face_released", "faceId": face_id})
    return {"faceId": face_id, "claimedByMemberId": None}
