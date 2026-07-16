from typing import Optional

from fastapi import WebSocket


class ConnectionManager:
    """세션별 실시간 연결/프레즌스/소프트 락을 관리한다 (COLLAB-01~04).

    단일 프로세스 인메모리 구조라 서버를 여러 대로 확장하면 세션을 sticky하게 라우팅하거나
    Redis pub/sub으로 브로드캐스트를 교체해야 한다(비기능 요구사항: 세션 단위 샤딩).
    """

    def __init__(self):
        self.connections: dict[str, dict[str, WebSocket]] = {}
        self.presence: dict[str, dict[str, dict]] = {}
        self.param_locks: dict[str, dict[str, str]] = {}

    async def connect(self, session_id: str, member_id: str, nickname: str, ws: WebSocket) -> None:
        await ws.accept()
        self.connections.setdefault(session_id, {})[member_id] = ws
        self.presence.setdefault(session_id, {})[member_id] = {
            "nickname": nickname, "tool": None, "region": None,
        }

    def disconnect(self, session_id: str, member_id: str) -> None:
        self.connections.get(session_id, {}).pop(member_id, None)
        self.presence.get(session_id, {}).pop(member_id, None)
        locks = self.param_locks.get(session_id, {})
        for path in [p for p, holder in locks.items() if holder == member_id]:
            locks.pop(path, None)

    async def broadcast(self, session_id: str, message: dict, exclude: Optional[str] = None) -> None:
        for member_id, ws in list(self.connections.get(session_id, {}).items()):
            if member_id == exclude:
                continue
            try:
                await ws.send_json(message)
            except Exception:
                self.disconnect(session_id, member_id)


connection_manager = ConnectionManager()
