import copy
from datetime import datetime
from typing import Any, Optional

from sqlalchemy.orm import Session as DBSession
from sqlalchemy.orm.attributes import flag_modified

from .. import models

DEFAULT_GLOBAL_PARAMS: dict[str, Any] = {
    "brightness": 0, "contrast": 0, "saturation": 0,
    "colorTemp": 0, "highlights": 0, "shadows": 0,
    "filter": {"id": None, "strength": 0},
    "crop": {"x": 0, "y": 0, "w": 0, "h": 0, "rotate": 0},
}

DEFAULT_FACE_PARAMS: dict[str, Any] = {
    "skinSmooth": 0, "skinTone": 0, "blemishRemoval": 0,
    "jawSlim": 0, "faceSlim": 0, "cheekbone": 0,
    "eyeScale": 0, "noseHeight": 0, "noseWidth": 0,
    "lipScale": 0, "lipColor": 0,
}

MAX_UNDO_HISTORY = 50


class InvalidPath(ValueError):
    """클라이언트가 보낸 편집 경로가 알려진 파라미터가 아닐 때."""


def _get(container: dict, parts: list[str]) -> Any:
    node = container
    for p in parts:
        node = node[p]
    return node


def _set(container: dict, parts: list[str], value: Any) -> None:
    node = container
    for p in parts[:-1]:
        node = node[p]
    node[parts[-1]] = value


def default_for(path: str) -> Any:
    """경로의 기본값(원본 상태)을 돌려준다. 알 수 없는 경로면 InvalidPath.

    WS는 신뢰할 수 없는 입력을 받으므로 모든 편집 경로가 여기를 먼저 통과해야 한다.
    기능별 리셋(명세 3장 "기능별 리셋")도 이 기본값으로 되돌린다.
    """
    parts = path.split(".")
    if parts[0] == "global":
        node: Any = DEFAULT_GLOBAL_PARAMS
        rest = parts[1:]
    elif parts[0] == "faces":
        if len(parts) < 3:
            raise InvalidPath(f"face path needs a face id and a param: {path}")
        node = DEFAULT_FACE_PARAMS
        rest = parts[2:]
    else:
        raise InvalidPath(f"unknown path root: {path}")

    if not rest:
        raise InvalidPath(f"path points at a whole group, not a param: {path}")
    for p in rest:
        if not isinstance(node, dict) or p not in node:
            raise InvalidPath(f"unknown param: {path}")
        node = node[p]
    return copy.deepcopy(node)


def face_id_of(path: str) -> Optional[str]:
    """`faces.{faceId}.*` 경로면 faceId를, 아니면 None을 돌려준다 (권한 검사용)."""
    parts = path.split(".")
    return parts[1] if parts[0] == "faces" and len(parts) >= 2 else None


