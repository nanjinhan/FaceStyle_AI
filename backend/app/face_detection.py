from pathlib import Path

_YUNET_MODEL = Path(__file__).parent / "models" / "face_detection_yunet_2023mar.onnx"


def _read_image(image_path: Path):
    """이미지를 BGR 배열로 읽는다. 실패 시 None.

    cv2.imread 는 윈도우에서 비ASCII(한글 등) 경로를 못 읽으므로, 바이트로 직접 읽고
    imdecode 해서 경로 인코딩 문제를 피한다.
    """
    import cv2
    import numpy as np

    try:
        buffer = np.frombuffer(image_path.read_bytes(), dtype=np.uint8)
    except OSError:
        return None
    return cv2.imdecode(buffer, cv2.IMREAD_COLOR)


def _detect_yunet(cv2, image) -> list[tuple[int, int, int, int]]:
    """YuNet(딥러닝 기반) 검출기. Haar보다 기울어진 얼굴·측면에 훨씬 강하다."""
    h, w = image.shape[:2]
    detector = cv2.FaceDetectorYN.create(str(_YUNET_MODEL), "", (w, h), score_threshold=0.6)
    detector.setInputSize((w, h))
    _, faces = detector.detect(image)
    if faces is None:
        return []
    boxes = []
    for f in faces:
        x, y, fw, fh = (int(v) for v in f[:4])
        # 이미지 경계 밖으로 나간 좌표를 잘라낸다.
        x, y = max(0, x), max(0, y)
        boxes.append((x, y, fw, fh))
    return boxes


def _detect_haar(cv2, image) -> list[tuple[int, int, int, int]]:
    """YuNet 모델이 없을 때의 폴백. 정확도는 낮지만 정면 얼굴은 잡는다."""
    classifier = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    boxes = classifier.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(60, 60))
    return [(int(x), int(y), int(w), int(h)) for x, y, w, h in boxes]


def detect_faces(image_path: Path) -> list[tuple[int, int, int, int]]:
    """업로드된 사진에서 얼굴 위치(bbox)를 찾는다 (FACE-01).

    찾은 bbox는 각 인물의 클레임 대상이 된다("이게 나예요"). 검출 순서는 얼굴 index로 쓰인다.

    검출기 우선순위:
      1. YuNet ONNX (app/models/) — 딥러닝 기반, 정확도 높음
      2. Haar cascade — YuNet 모델이 없을 때 폴백
    opencv 미설치 시 빈 목록을 반환한다(클라이언트가 좌표를 직접 보고하는 플로우로 대체 가능).

    정밀 검출(눈코입/윤곽 랜드마크)은 실시간 편집 중 온디바이스에서 처리하며,
    M4에서 MediaPipe Face Mesh로 확장한다(프라이버시: 얼굴 인식 온디바이스 원칙).
    """
    try:
        import cv2  # noqa: F401
    except ImportError:
        return []

    image = _read_image(image_path)
    if image is None:
        return []

    if _YUNET_MODEL.exists() and hasattr(cv2, "FaceDetectorYN"):
        try:
            return _detect_yunet(cv2, image)
        except cv2.error:
            pass  # 모델 손상 등 — Haar로 폴백
    return _detect_haar(cv2, image)
