# FaceStyle

**친구들이 단체사진 한 장에 동시 접속해서 각자 자기 얼굴만 보정하는 앱.**

보정본을 저장하고 카톡으로 돌리며 재보정하면 JPEG 재압축이 쌓여 화질이 계속 나빠진다.
이 앱은 픽셀을 주고받지 않는다 — 서버엔 원본 1장만 있고 오가는 건 파라미터 JSON뿐이라,
몇 번을 고쳐도 화질 손실이 없고 여러 명이 동시에 만져도 끊기지 않는다.

```
app/       Flutter 앱 (iOS/Android)
backend/   FastAPI 서버 (REST + WebSocket)
docs/      명세·설계·진행 현황
```

## 시작하기

**👉 [docs/이어서-작업하기.md](docs/이어서-작업하기.md) 를 먼저 읽으세요.**
어디까지 됐고 어디서부터 하면 되는지, 환경 세팅과 인계 프롬프트까지 이 문서 하나에 있습니다.

| 문서 | 내용 |
|---|---|
| [이어서-작업하기.md](docs/이어서-작업하기.md) | **진행 현황 · 다음 할 일 · 막힌 것 · 환경 세팅** |
| [기능명세서.md](docs/기능명세서.md) | 페이지별 기능 명세 (회원/홈/실시간 방/앨범) |
| [아키텍처.md](docs/아키텍처.md) | 설계 원칙, WS 프로토콜, 권한 규칙 |
| [로드맵.md](docs/로드맵.md) | 마일스톤 M1~M4, 갭 분석 |
| [출시-준비물.md](docs/출시-준비물.md) | 스토어 등록·소셜 로그인 키·비용 |

## 빠른 실행

```bash
# 백엔드 (http://localhost:8000)
cd backend && python -m venv .venv
.venv/Scripts/python.exe -m pip install -r requirements.txt
.venv/Scripts/python.exe -m uvicorn app.main:app --reload

# 앱
cd app && flutter pub get && flutter run
```

## 테스트

```bash
cd backend && .venv/Scripts/python.exe -m pytest tests/ -q   # 63개
cd app && flutter test                                        # 28개
```
