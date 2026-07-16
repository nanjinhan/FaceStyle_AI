from datetime import datetime

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, status
from sqlalchemy.orm import Session

from .. import models, security
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


async def _handle_message(db: Session, session_id: str, member: models.Member, msg: dict) -> None:
    msg_type = msg.get("type")

    if msg_type == "edit":
        await _apply_and_broadcast(db, session_id, member, msg["photoId"], msg["path"], msg["value"])

    elif msg_type in ("undo", "redo"):
        photo_id = msg["photoId"]
        state = edit_state_store.get(db, photo_id)
        entry = state.undo(member.id) if msg_type == "undo" else state.redo(member.id)
        if entry is None:
            return
        edit_state_store.persist(db, state)
        db.add(models.EditHistory(
            photo_id=photo_id, seq=entry["seq"], member_id=member.id,
            op=entry["op"], path=entry["path"], from_value=entry["from"], to_value=entry["to"],
        ))
        db.commit()
        await connection_manager.broadcast(session_id, {"type": "edit_applied", "photoId": photo_id, **entry})

    elif msg_type == "presence":
        presence = connection_manager.presence.setdefault(session_id, {}).setdefault(member.id, {})
        presence["tool"] = msg.get("tool")
        presence["region"] = msg.get("region")
        await connection_manager.broadcast(session_id, {
            "type": "presence_update", "memberId": member.id,
            "tool": msg.get("tool"), "region": msg.get("region"), "connected": True,
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


async def _apply_and_broadcast(
    db: Session, session_id: str, member: models.Member, photo_id: str, path: str, value
) -> None:
    state = edit_state_store.get(db, photo_id)
    entry = state.apply(member.id, path, value)
    edit_state_store.persist(db, state)
    db.add(models.EditHistory(
        photo_id=photo_id, seq=entry["seq"], member_id=member.id,
        op=entry["op"], path=entry["path"], from_value=entry["from"], to_value=entry["to"],
    ))
    db.commit()
    await connection_manager.broadcast(session_id, {"type": "edit_applied", "photoId": photo_id, **entry})
