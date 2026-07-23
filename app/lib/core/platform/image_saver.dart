/// 렌더링한 이미지 바이트를 기기에 저장한다.
///
/// 플랫폼별 구현을 조건부 import 로 고른다:
///  - 웹: 브라우저 다운로드 (image_saver_web.dart)
///  - 그 외(모바일/데스크톱): 아직 미구현 (image_saver_io.dart) — 갤러리 저장은 M4에서
library;

export 'image_saver_io.dart' if (dart.library.js_interop) 'image_saver_web.dart';
