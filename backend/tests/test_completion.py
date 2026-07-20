"""B7 — 완료 확정 검증.

명세 3장: "전원이 확정 체크 시 최종본 확정 + 전원 갤러리 자동 저장 / 확정 후 편집 잠금"
'전원'의 정의는 명세 4장 "사진 속 클레임 인원 기준으로 계산"을 따른다.
"""

from conftest import add_face, claim_face, create_room, host_member_token, join_room, make_user


def setup_room(client, guests=("게스트",)):
    user_token, _ = make_user(client)
    room = create_room(client, user_token)
    photo_id = room["photos"][0]["id"]
    guest_tokens = [join_room(client, room["inviteToken"], g) for g in guests]
    return room, photo_id, host_member_token(room), guest_tokens


def member_id_of(token: str) -> str:
    from app import security
    return security.decode_token(token)["sub"]


def drain(ws, wanted: str, limit: int = 8) -> dict:
    """원하는 타입의 메시지가 나올 때까지 읽는다."""
    for _ in range(limit):
        msg = ws.receive_json()
        if msg["type"] == wanted:
            return msg
    raise AssertionError(f"{wanted} 메시지를 받지 못했다")


class TestCompletion:
    def test_클레임한_사람만_완료_체크할_수_있다(self, client):
        room, photo_id, host_token, _guests = setup_room(client)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as ws:
            ws.receive_json()
            ws.send_json({"type": "complete", "photoId": photo_id})
            msg = ws.receive_json()

        assert msg["type"] == "edit_rejected"
        assert "지정한 얼굴이 없어요" in msg["reason"]

    def test_한_명이_완료하면_현황이_전파된다(self, client):
        room, photo_id, host_token, (guest_token,) = setup_room(client)
        face_id = add_face(photo_id)
        claim_face(client, room["id"], photo_id, face_id, guest_token)
        guest_id = member_id_of(guest_token)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as host_ws:
            host_ws.receive_json()
            with client.websocket_connect(f"/ws/sessions/{room['id']}?token={guest_token}") as guest_ws:
                guest_ws.receive_json()
                guest_ws.send_json({"type": "complete", "photoId": photo_id})
                msg = drain(host_ws, "completion_update")

        assert msg["completed"] == [guest_id]
        assert msg["required"] == [guest_id]

    def test_전원_완료하면_자동_확정된다(self, client):
        """두 명이 각자 얼굴을 클레임하고 둘 다 완료 → finalized."""
        room, photo_id, host_token, (guest_token,) = setup_room(client)
        host_face = add_face(photo_id, 0)
        guest_face = add_face(photo_id, 1)
        claim_face(client, room["id"], photo_id, host_face, host_token)
        claim_face(client, room["id"], photo_id, guest_face, guest_token)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as host_ws:
            host_ws.receive_json()
            with client.websocket_connect(f"/ws/sessions/{room['id']}?token={guest_token}") as guest_ws:
                guest_ws.receive_json()

                host_ws.send_json({"type": "edit", "photoId": photo_id, "path": f"faces.{host_face}.jawSlim", "value": 20})
                drain(host_ws, "edit_applied")

                # 한 명만 완료 — 아직 확정되면 안 된다
                host_ws.send_json({"type": "complete", "photoId": photo_id})
                mid = drain(host_ws, "completion_update")
                assert mid["finalized"] is False

                # 나머지도 완료 → 확정
                guest_ws.send_json({"type": "complete", "photoId": photo_id})
                final = drain(host_ws, "finalized")

        assert final["photoId"] == photo_id
        assert final["editState"]["faces"][host_face]["jawSlim"] == 20
        assert final["version"] >= 1

    def test_확정_후에는_편집이_잠긴다(self, client):
        room, photo_id, host_token, (guest_token,) = setup_room(client)
        face_id = add_face(photo_id)
        claim_face(client, room["id"], photo_id, face_id, host_token)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as ws:
            ws.receive_json()
            ws.send_json({"type": "complete", "photoId": photo_id})
            drain(ws, "finalized")

            # 확정된 사진은 본인 얼굴이라도 더 못 만진다
            ws.send_json({"type": "edit", "photoId": photo_id, "path": f"faces.{face_id}.jawSlim", "value": 50})
            msg = ws.receive_json()

        assert msg["type"] == "edit_rejected"
        assert "확정된 사진" in msg["reason"]

    def test_확정_후에는_공용영역도_잠긴다(self, client):
        room, photo_id, host_token, _guests = setup_room(client)
        face_id = add_face(photo_id)
        claim_face(client, room["id"], photo_id, face_id, host_token)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as ws:
            ws.receive_json()
            ws.send_json({"type": "complete", "photoId": photo_id})
            drain(ws, "finalized")

            ws.send_json({"type": "edit", "photoId": photo_id, "path": "global.brightness", "value": 30})
            msg = ws.receive_json()

        assert msg["type"] == "edit_rejected"

    def test_확정_전에는_완료를_취소할_수_있다(self, client):
        room, photo_id, host_token, (guest_token,) = setup_room(client)
        host_face = add_face(photo_id, 0)
        guest_face = add_face(photo_id, 1)
        claim_face(client, room["id"], photo_id, host_face, host_token)
        claim_face(client, room["id"], photo_id, guest_face, guest_token)
        host_id = member_id_of(host_token)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as ws:
            ws.receive_json()
            ws.send_json({"type": "complete", "photoId": photo_id})
            assert drain(ws, "completion_update")["completed"] == [host_id]

            ws.send_json({"type": "uncomplete", "photoId": photo_id})
            msg = drain(ws, "completion_update")

        assert msg["completed"] == []
        assert msg["finalized"] is False

    def test_확정된_뒤에는_취소할_수_없다(self, client):
        room, photo_id, host_token, _guests = setup_room(client)
        face_id = add_face(photo_id)
        claim_face(client, room["id"], photo_id, face_id, host_token)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as ws:
            ws.receive_json()
            ws.send_json({"type": "complete", "photoId": photo_id})
            drain(ws, "finalized")

            ws.send_json({"type": "uncomplete", "photoId": photo_id})
            msg = ws.receive_json()

        assert msg["type"] == "edit_rejected"
        assert "확정된 사진" in msg["reason"]

    def test_같은_완료를_두_번_보내도_중복되지_않는다(self, client):
        room, photo_id, host_token, (guest_token,) = setup_room(client)
        host_face = add_face(photo_id, 0)
        guest_face = add_face(photo_id, 1)
        claim_face(client, room["id"], photo_id, host_face, host_token)
        claim_face(client, room["id"], photo_id, guest_face, guest_token)
        host_id = member_id_of(host_token)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as ws:
            ws.receive_json()
            ws.send_json({"type": "complete", "photoId": photo_id})
            drain(ws, "completion_update")
            # 두 번째 complete는 무시되고, 뒤이은 메시지 응답이 먼저 온다
            ws.send_json({"type": "complete", "photoId": photo_id})
            ws.send_json({"type": "uncomplete", "photoId": photo_id})
            msg = drain(ws, "completion_update")

        assert msg["completed"] == []
        assert host_id not in msg["completed"]

    def test_아무도_클레임_안했으면_확정되지_않는다(self, client):
        """얼굴을 지정한 사람이 없으면 완료 대상 자체가 없다."""
        room, photo_id, host_token, _guests = setup_room(client)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as ws:
            ws.receive_json()
            ws.send_json({"type": "complete", "photoId": photo_id})
            msg = ws.receive_json()
            assert msg["type"] == "edit_rejected"

            # 편집은 여전히 가능해야 한다 (확정되지 않았으므로)
            ws.send_json({"type": "edit", "photoId": photo_id, "path": "global.contrast", "value": 5})
            assert ws.receive_json()["type"] == "edit_applied"


