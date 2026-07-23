"""M3 앨범 — 생성·목록·초대참여·업로드·권한 검증 (명세 4장)."""

from conftest import PNG_1X1, make_user


def auth_header(token):
    return {"Authorization": f"Bearer {token}"}


def create_album(client, token, name="제주 여행"):
    res = client.post("/albums", json={"name": name}, headers=auth_header(token))
    assert res.status_code == 201, res.text
    return res.json()


class TestCreateAndList:
    def test_앨범을_만들면_생성자가_방장이다(self, client):
        token, uid = make_user(client, "지우")
        album = create_album(client)  if False else create_album(client, token)
        assert album["ownerUserId"] == uid
        assert album["myRole"] == "owner"
        assert len(album["members"]) == 1
        assert album["members"][0]["role"] == "owner"

    def test_빈_이름은_거부한다(self, client):
        token, _ = make_user(client)
        res = client.post("/albums", json={"name": "  "}, headers=auth_header(token))
        assert res.status_code == 400

    def test_내_앨범_목록에_나온다(self, client):
        token, _ = make_user(client)
        create_album(client, token, "여행1")
        create_album(client, token, "여행2")
        res = client.get("/albums", headers=auth_header(token))
        assert res.status_code == 200
        names = {a["name"] for a in res.json()}
        assert names == {"여행1", "여행2"}

    def test_남의_앨범은_목록에_없다(self, client):
        t1, _ = make_user(client, "지우")
        create_album(client, t1, "지우앨범")
        t2, _ = make_user(client, "수진")
        assert client.get("/albums", headers=auth_header(t2)).json() == []


class TestInviteJoin:
    def test_초대코드로_참여한다(self, client):
        owner, _ = make_user(client, "지우")
        album = create_album(client, owner)
        guest, guid = make_user(client, "수진")

        res = client.post("/albums/join", json={"invite": album["inviteCode"]}, headers=auth_header(guest))
        assert res.status_code == 200
        assert res.json()["myRole"] == "member"
        # 이제 목록에도 보인다
        assert any(a["id"] == album["id"] for a in client.get("/albums", headers=auth_header(guest)).json())

    def test_초대토큰으로도_참여한다(self, client):
        owner, _ = make_user(client, "지우")
        album = create_album(client, owner)
        guest, _ = make_user(client, "민지")
        res = client.post("/albums/join", json={"invite": album["inviteToken"]}, headers=auth_header(guest))
        assert res.status_code == 200

    def test_두_번_참여해도_멤버는_한_번만(self, client):
        owner, _ = make_user(client, "지우")
        album = create_album(client, owner)
        guest, _ = make_user(client, "수진")
        client.post("/albums/join", json={"invite": album["inviteCode"]}, headers=auth_header(guest))
        res = client.post("/albums/join", json={"invite": album["inviteCode"]}, headers=auth_header(guest))
        assert len(res.json()["members"]) == 2

    def test_잘못된_초대는_404(self, client):
        token, _ = make_user(client)
        res = client.post("/albums/join", json={"invite": "NOPE12"}, headers=auth_header(token))
        assert res.status_code == 404


class TestPhotos:
    def _upload(self, client, token, album_id, n=1):
        files = [("files", (f"p{i}.png", PNG_1X1, "image/png")) for i in range(n)]
        return client.post(f"/albums/{album_id}/photos", files=files, headers=auth_header(token))

    def test_멤버는_사진을_올린다(self, client):
        token, _ = make_user(client)
        album = create_album(client, token)
        res = self._upload(client, token, album["id"], n=2)
        assert res.status_code == 201
        assert len(res.json()["photos"]) == 2

    def test_초대받은_멤버도_올린다(self, client):
        owner, _ = make_user(client, "지우")
        album = create_album(client, owner)
        guest, _ = make_user(client, "수진")
        client.post("/albums/join", json={"invite": album["inviteCode"]}, headers=auth_header(guest))
        assert self._upload(client, guest, album["id"]).status_code == 201

    def test_멤버가_아니면_못_올린다(self, client):
        owner, _ = make_user(client, "지우")
        album = create_album(client, owner)
        outsider, _ = make_user(client, "낯선사람")
        assert self._upload(client, outsider, album["id"]).status_code == 403

    def test_목록_커버가_최근_사진이다(self, client):
        token, _ = make_user(client)
        album = create_album(client, token)
        self._upload(client, token, album["id"])
        summary = client.get("/albums", headers=auth_header(token)).json()[0]
        assert summary["photoCount"] == 1
        assert summary["coverUrl"] is not None


