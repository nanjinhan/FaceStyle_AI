# TogetherSnap Backend (MVP)

`공동 보정 앱 기능 명세서 v0.1`의 P0 항목을 구현한 FastAPI 백엔드 스켈레톤입니다.

## 실행

```bash
cd backend
python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt
./.venv/bin/uvicorn app.main:app --reload --port 8000
```

기본값은 SQLite(`togethersnap.db`) + 로컬 디스크 스토리지(`./storage`)입니다.
`DATABASE_URL`, `JWT_SECRET`, `STORAGE_DIR` 환경변수로 바꿀 수 있습니다.
**`JWT_SECRET`은 배포 전 반드시 32바이트 이상 무작위 값으로 교체하세요.**

문서 확인: `http://localhost:8000/docs`

## 구현 범위 (스펙 ID 매핑)

| 영역 | 구현 위치 | 스펙 ID |
|---|---|---|
| 소셜 로그인(스텁) / 내 정보 | `routers/auth.py` | AUTH-01 |
| 게스트 참여(닉네임만) | `routers/sessions.py: join_session` | AUTH-02 |
| 사진 업로드 + 세션 자동 생성 | `routers/sessions.py: create_session` | SES-01, SES-02 |
| 초대 링크/코드 | `models.EditSession.invite_token/invite_code` | SES-04 |
| 참여 인원 제한(4인) | `join_session`의 `max_members` 체크 | SES-05 |
| 세션 만료(72h) | `EditSession.expires_at`, `join_session`에서 검사 | SES-06 |
| 잠금/강퇴 | `toggle_lock`, `kick_member` | SES-07 |
| 얼굴 자동 인식(서버 보조) | `face_detection.py` | FACE-01 |
| 얼굴 클레임 | `routers/faces.py` | FACE-02 |
| 보정 파라미터(전역/얼굴별) | `collab/state.py`의 `DEFAULT_GLOBAL_PARAMS`/`DEFAULT_FACE_PARAMS` | EDIT-01~04, FACE-03~05 |
| 실시간 동기화 / 프레즌스 / 소프트 락 | `routers/ws.py`, `collab/manager.py` | COLLAB-01~04, 08 |
| 서버 공용 Undo/Redo(50단계) | `collab/state.py: PhotoEditState.undo/redo` | COLLAB-06 |
| 저장 확정 + 전원 배포 | `sessions.py: save_photo_endpoint` | OUT-01, OUT-02, OUT-03 |

## 의도적으로 스텁/미구현으로 남긴 부분

- **소셜 로그인 토큰 검증**: 카카오/Apple/Google 서버와의 실제 OAuth 검증 연동은 하지 않았습니다.
  클라이언트가 이미 검증된 `provider_id`를 보낸다고 가정합니다.
- **풀해상도 렌더링**: 문서 5장 설계 원칙대로 실제 픽셀 합성(GPU 셰이더/워핑)은
  클라이언트(온디바이스) 또는 별도 렌더 서버의 몫입니다. `/sessions/{id}/photos/{id}/save`는
  렌더링 결과 배포·기록만 담당합니다.
- **얼굴 인식**: 개인정보 보호 원칙(온디바이스 처리)에 따라 서버 검출(`face_detection.py`)은
  OpenCV가 설치된 경우에만 동작하는 업로드 시점의 보조 미리보기이며, 필수 의존성이 아닙니다.
- **수평 확장**: 실시간 상태(`collab/state.py`, `collab/manager.py`)는 단일 프로세스 인메모리입니다.
  다중 인스턴스로 확장하려면 Redis pub/sub + 세션 단위 sticky 라우팅으로 교체해야 합니다.
- P1/P2 항목(다중 사진 세션, 버전 스냅샷, 채팅/음성, 메이크업/체형 보정, 결제)은 포함하지 않았습니다.

## WebSocket 프로토콜

`GET/WS /ws/sessions/{session_id}?token={memberToken}`

클라이언트 → 서버:
```jsonc
{"type": "edit", "photoId": "photo_x", "path": "global.brightness", "value": 20}
{"type": "edit", "photoId": "photo_x", "path": "faces.face_0.skinSmooth", "value": 40}
{"type": "undo", "photoId": "photo_x"}
{"type": "redo", "photoId": "photo_x"}
{"type": "presence", "tool": "filter", "region": null}
{"type": "lock_param", "path": "global.filter.strength"}
{"type": "unlock_param", "path": "global.filter.strength"}
{"type": "reaction", "emoji": "😍"}
```

서버 → 클라이언트: `state_sync`(접속 직후 1회), `edit_applied`, `presence_update`,
`param_locked`/`param_unlocked`, `face_claimed`/`face_released`, `member_kicked`,
`export_ready`, `reaction`.
