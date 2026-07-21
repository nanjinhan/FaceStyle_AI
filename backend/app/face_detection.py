from pathlib import Path
from typing import Optional, TypedDict

_YUNET_MODEL = Path(__file__).parent / "models" / "face_detection_yunet_2023mar.onnx"


class DetectedFace(TypedDict):
    bbox: tuple[int, int, int, int]
    # 5점 랜드마크(이미지 픽셀 좌표). YuNet일 때만 채워지고 Haar면 None.
    #   {"rEye":[x,y], "lEye":[x,y], "nose":[x,y], "mouthR":[x,y], "mouthL":[x,y]}
    landmarks: Optional[dict[str, list[int]]]


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


def _detect_yunet(cv2, image) -> list[DetectedFace]:
    """YuNet(딥러닝 기반) 검출기. bbox + 5점 랜드마크를 돌려준다.

    YuNet 출력 한 행: [x, y, w, h, rEyeX, rEyeY, lEyeX, lEyeY, noseX, noseY,
                      mouthRX, mouthRY, mouthLX, mouthLY, score]
    """
    h, w = image.shape[:2]
    detector = cv2.FaceDetectorYN.create(str(_YUNET_MODEL), "", (w, h), score_threshold=0.6)
    detector.setInputSize((w, h))
    _, faces = detector.detect(image)
    if faces is None:
        return []
    out: list[DetectedFace] = []
    for f in faces:
        v = [int(round(x)) for x in f[:14]]
        x, y = max(0, v[0]), max(0, v[1])
        out.append({
            "bbox": (x, y, v[2], v[3]),
            "landmarks": {
                "rEye": [v[4], v[5]],
                "lEye": [v[6], v[7]],
                "nose": [v[8], v[9]],
                "mouthR": [v[10], v[11]],
                "mouthL": [v[12], v[13]],
            },
        })
    return out


def _detect_haar(cv2, image) -> list[DetectedFace]:
    """YuNet 모델이 없을 때의 폴백. bbox만 (랜드마크 없음)."""
    classifier = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    boxes = classifier.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(60, 60))
    return [{"bbox": (int(x), int(y), int(w), int(h)), "landmarks": None} for x, y, w, h in boxes]


def detect_faces(image_path: Path) -> list[DetectedFace]:
    """업로드된 사진에서 얼굴 위치(bbox)와 5점 랜드마크를 찾는다 (FACE-01).

    bbox는 각 인물의 클레임 대상("이게 나예요")이 되고, 랜드마크(양눈·코·입양끝)는
    앱의 얼굴 워핑(눈 크기·코·입 보정)의 기준점이 된다.

    검출기 우선순위:
      1. YuNet ONNX (app/models/) — 딥러닝 기반, bbox + 5점 랜드마크
      2. Haar cascade — YuNet 모델이 없을 때 폴백 (bbox만)
    opencv 미설치 시 빈 목록을 반환한다.

    턱선·눈썹 등 정밀 랜드마크(68/468점)는 M4에서 온디바이스 MediaPipe로 확장한다.
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
