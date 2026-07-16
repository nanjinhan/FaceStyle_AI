from pathlib import Path


def detect_faces(image_path: Path) -> list[tuple[int, int, int, int]]:
    """호스트 업로드 시 얼굴 위치 미리보기(FACE-01)를 서버에서 1회 계산한다.

    비기능 요구사항(프라이버시: "얼굴 인식은 온디바이스 처리 원칙")에 따라 실시간 편집 중
    얼굴 인식은 클라이언트 MediaPipe가 담당하고, 이 함수는 업로드 직후 인물 목록/썸네일을
    보여주기 위한 보조 기능이다. opencv가 설치되어 있지 않으면 빈 목록을 반환하며,
    이 경우 클라이언트가 얼굴 좌표를 별도로 보고하는 플로우로 대체할 수 있다.
    """
    try:
        import cv2
    except ImportError:
        return []

    classifier = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
    image = cv2.imread(str(image_path))
    if image is None:
        return []

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    boxes = classifier.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(60, 60))
    return [(int(x), int(y), int(w), int(h)) for x, y, w, h in boxes]
