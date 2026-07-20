"""테스트는 임시 SQLite DB와 임시 스토리지를 쓴다.

`app.config.settings`가 import 시점에 환경변수를 읽으므로, app 패키지를 import하기 전에
여기서 먼저 환경변수를 세팅해야 한다.
"""

import os
import shutil
import tempfile

_TMP = tempfile.mkdtemp(prefix="facestyle-test-")
os.environ["DATABASE_URL"] = f"sqlite:///{_TMP}/test.db"
os.environ["STORAGE_DIR"] = f"{_TMP}/storage"
os.environ["JWT_SECRET"] = "test-secret"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app import models, security  # noqa: E402
from app.collab.manager import connection_manager  # noqa: E402
from app.collab.state import edit_state_store  # noqa: E402
from app.database import Base, SessionLocal, engine  # noqa: E402
from app.main import app  # noqa: E402


def pytest_sessionfinish(session, exitstatus):
    shutil.rmtree(_TMP, ignore_errors=True)


@pytest.fixture(autouse=True)
def clean_state():
    """테스트마다 DB와 인메모리 캐시를 초기화한다."""
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    edit_state_store._states.clear()
    connection_manager.connections.clear()
    connection_manager.presence.clear()
    connection_manager.param_locks.clear()
    yield


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


@pytest.fixture
def db():
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


# --- 헬퍼 -------------------------------------------------------------------

# 1x1 PNG (실제 이미지 바이트가 필요한 업로드 테스트용)
PNG_1X1 = bytes.fromhex(
    "89504e470d0a1a0a0000000d494844520000000100000001080600000"
    "01f15c4890000000a49444154789c6360000002000100ffff0300000600"
    "05572bd8e50000000049454e44ae426082"
)


def make_user(client: TestClient, nickname: str = "호스트") -> tuple[str, str]:
    """소셜 로그인으로 유저를 만들고 (userToken, userId)를 돌려준다."""
    res = client.post("/auth/social-login", json={
        "provider": "kakao", "provider_id": f"pid-{nickname}", "nickname": nickname,
    })
    assert res.status_code == 200, res.text
    body = res.json()
    return body["access_token"], body["user"]["id"]


def create_room(client: TestClient, user_token: str, photo_count: int = 1) -> dict:
    """방을 만들고 SessionDetail을 돌려준다."""
    files = [("files", (f"p{i}.png", PNG_1X1, "image/png")) for i in range(photo_count)]
    res = client.post("/sessions", files=files, headers={"Authorization": f"Bearer {user_token}"})
    assert res.status_code == 201, res.text
    return res.json()


def join_room(client: TestClient, invite: str, nickname: str) -> str:
    """게스트로 참여하고 memberToken을 돌려준다."""
    res = client.post("/sessions/join", json={"invite": invite, "nickname": nickname})
    assert res.status_code == 200, res.text
    return res.json()["memberToken"]


def host_member_token(session_detail: dict) -> str:
    """방장의 member 토큰을 직접 발급한다 (호스트는 join을 거치지 않으므로)."""
    host = next(m for m in session_detail["members"] if m["role"] == "host")
    return security.create_member_token(host["id"], session_detail["id"])


def add_face(photo_id: str, face_index: int = 0) -> str:
    """서버 얼굴검출(opencv)이 없어도 되도록 얼굴 행을 직접 넣는다."""
    session = SessionLocal()
    try:
        face = models.Face(
            photo_id=photo_id, face_index=face_index,
            bbox_x=0, bbox_y=0, bbox_w=10, bbox_h=10,
        )
        session.add(face)
        session.commit()
        session.refresh(face)
        return face.id
    finally:
        session.close()


def claim_face(client: TestClient, session_id: str, photo_id: str, face_id: str, member_token: str):
    return client.post(
        f"/sessions/{session_id}/photos/{photo_id}/faces/{face_id}/claim",
        headers={"Authorization": f"Bearer {member_token}"},
    )
