from datetime import datetime
from typing import Optional

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, status
from sqlalchemy.orm import Session

from .. import models, security
from ..collab import state as state_module
from ..collab.manager import connection_manager
from ..collab.state import edit_state_store
from ..database import SessionLocal

router = APIRouter(tags=["realtime"])


def _member_from_token(db: Session, token: str, session_id: str) -> models.Member:
    payload = security.decode_token(token)
    if payload.get("typ") != "member" or payload.get("session_id") != session_id:
        raise ValueError("invalid member token for this session")
    member = db.get(models.Member, payload["sub"])
    if member is None or member.left_at is not None:
        raise ValueError("member not found")
    return member


@router.websocket("/ws/sessions/{session_id}")
async def session_ws(websocket: WebSocket, session_id: str, token: str):
    """세션당 실시간 동기화 채널 하나 (COLLAB-01~04, 06, 08).

    연결 직후 현재 편집 상태 전체를 스냅샷으로 보내고(state_sync), 이후 각 클라이언트가
    보내는 파라미터 변경/undo/redo/프레즌스/소프트 락/이모지 리액션 메시지를 세션 내
    전원에게 즉시 브로드캐스트한다. WebSocket 직결이므로 300ms 목표(COLLAB-01)는
    네트워크/인프라 구간의 문제이며 여기서 인위적 지연은 없다.
    """
    db = SessionLocal()
    try:
        member = _member_from_token(db, token, session_id)
    except ValueError:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        db.close()
        return

    session = db.get(models.EditSession, session_id)
    if session is None or session.status == "expired":
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        db.close()
        return

    await connection_manager.connect(session_id, member.id, member.nickname, websocket)
    member.connected = True
    session.last_activity_at = datetime.utcnow()
    db.commit()

    photo_states = {photo.id: edit_state_store.get(db, photo.id).as_dict() for photo in session.photos}
    await websocket.send_json({
        "type": "state_sync",
        "photos": photo_states,
        "completions": {photo.id: _completion_payload(photo) for photo in session.photos},
        "presence": connection_manager.presence.get(session_id, {}),
        "locks": connection_manager.param_locks.get(session_id, {}),
    })
    await connection_manager.broadcast(session_id, {
        "type": "presence_update", "memberId": member.id, "nickname": member.nickname, "connected": True,
    }, exclude=member.id)

    try:
        while True:
            msg = await websocket.receive_json()
            await _handle_message(db, session_id, member, msg)
    except WebSocketDisconnect:
        pass
    finally:
        connection_manager.disconnect(session_id, member.id)
        member.connected = False
        # 개인 undo 이력은 접속 단위로 유지된다 (재접속 시 새 스택).
        for photo in session.photos:
            edit_state_store.get(db, photo.id).forget_member(member.id)
        if member.role == "guest":
            # 게스트 이탈 시 클레임 해제(문서 7.2 예외 플로우)
            for face in (
                db.query(models.Face)
                .join(models.Photo)
                .filter(models.Photo.session_id == session_id, models.Face.claimed_by_member_id == member.id)
            ):
                face.claimed_by_member_id = None
        db.commit()
        await connection_manager.broadcast(session_id, {
            "type": "presence_update", "memberId": member.id, "connected": False,
        })
        db.close()


