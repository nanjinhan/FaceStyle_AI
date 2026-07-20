"""B3 — 편집 권한 **서버측** 강제 검증.

아키텍처 설계 원칙 3 "내 것만 편집": 클라이언트를 신뢰하지 않는다.
악의적인 클라이언트가 임의의 path로 edit을 쏴도 서버가 막아야 한다.
"""

from conftest import add_face, claim_face, create_room, host_member_token, join_room, make_user


def open_ws(client, session_id: str, token: str):
    """WS를 열고 첫 state_sync를 소비한 뒤 돌려준다."""
    ws = client.websocket_connect(f"/ws/sessions/{session_id}?token={token}").__enter__()
    first = ws.receive_json()
    assert first["type"] == "state_sync"
    return ws


def setup_room(client, guest_nickname: str = "게스트"):
    """방장 1 + 게스트 1 짜리 방을 만든다."""
    user_token, _ = make_user(client)
    room = create_room(client, user_token)
    photo_id = room["photos"][0]["id"]
    guest_token = join_room(client, room["inviteToken"], guest_nickname)
    return room, photo_id, host_member_token(room), guest_token


class TestFacePermissions:
    def test_클레임한_본인은_자기_얼굴을_편집할_수_있다(self, client):
        room, photo_id, _host_token, guest_token = setup_room(client)
        face_id = add_face(photo_id)
        assert claim_face(client, room["id"], photo_id, face_id, guest_token).status_code == 200

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={guest_token}") as ws:
            assert ws.receive_json()["type"] == "state_sync"
            ws.send_json({
                "type": "edit", "photoId": photo_id,
                "path": f"faces.{face_id}.jawSlim", "value": 30,
            })
            msg = ws.receive_json()

        assert msg["type"] == "edit_applied"
        assert msg["to"] == 30

    def test_남의_얼굴은_편집할_수_없다(self, client):
        """핵심 원칙: "OO님의 영역이에요"."""
        room, photo_id, host_token, guest_token = setup_room(client)
        face_id = add_face(photo_id)
        # 게스트가 먼저 클레임
        assert claim_face(client, room["id"], photo_id, face_id, guest_token).status_code == 200

        # 방장이 그 얼굴을 건드리려 하면 거부돼야 한다 (방장이라도 남의 얼굴은 못 만진다)
        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as ws:
            assert ws.receive_json()["type"] == "state_sync"
            ws.send_json({
                "type": "edit", "photoId": photo_id,
                "path": f"faces.{face_id}.jawSlim", "value": 99,
            })
            msg = ws.receive_json()

        assert msg["type"] == "edit_rejected"
        assert "다른 참여자" in msg["reason"]

    def test_아무도_클레임_안한_얼굴은_편집할_수_없다(self, client):
        room, photo_id, _host_token, guest_token = setup_room(client)
        face_id = add_face(photo_id)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={guest_token}") as ws:
            assert ws.receive_json()["type"] == "state_sync"
            ws.send_json({
                "type": "edit", "photoId": photo_id,
                "path": f"faces.{face_id}.eyeScale", "value": 20,
            })
            msg = ws.receive_json()

        assert msg["type"] == "edit_rejected"

    def test_존재하지_않는_얼굴은_거부한다(self, client):
        room, photo_id, _host_token, guest_token = setup_room(client)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={guest_token}") as ws:
            assert ws.receive_json()["type"] == "state_sync"
            ws.send_json({
                "type": "edit", "photoId": photo_id,
                "path": "faces.face_없음.jawSlim", "value": 20,
            })
            msg = ws.receive_json()

        assert msg["type"] == "edit_rejected"


