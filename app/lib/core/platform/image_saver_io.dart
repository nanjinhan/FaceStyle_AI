import 'dart:typed_data';

/// 모바일/데스크톱 갤러리 저장 — 아직 미구현.
/// 안드로이드/ iOS는 갤러리 저장 플러그인(image_gallery_saver 등) 연동이 필요하며 M4에서 추가한다.
Future<void> saveImageBytes(Uint8List bytes, String filename) async {
  throw UnsupportedError('이 플랫폼의 저장은 아직 준비 중이에요');
}