def _authorize_edit(
    db: Session,
    session: models.EditSession,
    member: models.Member,
    photo: models.Photo,
    path: str,
) -> Optional[str]:
    """편집 권한을 **서버에서** 강제한다 (명세 3장 "편집 권한 분리" / 아키텍처 설계 원칙 3).

    거부 사유 문자열을 돌려주고, 통과하면 None. 클라이언트를 신뢰하지 않는다.
      - `faces.{faceId}.*` → 그 얼굴을 클레임한 본인만
      - `global.*`        → 방 설정(기본 방장 전용)에 따름
    """
    if photo.finalized_at is not None:
        return "이미 확정된 사진이에요"
    if session.status == "locked" and member.role != "host":
        return "방이 보기 전용으로 잠겨 있어요"

    face_id = state_module.face_id_of(path)
    if face_id is not None:
        face = db.get(models.Face, face_id)
        if face is None or face.photo_id != photo.id:
            return "얼굴을 찾을 수 없어요"
        if face.claimed_by_member_id is None:
            return "아직 아무도 지정하지 않은 얼굴이에요"
        if face.claimed_by_member_id != member.id:
            return "다른 참여자의 영역이에요"
        return None

    # global.* — 공용 영역
    if session.global_edit_policy != "everyone" and member.role != "host":
        return "공용 영역은 방장만 편집할 수 있어요"
    return None


def _required_members(photo: models.Photo) -> list[str]:
    """완료 확정의 분모 — 그 사진에서 얼굴을 클레임한 멤버들.

    명세 4장 "진행 상태 아이콘 — 사진 속 클레임 인원 기준으로 계산 (예: 2/3 완료)".
    """
    return sorted({f.claimed_by_member_id for f in photo.faces if f.claimed_by_member_id})


def _completion_payload(photo: models.Photo) -> dict:
    return {
        "photoId": photo.id,
        "completed": sorted(c.member_id for c in photo.completions),
        "required": _required_members(photo),
        "finalized": photo.finalized_at is not None,
    }


async def _reject(session_id: str, member_id: str, photo_id: str, path: str, reason: str) -> None:
    await connection_manager.send_to(session_id, member_id, {
        "type": "edit_rejected", "photoId": photo_id, "path": path, "reason": reason,
    })


async def _handle_message(db: Session, session_id: str, member: models.Member, msg: dict) -> None:
    msg_type = msg.get("type")

    if msg_type in ("edit", "reset_param"):
        photo_id = msg.get("photoId")
        path = msg.get("path")
        if not isinstance(photo_id, str) or not isinstance(path, str):
            return
        session = db.get(models.EditSession, session_id)
        photo = db.get(models.Photo, photo_id)
        if session is None or photo is None or photo.session_id != session_id:
            return

        reason = _authorize_edit(db, session, member, photo, path)
        if reason is not None:
            await _reject(session_id, member.id, photo_id, path, reason)
            return

        state = edit_state_store.get(db, photo_id)
        try:
            if msg_type == "edit":
                entry = state.apply(member.id, path, msg.get("value"))
            else:
                entry = state.reset(member.id, path)
        except state_module.InvalidPath as exc:
            await _reject(session_id, member.id, photo_id, path, str(exc))
            return
        if entry is None:  # 이미 기본값이라 바뀐 게 없다
            return
        await _persist_and_broadcast(db, session_id, photo_id, member, state, entry)

    elif msg_type in ("undo", "redo"):
        photo_id = msg.get("photoId")
        if not isinstance(photo_id, str):
            return
        state = edit_state_store.get(db, photo_id)
        # 본인 스택만 되감으므로 권한 재검사가 필요 없다 (애초에 통과한 편집만 쌓인다).
        entry = state.undo(member.id) if msg_type == "undo" else state.redo(member.id)
        if entry is None:
            return
        await _persist_and_broadcast(db, session_id, photo_id, member, state, entry)

    elif msg_type in ("complete", "uncomplete"):
        photo_id = msg.get("photoId")
        if not isinstance(photo_id, str):
            return
        photo = db.get(models.Photo, photo_id)
        if photo is None or photo.session_id != session_id:
            return
        if photo.finalized_at is not None:
            await _reject(session_id, member.id, photo_id, "", "이미 확정된 사진이에요")
            return

        # 얼굴을 지정하지 않은 사람은 완료 체크 대상이 아니다.
        if member.id not in _required_members(photo):
            await _reject(session_id, member.id, photo_id, "", "이 사진에서 지정한 얼굴이 없어요")
            return

        existing = (
            db.query(models.PhotoCompletion)
            .filter(
                models.PhotoCompletion.photo_id == photo_id,
                models.PhotoCompletion.member_id == member.id,
            )
            .first()
        )
        if msg_type == "complete" and existing is None:
            db.add(models.PhotoCompletion(photo_id=photo_id, member_id=member.id))
        elif msg_type == "uncomplete" and existing is not None:
            db.delete(existing)
        else:
            return  # 이미 그 상태 — 알릴 변화가 없다
        db.commit()
        db.refresh(photo)

        await connection_manager.broadcast(session_id, {
            "type": "completion_update", **_completion_payload(photo),
        })
        await _finalize_if_everyone_done(db, session_id, photo)

    elif msg_type == "presence":
        presence = connection_manager.presence.setdefault(session_id, {}).setdefault(member.id, {})
        cursor = msg.get("cursor")
        if not (isinstance(cursor, dict) and {"x", "y"} <= cursor.keys()):
            cursor = None
        presence["tool"] = msg.get("tool")
        presence["region"] = msg.get("region")
        presence["cursor"] = cursor
        await connection_manager.broadcast(session_id, {
            "type": "presence_update", "memberId": member.id,
            "tool": msg.get("tool"), "region": msg.get("region"), "cursor": cursor,
            "connected": True,
        }, exclude=member.id)

    elif msg_type == "lock_param":
        path = msg["path"]
        locks = connection_manager.param_locks.setdefault(session_id, {})
        if path in locks and locks[path] != member.id:
            return
        locks[path] = member.id
        await connection_manager.broadcast(session_id, {
            "type": "param_locked", "path": path, "memberId": member.id,
        }, exclude=member.id)

    elif msg_type == "unlock_param":
        path = msg["path"]
        locks = connection_manager.param_locks.get(session_id, {})
        if locks.get(path) == member.id:
            locks.pop(path, None)
            await connection_manager.broadcast(session_id, {"type": "param_unlocked", "path": path}, exclude=member.id)

    elif msg_type == "reaction":
        await connection_manager.broadcast(session_id, {
            "type": "reaction", "memberId": member.id, "emoji": msg.get("emoji"),
        }, exclude=member.id)


