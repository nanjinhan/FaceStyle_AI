"""B5(개인별 undo/redo) · B6(기능별 리셋) · 경로 검증 단위 테스트.

DB 없이 PhotoEditState만 직접 검증한다.
"""

import copy

import pytest

from app import models
from app.collab.state import (
    DEFAULT_FACE_PARAMS,
    DEFAULT_GLOBAL_PARAMS,
    InvalidPath,
    PhotoEditState,
    default_for,
    face_id_of,
)

ALICE = "mem_alice"
BOB = "mem_bob"


def new_state() -> PhotoEditState:
    record = models.EditStateRecord(
        photo_id="photo_1",
        version=0,
        global_params=copy.deepcopy(DEFAULT_GLOBAL_PARAMS),
        faces_params={},
    )
    return PhotoEditState(record)


class TestPathValidation:
    def test_알려진_경로는_기본값을_돌려준다(self):
        assert default_for("global.brightness") == 0
        assert default_for("global.filter.strength") == 0
        assert default_for("faces.face_1.skinSmooth") == 0

    @pytest.mark.parametrize("path", [
        "global.evil",              # 없는 파라미터
        "faces.face_1.evil",        # 없는 얼굴 파라미터
        "hack.something",           # 알 수 없는 루트
        "global",                   # 그룹 전체를 가리킴
        "faces.face_1",             # 파라미터 미지정
        "__class__",                # 파이썬 내부 속성 흉내
    ])
    def test_이상한_경로는_거부한다(self, path):
        with pytest.raises(InvalidPath):
            default_for(path)

    def test_이상한_경로로는_편집도_안된다(self):
        state = new_state()
        with pytest.raises(InvalidPath):
            state.apply(ALICE, "global.evil", 50)

    def test_face_id_추출(self):
        assert face_id_of("faces.face_9.jawSlim") == "face_9"
        assert face_id_of("global.brightness") is None


class TestPersonalUndo:
    """명세 3장: "실행취소는 본인 편집 내역 기준으로만 작동, 타인 작업에 영향 없음"."""

    def test_내_undo는_내_편집만_되돌린다(self):
        state = new_state()
        state.apply(ALICE, "global.brightness", 30)
        state.apply(BOB, "global.contrast", 40)

        entry = state.undo(ALICE)

        assert entry is not None
        assert state.global_params["brightness"] == 0   # 내 편집만 취소됨
        assert state.global_params["contrast"] == 40    # 밥 작업은 그대로

    def test_남의_편집을_내가_되돌릴_수_없다(self):
        state = new_state()
        state.apply(BOB, "global.brightness", 30)

        assert state.undo(ALICE) is None                # 앨리스 스택은 비어 있다
        assert state.global_params["brightness"] == 30

    def test_각자_자기_순서대로_되돌린다(self):
        state = new_state()
        state.apply(ALICE, "global.brightness", 10)
        state.apply(BOB, "global.contrast", 20)
        state.apply(ALICE, "global.brightness", 50)

        state.undo(ALICE)
        assert state.global_params["brightness"] == 10  # 앨리스의 두 번째 편집만 취소
        state.undo(ALICE)
        assert state.global_params["brightness"] == 0   # 앨리스의 첫 편집도 취소
        assert state.global_params["contrast"] == 20    # 밥 것은 여전히 그대로

    def test_redo도_개인별이다(self):
        state = new_state()
        state.apply(ALICE, "global.brightness", 30)
        state.undo(ALICE)

        assert state.redo(BOB) is None                  # 밥은 되돌릴 게 없다
        assert state.redo(ALICE) is not None
        assert state.global_params["brightness"] == 30

    def test_새_편집은_본인_redo만_무효화한다(self):
        state = new_state()
        state.apply(ALICE, "global.brightness", 30)
        state.apply(BOB, "global.contrast", 40)
        state.undo(ALICE)
        state.undo(BOB)

        state.apply(ALICE, "global.saturation", 10)     # 앨리스가 새 편집

        assert state.redo(ALICE) is None                # 앨리스 redo는 날아갔지만
        assert state.redo(BOB) is not None              # 밥 redo는 살아 있다

    def test_방을_나가면_이력이_정리된다(self):
        state = new_state()
        state.apply(ALICE, "global.brightness", 30)
        state.forget_member(ALICE)

        assert state.undo(ALICE) is None
        assert state.global_params["brightness"] == 30  # 적용된 값 자체는 남는다


class TestReset:
    """명세 3장: "전체 초기화가 아닌 항목별 리셋"."""

    def test_해당_항목만_원본으로_되돌린다(self):
        state = new_state()
        state.apply(ALICE, "global.brightness", 60)
        state.apply(ALICE, "global.contrast", 40)

        entry = state.reset(ALICE, "global.brightness")

        assert entry is not None
        assert entry["op"] == "reset"
        assert state.global_params["brightness"] == 0
        assert state.global_params["contrast"] == 40    # 다른 항목은 유지

    def test_이미_기본값이면_아무_일도_없다(self):
        state = new_state()
        assert state.reset(ALICE, "global.brightness") is None

    def test_리셋도_undo로_되살릴_수_있다(self):
        state = new_state()
        state.apply(ALICE, "global.brightness", 60)
        state.reset(ALICE, "global.brightness")
        state.undo(ALICE)

        assert state.global_params["brightness"] == 60

    def test_얼굴_파라미터도_리셋된다(self):
        state = new_state()
        state.apply(ALICE, "faces.face_1.jawSlim", 30)
        state.reset(ALICE, "faces.face_1.jawSlim")

        assert state.faces_params["face_1"]["jawSlim"] == DEFAULT_FACE_PARAMS["jawSlim"]


class TestVersioning:
    def test_버전은_단조_증가한다(self):
        state = new_state()
        versions = [
            state.apply(ALICE, "global.brightness", 10)["seq"],
            state.apply(BOB, "global.contrast", 20)["seq"],
            state.undo(ALICE)["seq"],
            state.redo(ALICE)["seq"],
        ]
        assert versions == sorted(versions)
        assert len(set(versions)) == len(versions)
