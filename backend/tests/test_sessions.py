"""B8(다중 업로드·컷 선택) · B9(6명/24시간) 검증."""

from datetime import datetime, timedelta

from conftest import PNG_1X1, create_room, host_member_token, join_room, make_user


class TestMultiPhotoUpload:
    """명세 3장: "여러 장 업로드 후 보정할 컷 함께 선택"."""

    def test_방을_만들_때_여러_장을_올릴_수_있다(self, client):
        user_token, _ = make_user(client)
        room = create_room(client, user_token, photo_count=3)

        assert len(room["photos"]) == 3
        # 컷 선택 UI가 순서를 유지할 수 있도록 각 사진이 고유 URL과 편집 상태를 갖는다
        assert len({p["id"] for p in room["photos"]}) == 3
        assert len({p["url"] for p in room["photos"]}) == 3
        assert all(p["editState"]["version"] == 0 for p in room["photos"])

    def test_방을_만든_뒤에도_사진을_추가할_수_있다(self, client):
        user_token, _ = make_user(client)
        room = create_room(client, user_token, photo_count=1)
        host_token = host_member_token(room)

        res = client.post(
            f"/sessions/{room['id']}/photos",
            files=[("files", ("extra.png", PNG_1X1, "image/png"))],
            headers={"Authorization": f"Bearer {host_token}"},
        )

        assert res.status_code == 201, res.text
        assert len(res.json()["photos"]) == 2

    def test_게스트도_사진을_추가할_수_있다(self, client):
        user_token, _ = make_user(client)
        room = create_room(client, user_token)
        guest_token = join_room(client, room["inviteToken"], "게스트")

        res = client.post(
            f"/sessions/{room['id']}/photos",
            files=[("files", ("g.png", PNG_1X1, "image/png"))],
            headers={"Authorization": f"Bearer {guest_token}"},
        )

        assert res.status_code == 201

    def test_상한을_넘기면_거부한다(self, client):
        user_token, _ = make_user(client)
        files = [("files", (f"p{i}.png", PNG_1X1, "image/png")) for i in range(21)]

        res = client.post("/sessions", files=files, headers={"Authorization": f"Bearer {user_token}"})

        assert res.status_code == 400
        assert "최대" in res.json()["detail"]

    def test_지원하지_않는_형식은_거부한다(self, client):
        user_token, _ = make_user(client)

        res = client.post(
            "/sessions",
            files=[("files", ("bad.txt", b"hello", "text/plain"))],
            headers={"Authorization": f"Bearer {user_token}"},
        )

        assert res.status_code == 400


class TestRoomLimits:
    """명세 3장: 인원 제한 6명, 24시간 후 자동 만료."""

    def test_방_정원은_6명이다(self, client):
        user_token, _ = make_user(client)
        room = create_room(client, user_token)

        assert room["maxMembers"] == 6

        # 방장 1 + 게스트 5 = 6명까지 입장 가능
        for i in range(5):
            join_room(client, room["inviteToken"], f"친구{i}")

        res = client.post("/sessions/join", json={"invite": room["inviteToken"], "nickname": "일곱번째"})
        assert res.status_code == 403
        assert "full" in res.json()["detail"]

    def test_만료는_24시간_뒤다(self, client):
        user_token, _ = make_user(client)
        room = create_room(client, user_token)

        expires = datetime.fromisoformat(room["expiresAt"])
        delta = expires - datetime.utcnow()

        assert timedelta(hours=23, minutes=55) < delta <= timedelta(hours=24)

    def test_공용영역_기본정책은_방장_전용이다(self, client):
        user_token, _ = make_user(client)
        room = create_room(client, user_token)

        assert room["globalEditPolicy"] == "host_only"


class TestInvite:
    def test_초대_코드로도_참여할_수_있다(self, client):
        user_token, _ = make_user(client)
        room = create_room(client, user_token)

        token = join_room(client, room["inviteCode"], "코드로온친구")

        assert token