async def _finalize_if_everyone_done(db: Session, session_id: str, photo: models.Photo) -> None:
    """전원이 완료 체크하면 최종본을 확정하고 편집을 잠근다 (명세 3장 "완료 확정").

    확정본은 그 시점의 파라미터 스냅샷이며, 각 기기가 같은 파라미터로 렌더링하므로
    결과가 동일하다(아키텍처 "최종 렌더링 일관성"). 서버는 픽셀을 만들지 않는다.
    """
    required = set(_required_members(photo))
    if not required:
        return  # 아무도 얼굴을 지정하지 않았다면 확정할 대상이 없다
    completed = {c.member_id for c in photo.completions}
    if not required <= completed:
        return

    state = edit_state_store.get(db, photo.id)
    photo.finalized_at = datetime.utcnow()
    photo.final_version = state.version
    db.commit()

    await connection_manager.broadcast(session_id, {
        "type": "finalized",
        "photoId": photo.id,
        "version": state.version,
        "editState": state.as_dict(),
        "finalizedAt": photo.finalized_at.isoformat(),
    })


async def _persist_and_broadcast(
    db: Session,
    session_id: str,
    photo_id: str,
    member: models.Member,
    state: state_module.PhotoEditState,
    entry: dict,
) -> None:
    """편집 1건을 DB에 남기고 방 전원에게 알린다."""
    edit_state_store.persist(db, state)
    db.add(models.EditHistory(
        photo_id=photo_id, seq=entry["seq"], member_id=member.id,
        op=entry["op"], path=entry["path"], from_value=entry["from"], to_value=entry["to"],
    ))
    db.commit()
    await connection_manager.broadcast(session_id, {"type": "edit_applied", "photoId": photo_id, **entry})