class TestCompletionVisibility:
    def test_state_sync에_완료_현황이_들어있다(self, client):
        room, photo_id, host_token, _guests = setup_room(client)
        face_id = add_face(photo_id)
        claim_face(client, room["id"], photo_id, face_id, host_token)
        host_id = member_id_of(host_token)

        with client.websocket_connect(f"/ws/sessions/{room['id']}?token={host_token}") as ws:
            sync = ws.receive_json()

        assert sync["completions"][photo_id]["required"] == [host_id]
        assert sync["completions"][photo_id]["completed"] == []
        assert sync["completions"][photo_id]["finalized"] is False

    def test_REST_응답에도_완료_현황이_들어있다(self, client):
        room, photo_id, host_token, _guests = setup_room(client)
        face_id = add_face(photo_id)
        claim_face(client, room["id"], photo_id, face_id, host_token)

        res = client.get(f"/sessions/{room['id']}", headers={"Authorization": f"Bearer {host_token}"})

        photo = res.json()["photos"][0]
        assert photo["requiredBy"] == [member_id_of(host_token)]
        assert photo["completedBy"] == []
        assert photo["finalized"] is False


class TestCrossSessionIsolation:
    def test_다른_방의_사진은_편집할_수_없다(self, client):
        """photoId만 알면 남의 방 사진을 편집할 수 있던 구멍을 막았는지 확인."""
        _room_a, photo_a, host_a, _ = setup_room(client)
        user_token_b, _ = make_user(client, "다른사람")
        room_b = create_room(client, user_token_b)

        with client.websocket_connect(f"/ws/sessions/{room_b['id']}?token={host_member_token(room_b)}") as ws:
            ws.receive_json()
            ws.send_json({"type": "edit", "photoId": photo_a, "path": "global.brightness", "value": 99})
            ws.send_json({"type": "edit", "photoId": room_b["photos"][0]["id"], "path": "global.contrast", "value": 5})
            msg = ws.receive_json()

        # 첫 메시지는 무시되고 두 번째(자기 방 사진)만 적용돼야 한다
        assert msg["type"] == "edit_applied"
        assert msg["path"] == "global.contrast"
