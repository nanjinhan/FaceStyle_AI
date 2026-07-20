import 'dart:io';
import 'dart:ui' as ui;

import 'package:facestyle/features/editor/rendering/photo_filter.dart';
import 'package:facestyle/features/room/domain/session_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// A7 렌더링 육안 확인용. 보정별 결과를 한 장의 PNG로 뽑는다.
///
/// 실행: flutter test test/photo_filter_visual_test.dart
/// 결과: build/filter_preview.png  (위에서부터 아래 `_rows` 순서)
///
/// 실기기 없이 보정이 실제로 먹는지 확인하기 위한 것이며, 단위 검증은
/// `photo_filter_test.dart`가 담당한다.
void main() {
  const rows = <(String, Map<String, dynamic>)>[
    ('원본', {}),
    ('밝기 +60', {'brightness': 60}),
    ('밝기 -60', {'brightness': -60}),
    ('대비 +60', {'contrast': 60}),
    ('대비 -60', {'contrast': -60}),
    ('채도 -100 (흑백)', {'saturation': -100}),
    ('채도 +80', {'saturation': 80}),
    ('색온도 +80 (따뜻)', {'colorTemp': 80}),
    ('색온도 -80 (차갑)', {'colorTemp': -80}),
    ('그림자 +80', {'shadows': 80}),
    ('하이라이트 +80', {'highlights': 80}),
    ('합성: 밝기30·대비20·채도40·색온도25', {
      'brightness': 30,
      'contrast': 20,
      'saturation': 40,
      'colorTemp': 25,
    }),
  ];

  testWidgets('보정 결과를 PNG로 출력한다', (tester) async {
    final key = GlobalKey();
    tester.view.physicalSize = const Size(720, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: const Color(0xFF202020),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (_, params) in rows)
                  Padding(
                    padding: const EdgeInsets.all(2),
                    child: _FilteredChart(params: params),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/filter_preview.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      // ignore: avoid_print
      print('→ ${file.absolute.path}');
    });
  });
}

/// 보정 효과가 눈에 잘 보이도록 만든 테스트 차트.
/// 흑→백 그라데이션(밝기·대비·하이라이트·그림자 확인) + 색상 패치(채도·색온도 확인).
class _FilteredChart extends StatelessWidget {
  const _FilteredChart({required this.params});

  final Map<String, dynamic> params;

  static const _patches = <Color>[
    Color(0xFFE0AC8B), // 살구빛 피부톤
    Color(0xFFC0392B), // 빨강
    Color(0xFF27AE60), // 초록
    Color(0xFF2980B9), // 파랑
    Color(0xFF8E44AD), // 보라
  ];

  @override
  Widget build(BuildContext context) {
    final editState = EditState(
      photoId: 'preview',
      version: 1,
      global: <String, dynamic>{
        'brightness': 0,
        'contrast': 0,
        'saturation': 0,
        'colorTemp': 0,
        'highlights': 0,
        'shadows': 0,
        ...params,
      },
      faces: const <String, Map<String, dynamic>>{},
    );

    return FilteredPhoto(
      editState: editState,
      child: SizedBox(
        height: 44,
        width: 700,
        child: Row(
          children: [
            const Expanded(
              flex: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.black, Colors.white]),
                ),
                child: SizedBox.expand(),
              ),
            ),
            for (final c in _patches)
              Expanded(child: ColoredBox(color: c, child: const SizedBox.expand())),
          ],
        ),
      ),
    );
  }
}
