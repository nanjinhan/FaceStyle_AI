import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../room/domain/session_models.dart';

/// 한 얼굴에 적용할 워핑 입력 — 랜드마크 + 그 얼굴의 파라미터.
class FaceWarp {
  const FaceWarp({required this.landmarks, required this.params});

  final FaceLandmarks landmarks;

  /// faces.{face}.* 파라미터 값 (-100..100). eyeScale / lipScale / noseWidth / faceSlim 등.
  final double Function(String key) params;

  bool get hasAny =>
      params('eyeScale') != 0 ||
      params('lipScale') != 0 ||
      params('noseWidth') != 0 ||
      params('noseHeight') != 0 ||
      params('faceSlim') != 0 ||
      params('jawSlim') != 0 ||
      params('cheekbone') != 0;
}

/// 얼굴 파라미터를 실제 픽셀 변형으로 렌더링한다 (A7 확장 / M4).
///
/// 삼각형 메시(drawVertices)를 이미지 위에 깔고, 랜드마크 주변 정점을 밀어 국소적으로
/// 확대/축소한다. 정점 위치는 움직이되 텍스처 좌표(UV)는 원본에 고정하므로, 그 부분의
/// 픽셀이 늘어나거나 줄어든다. 셰이더 없이 동작해 웹/모바일 모두 지원한다.
///
/// 5점 랜드마크(양눈·코·입양끝) 기반이라 눈 크기·입술·코 너비·얼굴 축소를 다룬다.
/// 턱선·광대 등 윤곽 기반 보정의 정밀도는 M4에서 MediaPipe 468점으로 확장한다.
class FaceWarpImage extends StatefulWidget {
  const FaceWarpImage({
    super.key,
    required this.url,
    required this.imageSize,
    required this.warps,
    this.errorBuilder,
  });

  final String url;
  final Size imageSize;
  final List<FaceWarp> warps;
  final WidgetBuilder? errorBuilder;

  @override
  State<FaceWarpImage> createState() => _FaceWarpImageState();
}

class _FaceWarpImageState extends State<FaceWarpImage> {
  ui.Image? _image;
  Object? _error;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(FaceWarpImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _resolve();
  }

  void _resolve() {
    final provider = NetworkImage(widget.url);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _detach();
    _stream = stream;
    _listener = ImageStreamListener(
      (info, _) => setState(() => _image = info.image),
      onError: (e, _) => setState(() => _error = e),
    );
    stream.addListener(_listener!);
  }

  void _detach() {
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.errorBuilder?.call(context) ?? const SizedBox.shrink();
    }
    final image = _image;
    if (image == null) return const Center(child: CircularProgressIndicator());
    // SizedBox.expand 로 부모 크기를 꽉 채워 페인터에 유효한 size를 준다.
    return SizedBox.expand(
      child: CustomPaint(
        painter: FaceWarpPainter(image, widget.imageSize, widget.warps),
      ),
    );
  }
}

class FaceWarpPainter extends CustomPainter {
  FaceWarpPainter(this.image, this.imageSize, this.warps);

  final ui.Image image;
  final Size imageSize;
  final List<FaceWarp> warps;

  // 메시 격자 해상도 (셀 개수). 얼굴이 작을 수 있어 촘촘해야 눈 같은 작은 특징이 변형된다.
  static const _cols = 100;
  static const _rows = 100;