class PhotoEditState:
    """사진 한 장의 보정 파라미터 상태.

    버전은 단조 증가하며 마지막 쓰기가 항상 이긴다(LWW, 문서 6장 EditState 모델과 동일).

    undo/redo 스택은 **멤버별로 분리**된다(명세 3장 "개인별 실행취소 — 실행취소/다시하기는
    본인 편집 내역 기준으로만 작동, 타인 작업에 영향 없음"). 각 스택은 최근 50단계로 제한.
    """

    def __init__(self, record: models.EditStateRecord):
        self.photo_id = record.photo_id
        self.version = record.version
        self.global_params = copy.deepcopy(record.global_params)
        self.faces_params = copy.deepcopy(record.faces_params)
        # member_id -> 그 사람의 편집 스택
        self.undo_stacks: dict[str, list[dict]] = {}
        self.redo_stacks: dict[str, list[dict]] = {}

    def as_dict(self) -> dict:
        return {
            "photoId": self.photo_id,
            "version": self.version,
            "global": self.global_params,
            "faces": self.faces_params,
        }

    def _root_and_parts(self, path: str) -> tuple[dict, list[str]]:
        """경로를 실제 파라미터 딕셔너리와 키 목록으로 분해한다.

        호출 전에 `default_for(path)`로 경로가 유효한지 검증되어 있어야 한다.
        """
        parts = path.split(".")
        if parts[0] == "global":
            return self.global_params, parts[1:]
        if parts[0] == "faces":
            face_id = parts[1]
            if face_id not in self.faces_params:
                self.faces_params[face_id] = copy.deepcopy(DEFAULT_FACE_PARAMS)
            return self.faces_params[face_id], parts[2:]
        raise InvalidPath(f"unknown path root: {path}")

    def _record(self, member_id: str, op: str, path: str, old_value: Any, new_value: Any) -> dict:
        """편집 1건을 적용 기록으로 남기고 본인 undo 스택에 쌓는다."""
        self.version += 1
        entry = {
            "seq": self.version, "memberId": member_id, "op": op,
            "path": path, "from": old_value, "to": new_value,
            "ts": datetime.utcnow().isoformat(),
        }
        stack = self.undo_stacks.setdefault(member_id, [])
        stack.append(entry)
        if len(stack) > MAX_UNDO_HISTORY:
            stack.pop(0)
        # 새 편집을 하면 그 사람의 redo 이력만 무효화된다 (타인 것은 그대로).
        self.redo_stacks.pop(member_id, None)
        return entry

    def apply(self, member_id: str, path: str, value: Any) -> dict:
        """파라미터 값 변경. 경로가 유효하지 않으면 InvalidPath."""
        default_for(path)  # 경로 검증 — 알 수 없는 경로면 여기서 막힌다
        root, parts = self._root_and_parts(path)
        old_value = _get(root, parts)
        _set(root, parts, value)
        return self._record(member_id, "set", path, old_value, value)

    def reset(self, member_id: str, path: str) -> Optional[dict]:
        """항목 하나를 원본(기본값)으로 되돌린다 — 명세 3장 "기능별 리셋".

        이미 기본값이면 None (브로드캐스트할 변화 없음).
        """
        default_value = default_for(path)
        root, parts = self._root_and_parts(path)
        old_value = _get(root, parts)
        if old_value == default_value:
            return None
        _set(root, parts, default_value)
        return self._record(member_id, "reset", path, old_value, default_value)

    def undo(self, member_id: str) -> Optional[dict]:
        """본인이 마지막에 한 편집만 되돌린다. 타인 작업에는 영향이 없다."""
        stack = self.undo_stacks.get(member_id)
        if not stack:
            return None
        entry = stack.pop()
        root, parts = self._root_and_parts(entry["path"])
        _set(root, parts, entry["from"])
        self.version += 1
        self.redo_stacks.setdefault(member_id, []).append(entry)
        return {
            "seq": self.version, "memberId": member_id, "op": "undo",
            "path": entry["path"], "from": entry["to"], "to": entry["from"],
            "ts": datetime.utcnow().isoformat(),
        }

    def redo(self, member_id: str) -> Optional[dict]:
        stack = self.redo_stacks.get(member_id)
        if not stack:
            return None
        entry = stack.pop()
        root, parts = self._root_and_parts(entry["path"])
        _set(root, parts, entry["to"])
        self.version += 1
        self.undo_stacks.setdefault(member_id, []).append(entry)
        return {
            "seq": self.version, "memberId": member_id, "op": "redo",
            "path": entry["path"], "from": entry["from"], "to": entry["to"],
            "ts": datetime.utcnow().isoformat(),
        }

    def forget_member(self, member_id: str) -> None:
        """멤버가 방을 떠나면 그 사람의 undo 이력을 정리한다."""
        self.undo_stacks.pop(member_id, None)
        self.redo_stacks.pop(member_id, None)


class EditStateStore:
    """프로세스 메모리 내 편집 상태 캐시 + DB 영속화.

    수평 확장(비기능 요구사항 4장)을 하려면 이 캐시를 Redis 공유 상태로 바꿔야 한다.
    MVP는 세션 서버 단일 프로세스를 가정하므로 인메모리로 충분하다.
    """

    def __init__(self):
        self._states: dict[str, PhotoEditState] = {}

    def get(self, db: DBSession, photo_id: str) -> PhotoEditState:
        if photo_id not in self._states:
            record = (
                db.query(models.EditStateRecord)
                .filter(models.EditStateRecord.photo_id == photo_id)
                .first()
            )
            if record is None:
                record = models.EditStateRecord(
                    photo_id=photo_id,
                    version=0,
                    global_params=copy.deepcopy(DEFAULT_GLOBAL_PARAMS),
                    faces_params={},
                )
                db.add(record)
                db.commit()
                db.refresh(record)
            self._states[photo_id] = PhotoEditState(record)
        return self._states[photo_id]

    def persist(self, db: DBSession, state: PhotoEditState) -> None:
        record = (
            db.query(models.EditStateRecord)
            .filter(models.EditStateRecord.photo_id == state.photo_id)
            .first()
        )
        record.version = state.version
        record.global_params = copy.deepcopy(state.global_params)
        record.faces_params = copy.deepcopy(state.faces_params)
        flag_modified(record, "global_params")
        flag_modified(record, "faces_params")
        record.updated_at = datetime.utcnow()
        db.commit()


edit_state_store = EditStateStore()