class TestGlobalPermissions:
    """명세 3장 "공용 영역 권한" — 기본값 방장 전용."""

    def test_기본값에서_방장은_공용영역을_편집한다(self, client):
        room, photo_id, host_token, _guest = setup_room(client)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as ws:
            assert ws.receive_json()["type"] == "state_sync"
            ws.send_json({"type": "edit", "photoId": photo_id, "path": "global.brightness", "value": 40})
            msg = ws.receive_json()

        assert msg["type"] == "edit_applied"

    def test_기본값에서_게스트는_공용영역을_못_건드린다(self, client):
        room, photo_id, _host, guest_token = setup_room(client)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={guest_token}") as ws:
            assert ws.receive_json()["type"] == "state_sync"
            ws.send_json({"type": "edit", "photoId": photo_id, "path": "global.brightness", "value": 40})
            msg = ws.receive_json()

        assert msg["type"] == "edit_rejected"
        assert "방장" in msg["reason"]

    def test_전체_허용으로_바꾸면_게스트도_편집한다(self, client):
        room, photo_id, host_token, guest_token = setup_room(client)
        res = client.post(
            f"/sessions/{room['id']}/global-edit-policy",
            params={"policy": "everyone"},
            headers={"Authorization": f"Bearer {host_token}"},
        )
        assert res.status_code == 200, res.text
        assert res.json()["globalEditPolicy"] == "everyone"

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={guest_token}") as ws:
            assert ws.receive_json()["type"] == "state_sync"
            ws.send_json({"type": "edit", "photoId": photo_id, "path": "global.saturation", "value": 25})
            msg = ws.receive_json()

        assert msg["type"] == "edit_applied"

    def test_게스트는_정책을_바꿀_수_없다(self, client):
        room, _photo_id, _host, guest_token = setup_room(client)
        res = client.post(
            f"/sessions/{room['id']}/global-edit-policy",
            params={"policy": "everyone"},
            headers={"Authorization": f"Bearer {guest_token}"},
        )
        assert res.status_code == 403


class TestMaliciousInput:
    def test_알_수_없는_경로는_거부한다(self, client):
        room, photo_id, host_token, _guest = setup_room(client)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as ws:
            assert ws.receive_json()["type"] == "state_sync"
            ws.send_json({"type": "edit", "photoId": photo_id, "path": "global.rm_rf", "value": 1})
            msg = ws.receive_json()

        assert msg["type"] == "edit_rejected"

    def test_잠긴_방에서는_게스트가_편집할_수_없다(self, client):
        room, photo_id, host_token, guest_token = setup_room(client)
        face_id = add_face(photo_id)
        claim_face(client, room["id"], photo_id, face_id, guest_token)
        res = client.post(
            f"/sessions/{room['id']}/lock",
            params={"locked": True},
            headers={"Authorization": f"Bearer {host_token}"},
        )
        assert res.status_code == 200, res.text

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={guest_token}") as ws:
            assert ws.receive_json()["type"] == "state_sync"
            ws.send_json({
                "type": "edit", "photoId": photo_id,
                "path": f"faces.{face_id}.jawSlim", "value": 10,
            })
            msg = ws.receive_json()

        assert msg["type"] == "edit_rejected"
        assert "보기 전용" in msg["reason"]


class TestResetPermissions:
    """B6 기능별 리셋도 같은 권한 검사를 통과해야 한다."""

    def test_게스트는_공용영역을_리셋할_수_없다(self, client):
        room, photo_id, host_token, guest_token = setup_room(client)
        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as hws:
            hws.receive_json()
            hws.send_json({"type": "edit", "photoId": photo_id, "path": "global.brightness", "value": 40})
            hws.receive_json()

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={guest_token}") as ws:
            assert ws.receive_json()["type"] == "state_sync"
            ws.send_json({"type": "reset_param", "photoId": photo_id, "path": "global.brightness"})
            msg = ws.receive_json()

        assert msg["type"] == "edit_rejected"

    def test_방장은_공용영역_항목을_리셋한다(self, client):
        room, photo_id, host_token, _guest = setup_room(client)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as ws:
            assert ws.receive_json()["type"] == "state_sync"
            ws.send_json({"type": "edit", "photoId": photo_id, "path": "global.brightness", "value": 40})
            assert ws.receive_json()["type"] == "edit_applied"
            ws.send_json({"type": "reset_param", "photoId": photo_id, "path": "global.brightness"})
            msg = ws.receive_json()

        assert msg["type"] == "edit_applied"
        assert msg["op"] == "reset"
        assert msg["to"] == 0