  @override
  void paint(Canvas canvas, Size size) {
    // BoxFit.contain 으로 그려질 이미지 사각형.
    final fitted = applyBoxFit(BoxFit.contain, imageSize, size);
    final dest = fitted.destination;
    final rect = Alignment.center.inscribe(dest, Offset.zero & size);
    final sx = dest.width / imageSize.width;
    final sy = dest.height / imageSize.height;

    Offset toCanvas(Offset img) => Offset(rect.left + img.dx * sx, rect.top + img.dy * sy);

    final active = warps.where((w) => w.hasAny).toList();

    // 워핑이 없으면 이미지를 그대로 그린다 (원본 화질).
    if (active.isEmpty) {
      paintImage(
        canvas: canvas,
        rect: rect,
        image: image,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.high,
      );
      return;
    }

    final positions = <Offset>[];
    final texCoords = <Offset>[];
    for (var r = 0; r <= _rows; r++) {
      for (var c = 0; c <= _cols; c++) {
        final imgPt = Offset(
          imageSize.width * c / _cols,
          imageSize.height * r / _rows,
        );
        final warped = _warpPoint(imgPt, active);
        texCoords.add(imgPt); // UV = 원본 이미지 픽셀 좌표
        positions.add(toCanvas(warped)); // 위치 = 변형 후 → 캔버스
      }
    }

    final indices = <int>[];
    int idx(int r, int c) => r * (_cols + 1) + c;
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        indices.addAll([idx(r, c), idx(r, c + 1), idx(r + 1, c)]);
        indices.addAll([idx(r, c + 1), idx(r + 1, c + 1), idx(r + 1, c)]);
      }
    }

    final vertices = ui.Vertices(
      VertexMode.triangles,
      positions,
      textureCoordinates: texCoords,
      indices: indices,
    );
    // 텍스처 = 이미지. UV가 이미지 픽셀 좌표이므로 ImageShader는 단위행렬.
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..shader = ImageShader(image, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage);
    canvas.drawVertices(vertices, BlendMode.srcOver, paint);
  }

  /// 이미지 픽셀 좌표 한 점에 모든 얼굴의 워핑을 누적 적용한다.
  Offset _warpPoint(Offset p, List<FaceWarp> active) {
    var out = p;
    for (final w in active) {
      out = _applyFace(out, w);
    }
    return out;
  }

  Offset _applyFace(Offset p, FaceWarp w) {
    final lm = w.landmarks;
    final eyeDist = lm.interocular.clamp(1.0, double.infinity);
    var out = p;

    // 눈 크기: 각 눈 중심을 축으로 국소 확대/축소.
    final eye = w.params('eyeScale');
    if (eye != 0) {
      final s = eye / 100 * 0.8; // ±100 → ±0.8배
      final radius = eyeDist * 0.7;
      out = _bulge(out, lm.rEye, radius, s);
      out = _bulge(out, lm.lEye, radius, s);
    }

    // 입술 크기: 입 중심 확대/축소.
    final lip = w.params('lipScale');
    if (lip != 0) {
      final mouthW = (lm.mouthL - lm.mouthR).distance.clamp(1.0, double.infinity);
      out = _bulge(out, lm.mouthCenter, mouthW * 0.9, lip / 100 * 0.5);
    }

    // 코 너비: 코를 축으로 가로 방향만 축소/확대.
    final noseW = w.params('noseWidth');
    if (noseW != 0) {
      out = _bulgeAxis(out, lm.nose, eyeDist * 0.5, noseW / 100 * 0.4, horizontal: true);
    }
    // 코 높이: 코를 축으로 세로 방향.
    final noseH = w.params('noseHeight');
    if (noseH != 0) {
      out = _bulgeAxis(out, lm.nose, eyeDist * 0.5, noseH / 100 * 0.4, horizontal: false);
    }

    // 얼굴 축소: 얼굴 세로축(코 x) 쪽으로 좌우를 당긴다.
    final slim = w.params('faceSlim');
    if (slim != 0) {
      out = _slimFace(out, lm, slim / 100 * 0.18);
    }
    return out;
  }

  /// center를 중심으로 반경 radius 안에서 방사형 확대(s>0)/축소(s<0).
  Offset _bulge(Offset p, Offset center, double radius, double s) {
    final d = (p - center).distance;
    if (d >= radius) return p;
    final t = 1 - d / radius; // 중심 1 → 가장자리 0
    final falloff = t * t * (3 - 2 * t); // smoothstep
    return p + (p - center) * (s * falloff);
  }

  /// 한 축(가로/세로)으로만 국소 확대/축소.
  Offset _bulgeAxis(Offset p, Offset center, double radius, double s, {required bool horizontal}) {
    final d = (p - center).distance;
    if (d >= radius) return p;
    final t = 1 - d / radius;
    final falloff = t * t * (3 - 2 * t);
    if (horizontal) {
      return Offset(p.dx + (p.dx - center.dx) * s * falloff, p.dy);
    }
    return Offset(p.dx, p.dy + (p.dy - center.dy) * s * falloff);
  }

  /// 얼굴 좌우를 세로 중심축으로 당겨 갸름하게 (s>0).
  Offset _slimFace(Offset p, FaceLandmarks lm, double s) {
    final axisX = lm.nose.dx;
    final eyeDist = lm.interocular;
    // 얼굴 세로 범위(눈~입 언저리) 안에서만, 축에서 멀수록 강하게 당긴다.
    final top = lm.rEye.dy - eyeDist * 0.6;
    final bottom = lm.mouthCenter.dy + eyeDist * 0.8;
    if (p.dy < top || p.dy > bottom) return p;
    final vy = 1 - ((p.dy - (top + bottom) / 2).abs() / ((bottom - top) / 2)).clamp(0.0, 1.0);
    final falloff = vy * vy * (3 - 2 * vy);
    final maxSpan = eyeDist * 2.2;
    final dx = (p.dx - axisX).clamp(-maxSpan, maxSpan);
    return Offset(p.dx - dx * s * falloff, p.dy);
  }

  @override
  bool shouldRepaint(FaceWarpPainter old) =>
      old.image != image || old.imageSize != imageSize || !identical(old.warps, warps);
}
