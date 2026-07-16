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


class PhotoEditState:
    """사진 한 장의 보정 파라미터 상태.

    버전은 단조 증가하며 마지막 쓰기가 항상 이긴다(LWW, 문서 6장 EditState 모델과 동일).
    undo/redo 스택은 최근 50단계로 제한한다(COLLAB-06).
    """

    def __init__(self, record: models.EditStateRecord):
        self.photo_id = record.photo_id
        self.version = record.version
        self.global_params = copy.deepcopy(record.global_params)
        self.faces_params = copy.deepcopy(record.faces_params)
        self.undo_stack: list[dict] = []
        self.redo_stack: list[dict] = []

    def as_dict(self) -> dict:
        return {
            "photoId": self.photo_id,
            "version": self.version,
            "global": self.global_params,
            "faces": self.faces_params,
        }

    def _root_and_parts(self, path: str) -> tuple[dict, list[str]]:
        parts = path.split(".")
        if parts[0] == "global":
            return self.global_params, parts[1:]
        if parts[0] == "faces":
            face_id = parts[1]
            if face_id not in self.faces_params:
                self.faces_params[face_id] = copy.deepcopy(DEFAULT_FACE_PARAMS)
            return self.faces_params[face_id], parts[2:]
        raise ValueError(f"unknown path root: {path}")

    def apply(self, member_id: str, path: str, value: Any) -> dict:
        root, parts = self._root_and_parts(path)
        old_value = _get(root, parts)
        _set(root, parts, value)
        self.version += 1
        entry = {
            "seq": self.version, "memberId": member_id, "op": "set",
            "path": path, "from": old_value, "to": value,
            "ts": datetime.utcnow().isoformat(),
        }
        self.undo_stack.append(entry)
        if len(self.undo_stack) > MAX_UNDO_HISTORY:
            self.undo_stack.pop(0)
        self.redo_stack.clear()
        return entry

    def undo(self, member_id: str) -> Optional[dict]:
        if not self.undo_stack:
            return None
        entry = self.undo_stack.pop()
        root, parts = self._root_and_parts(entry["path"])
        _set(root, parts, entry["from"])
        self.version += 1
        self.redo_stack.append(entry)
        return {
            "seq": self.version, "memberId": member_id, "op": "undo",
            "path": entry["path"], "from": entry["to"], "to": entry["from"],
            "ts": datetime.utcnow().isoformat(),
        }

    def redo(self, member_id: str) -> Optional[dict]:
        if not self.redo_stack:
            return None
        entry = self.redo_stack.pop()
        root, parts = self._root_and_parts(entry["path"])
        _set(root, parts, entry["to"])
        self.version += 1
        self.undo_stack.append(entry)
        return {
            "seq": self.version, "memberId": member_id, "op": "redo",
            "path": entry["path"], "from": entry["from"], "to": entry["to"],
            "ts": datetime.utcnow().isoformat(),
        }


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