class TestCursor:
    """명세 3장 "실시간 커서 — 편집 중인 위치를 색상 커서로 실시간 표시"."""

    def test_커서_좌표가_다른_참여자에게_전달된다(self, client):
        room, _photo_id, host_token, guest_token = setup_room(client)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as host_ws:
            assert host_ws.receive_json()["type"] == "state_sync"
            with client.websocket_connect(f"/ws/sessions/{room['id']}?token={guest_token}") as guest_ws:
                assert guest_ws.receive_json()["type"] == "state_sync"
                # 게스트 입장 알림을 방장이 받는다
                assert host_ws.receive_json()["type"] == "presence_update"

                guest_ws.send_json({
                    "type": "presence", "tool": "잡티 제거",
                    "cursor": {"x": 0.25, "y": 0.75},
                })
                msg = host_ws.receive_json()

        assert msg["type"] == "presence_update"
        assert msg["cursor"] == {"x": 0.25, "y": 0.75}
        assert msg["tool"] == "잡티 제거"

    def test_형식이_틀린_커서는_무시된다(self, client):
        room, _photo_id, host_token, guest_token = setup_room(client)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as host_ws:
            host_ws.receive_json()
            with client.websocket_connect(f"/ws/sessions/{room['id']}?token={guest_token}") as guest_ws:
                guest_ws.receive_json()
                host_ws.receive_json()

                guest_ws.send_json({"type": "presence", "cursor": "여기요"})
                msg = host_ws.receive_json()

        assert msg["cursor"] is None


class TestPersonalUndoOverWs:
    def test_내_undo가_남의_편집을_건드리지_않는다(self, client):
        """B5 — 두 사람이 각자 편집한 뒤 한 명만 되돌린다."""
        room, photo_id, host_token, guest_token = setup_room(client)
        face_id = add_face(photo_id)
        claim_face(client, room["id"], photo_id, face_id, guest_token)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as host_ws:
            host_ws.receive_json()
            with client.websocket_connect(f"/ws/sessions/{room['id']}?token={guest_token}") as guest_ws:
                guest_ws.receive_json()
                host_ws.receive_json()  # presence_update

                # 방장: 공용 영역 편집
                host_ws.send_json({"type": "edit", "photoId": photo_id, "path": "global.brightness", "value": 40})
                host_ws.receive_json()
                guest_ws.receive_json()

                # 게스트: 자기 얼굴 편집
                guest_ws.send_json({
                    "type": "edit", "photoId": photo_id,
                    "path": f"faces.{face_id}.jawSlim", "value": 25,
                })
                guest_ws.receive_json()
                host_ws.receive_json()

                # 방장이 undo → 자기 편집(global.brightness)만 되돌아가야 한다
                host_ws.send_json({"type": "undo", "photoId": photo_id})
                undo_msg = host_ws.receive_json()

        assert undo_msg["op"] == "undo"
        assert undo_msg["path"] == "global.brightness"
        assert undo_msg["to"] == 0

    def test_되돌릴_게_없으면_아무_응답도_없다(self, client):
        room, photo_id, host_token, _guest = setup_room(client)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as ws:
            ws.receive_json()
            ws.send_json({"type": "undo", "photoId": photo_id})
            # 응답이 없어야 하므로, 뒤이은 정상 편집의 응답이 먼저 와야 한다
            ws.send_json({"type": "edit", "photoId": photo_id, "path": "global.contrast", "value": 10})
            msg = ws.receive_json()

        assert msg["type"] == "edit_applied"
        assert msg["path"] == "global.contrast"
