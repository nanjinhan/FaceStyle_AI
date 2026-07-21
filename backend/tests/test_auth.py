"""B1(고유 색상 배정) · 닉네임 변경 검증."""

from app.colors import PALETTE
from conftest import make_user


def login(client, provider_id, nickname):
    return client.post("/auth/social-login", json={
        "provider": "dev", "provider_id": provider_id, "nickname": nickname,
    }).json()


class TestUserColor:
    def test_가입하면_고유색이_배정된다(self, client):
        body = login(client, "u1", "지우")
        assert body["user"]["color"] in PALETTE

    def test_여러명이_서로_다른_색을_받는다(self, client):
        colors = [login(client, f"u{i}", f"친구{i}")["user"]["color"] for i in range(len(PALETTE))]
        # 팔레트 크기만큼 가입하면 전부 다른 색이어야 한다 (고르게 배정)
        assert len(set(colors)) == len(PALETTE)

    def test_기존_유저는_색이_유지된다(self, client):
        first = login(client, "same", "지우")["user"]["color"]
        again = login(client, "same", "지우")["user"]["color"]
        assert first == again


class TestUpdateProfile:
    def test_닉네임을_바꾼다(self, client):
        token, _ = make_user(client, "옛닉")
        res = client.patch("/auth/me", json={"nickname": "새닉"},
                           headers={"Authorization": f"Bearer {token}"})
        assert res.status_code == 200
        assert res.json()["nickname"] == "새닉"

    def test_빈_닉네임은_거부한다(self, client):
        token, _ = make_user(client)
        res = client.patch("/auth/me", json={"nickname": "  "},
                           headers={"Authorization": f"Bearer {token}"})
        assert res.status_code == 400

    def test_로그인_유저의_색이_방_멤버에_노출된다(self, client):
        from conftest import create_room, host_member_token  # noqa
        token, _ = make_user(client, "호스트")
        room = create_room(client, token)
        host = next(m for m in room["members"] if m["role"] == "host")
        assert host["color"] in PALETTE
