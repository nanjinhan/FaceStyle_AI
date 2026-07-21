import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:facestyle/features/editor/rendering/face_warp.dart';
import 'package:facestyle/features/room/domain/session_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 얼굴 워핑 육안 확인.
///
/// 실제 테스트 사진 + 실제 YuNet 랜드마크로 눈 크기/얼굴 축소 등을 적용해 PNG로 뽑는다.
/// 실행: flutter test test/face_warp_visual_test.dart
/// 결과: build/face_warp_preview.png (원본 | 눈+100 | 눈-60 | 얼굴축소+100 | 입술+100)
void main() {
  const imgW = 800.0, imgH = 1200.0;
  // 이미지 예시2.jpg 앞쪽 얼굴의 YuNet 5점 랜드마크 (backend detect 로 확인).
  final landmarks = FaceLandmarks(
    rEye: const Offset(436, 552),
    lEye: const Offset(483, 558),
    nose: const Offset(460, 579),
    mouthR: const Offset(434, 599),
    mouthL: const Offset(471, 603),
  );
  FaceWarp warp(Map<String, double> p) =>
      FaceWarp(landmarks: landmarks, params: (k) => p[k] ?? 0);

  testWidgets('워핑 결과를 PNG로 출력한다', (tester) async {
    final src = File('../backend/test_photos/이미지 예시2.jpg');
    if (!src.existsSync()) return; // 사진 없으면 스킵

    await tester.runAsync(() async {
      final image = await _decode(await src.readAsBytes());

      final cases = <(String, List<FaceWarp>)>[
        ('원본', const []),
        ('눈 +100', [warp({'eyeScale': 100})]),
        ('눈 -60', [warp({'eyeScale': -60})]),
      ];

      // 눈 영역만 바짝 확대 (변형이 명확히 보이도록). 두 눈을 감싸는 박스.
      final cx = (landmarks.rEye.dx + landmarks.lEye.dx) / 2;
      final cy = (landmarks.rEye.dy + landmarks.lEye.dy) / 2;
      const cropW = 110.0, cropH = 70.0;
      final cropRect = Rect.fromCenter(center: Offset(cx, cy), width: cropW, height: cropH);
      const scale = 4.0; // 4배 확대 출력

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      for (var i = 0; i < cases.length; i++) {
        final warped = await _renderWarp(image, const Size(imgW, imgH), cases[i].$2);
        final dst = Rect.fromLTWH(i * cropW * scale, 0, cropW * scale, cropH * scale);
        canvas.drawImageRect(warped, cropRect, dst, Paint());
      }
      final pic = recorder.endRecording();
      final out = await pic.toImage((cropW * scale * cases.length).toInt(), (cropH * scale).toInt());
      final png = await out.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/face_warp_preview.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
      // ignore: avoid_print
      print('→ ${file.absolute.path}');
      expect(file.existsSync(), isTrue);
    });
  });
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

/// FaceWarpPainter 로 워핑 결과를 원본 크기 이미지로 렌더한다.
Future<ui.Image> _renderWarp(ui.Image image, Size imageSize, List<FaceWarp> warps) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  FaceWarpPainter(image, imageSize, warps).paint(canvas, imageSize);
  final pic = recorder.endRecording();
  return pic.toImage(imageSize.width.toInt(), imageSize.height.toInt());
}