class TestEditSession:
    """앨범 사진 편집 진입 — 장수명 세션 생성/재사용 (명세 4장 비동기 보정)."""

    def _album_with_photo(self, client):
        token, uid = make_user(client, "지우")
        album = create_album(client, token)
        files = [("files", ("p.png", PNG_1X1, "image/png"))]
        detail = client.post(f"/albums/{album['id']}/photos", files=files, headers=auth_header(token)).json()
        return token, uid, album, detail["photos"][0]

    def test_편집_세션을_열면_핸들을_받는다(self, client):
        token, _, album, photo = self._album_with_photo(client)
        res = client.post(
            f"/albums/{album['id']}/photos/{photo['id']}/edit-session",
            headers=auth_header(token),
        )
        assert res.status_code == 200, res.text
        body = res.json()
        assert body["sessionId"] and body["photoId"] and body["memberToken"]

    def test_같은_사진은_같은_세션을_재사용한다(self, client):
        token, _, album, photo = self._album_with_photo(client)
        h1 = client.post(f"/albums/{album['id']}/photos/{photo['id']}/edit-session", headers=auth_header(token)).json()
        h2 = client.post(f"/albums/{album['id']}/photos/{photo['id']}/edit-session", headers=auth_header(token)).json()
        assert h1["sessionId"] == h2["sessionId"]
        assert h1["photoId"] == h2["photoId"]

    def test_다른_멤버도_같은_사진_세션에_참여한다(self, client):
        owner, _, album, photo = self._album_with_photo(client)
        guest, _ = make_user(client, "수진")
        client.post("/albums/join", json={"invite": album["inviteCode"]}, headers=auth_header(guest))

        h_owner = client.post(f"/albums/{album['id']}/photos/{photo['id']}/edit-session", headers=auth_header(owner)).json()
        h_guest = client.post(f"/albums/{album['id']}/photos/{photo['id']}/edit-session", headers=auth_header(guest)).json()
        assert h_owner["sessionId"] == h_guest["sessionId"]  # 같은 세션
        assert h_owner["memberToken"] != h_guest["memberToken"]  # 각자 다른 멤버 토큰

    def test_멤버가_아니면_편집_세션을_못_연다(self, client):
        _owner, _, album, photo = self._album_with_photo(client)
        outsider, _ = make_user(client, "낯선사람")
        res = client.post(
            f"/albums/{album['id']}/photos/{photo['id']}/edit-session",
            headers=auth_header(outsider),
        )
        assert res.status_code == 403


class TestMembershipRules:
    def test_멤버가_아니면_상세를_못_본다(self, client):
        owner, _ = make_user(client, "지우")
        album = create_album(client, owner)
        outsider, _ = make_user(client, "낯선사람")
        assert client.get(f"/albums/{album['id']}", headers=auth_header(outsider)).status_code == 403

    def test_멤버는_나갈_수_있고_방장은_못_나간다(self, client):
        owner, _ = make_user(client, "지우")
        album = create_album(client, owner)
        guest, _ = make_user(client, "수진")
        client.post("/albums/join", json={"invite": album["inviteCode"]}, headers=auth_header(guest))

        assert client.post(f"/albums/{album['id']}/leave", headers=auth_header(guest)).status_code == 204
        assert client.post(f"/albums/{album['id']}/leave", headers=auth_header(owner)).status_code == 400

    def test_방장만_삭제한다(self, client):
        owner, _ = make_user(client, "지우")
        album = create_album(client, owner)
        guest, _ = make_user(client, "수진")
        client.post("/albums/join", json={"invite": album["inviteCode"]}, headers=auth_header(guest))

        assert client.delete(f"/albums/{album['id']}", headers=auth_header(guest)).status_code == 403
        assert client.delete(f"/albums/{album['id']}", headers=auth_header(owner)).status_code == 204
        # 삭제 후 목록에서 사라진다
        assert client.get("/albums", headers=auth_header(owner)).json() == []
