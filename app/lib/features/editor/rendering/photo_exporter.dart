import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'face_warp.dart';
import 'photo_filter.dart';

/// 현재 보정 상태(전역 색보정 + 얼굴 워핑 + 피부 스무딩)를 원본 해상도로 한 번에
/// 렌더링해 PNG 바이트로 만든다 (명세 3장 "개인 저장" / 아키텍처 "최종 렌더링 일관성").
///
/// 편집 중 화면은 축소 표시지만, 저장은 원본 크기로 다시 렌더링하므로 화질 손실이 없다.
abstract final class PhotoExporter {
  /// [url] 원본 이미지를 받아 보정을 적용한 PNG 바이트를 돌려준다.
  static Future<Uint8List> renderPng({
    required ui.Image image,
    required Size imageSize,
    required List<FaceWarp> warps,
    required List<double> colorMatrix,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final needsColor = !_isIdentity(colorMatrix);
    if (needsColor) {
      canvas.saveLayer(
        Offset.zero & imageSize,
        Paint()..colorFilter = ColorFilter.matrix(colorMatrix),
      );
    }
    // FaceWarpPainter 가 size=imageSize 기준으로 워핑+피부까지 그린다.
    FaceWarpPainter(image, imageSize, warps).paint(canvas, imageSize);
    if (needsColor) canvas.restore();

    final picture = recorder.endRecording();
    final out = await picture.toImage(imageSize.width.round(), imageSize.height.round());
    final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  static bool _isIdentity(List<double> m) {
    const id = PhotoFilter.identity;
    for (var i = 0; i < id.length; i++) {
      if ((m[i] - id[i]).abs() > 0.0001) return false;
    }
    return true;
  }
}
