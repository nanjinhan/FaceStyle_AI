import 'package:flutter/widgets.dart';

import '../../room/domain/session_models.dart';

/// 로드맵 A7 — 전역 보정 파라미터를 실제 이미지에 적용하는 렌더링 파이프라인.
///
/// 아키텍처 설계 원칙 1(픽셀이 아니라 파라미터만 주고받는다)에 따라, 서버가 내려준
/// `global.*` 값을 각 기기가 여기서 ColorMatrix로 변환해 온디바이스 렌더링한다.
/// 모든 참여자가 같은 코드로 같은 파라미터를 렌더링하므로 화면 결과가 서로 일치한다.
///
/// 백엔드 `DEFAULT_GLOBAL_PARAMS`의 스칼라 6종을 다루며, 값 범위는 슬라이더와 동일한
/// -100 ~ +100 (0 = 원본)이다.
///
/// 한계: highlights/shadows는 본래 밝기 구간별로 다르게 먹는 비선형 보정이라
/// 4x5 선형 행렬로는 정확히 표현할 수 없다. 여기서는 gain/offset 조합으로 근사한다
/// (highlights = 밝은 쪽이 더 크게 움직이는 gain, shadows = 어두운 쪽을 들어올리는 offset).
/// 정확한 구현은 프래그먼트 셰이더가 필요하며 M4 보정 고도화 단계에서 교체한다.
class PhotoFilter {
  const PhotoFilter._();

  /// 항등 행렬 (보정 없음).
  static const List<double> identity = <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  /// 휘도 계수 (Rec.709) — 채도 조절 시 밝기를 보존하기 위해 사용.
  static const double _lumR = 0.2126;
  static const double _lumG = 0.7152;
  static const double _lumB = 0.0722;

  /// `editState`의 전역 파라미터로부터 최종 ColorMatrix를 만든다.
  ///
  /// 적용 순서는 일반적인 사진 보정 파이프라인을 따른다:
  /// 밝기 → 대비 → 하이라이트 → 그림자 → 채도 → 색온도.
  static List<double> fromEditState(EditState? editState) {
    if (editState == null) return identity;

    final brightness = _param(editState, 'brightness');
    final contrast = _param(editState, 'contrast');
    final saturation = _param(editState, 'saturation');
    final colorTemp = _param(editState, 'colorTemp');
    final highlights = _param(editState, 'highlights');
    final shadows = _param(editState, 'shadows');

    var matrix = identity;
    if (brightness != 0) matrix = _compose(_brightness(brightness), matrix);
    if (contrast != 0) matrix = _compose(_contrast(contrast), matrix);
    if (highlights != 0) matrix = _compose(_highlights(highlights), matrix);
    if (shadows != 0) matrix = _compose(_shadows(shadows), matrix);
    if (saturation != 0) matrix = _compose(_saturation(saturation), matrix);
    if (colorTemp != 0) matrix = _compose(_colorTemp(colorTemp), matrix);
    return matrix;
  }

  /// 보정값이 전부 0이면 필터를 걸 필요가 없다 (원본 그대로).
  static bool isIdentity(EditState? editState) {
    if (editState == null) return true;
    for (final key in const ['brightness', 'contrast', 'saturation', 'colorTemp', 'highlights', 'shadows']) {
      if (_param(editState, key) != 0) return false;
    }
    return true;
  }

  static double _param(EditState editState, String key) =>
      (editState.valueAt('global.$key') as num?)?.toDouble() ?? 0;

  // --- 개별 보정 행렬 -------------------------------------------------------

  /// 밝기: 전 채널에 일정한 offset을 더한다. ±100 → ±80/255.
  static List<double> _brightness(double p) {
    final offset = p * 0.8;
    return <double>[
      1, 0, 0, 0, offset, //
      0, 1, 0, 0, offset, //
      0, 0, 1, 0, offset, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// 대비: 중간톤(128)을 축으로 확대/축소. ±100 → gain 0 ~ 2.
  static List<double> _contrast(double p) {
    final gain = 1 + p / 100;
    final offset = 128 * (1 - gain);
    return <double>[
      gain, 0, 0, 0, offset, //
      0, gain, 0, 0, offset, //
      0, 0, gain, 0, offset, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// 하이라이트(근사): offset 없이 gain만 조절하면 밝은 픽셀일수록 변화폭이 커진다.
  static List<double> _highlights(double p) {
    final gain = 1 + p / 300;
    return <double>[
      gain, 0, 0, 0, 0, //
      0, gain, 0, 0, 0, //
      0, 0, gain, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// 그림자(근사): offset으로 어두운 쪽을 들어올리고, 흰색이 날아가지 않게 gain으로 보상.
  static List<double> _shadows(double p) {
    final offset = p * 0.35;
    final gain = 1 - p / 500;
    return <double>[
      gain, 0, 0, 0, offset, //
      0, gain, 0, 0, offset, //
      0, 0, gain, 0, offset, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// 채도: 휘도를 유지한 채 회색축에서 멀어지거나 가까워진다. ±100 → 흑백 ~ 2배.
  static List<double> _saturation(double p) {
    final s = 1 + p / 100;
    final inv = 1 - s;
    final r = _lumR * inv;
    final g = _lumG * inv;
    final b = _lumB * inv;
    return <double>[
      r + s, g, b, 0, 0, //
      r, g + s, b, 0, 0, //
      r, g, b + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// 색온도: +는 따뜻하게(R↑ B↓), -는 차갑게(R↓ B↑).
  static List<double> _colorTemp(double p) {
    final rGain = 1 + p / 400;
    final bGain = 1 - p / 400;
    return <double>[
      rGain, 0, 0, 0, 0, //
      0, 1, 0, 0, 0, //
      0, 0, bGain, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// 4x5 ColorMatrix 두 개를 합성한다 (`after` ∘ `before` — before가 먼저 적용된다).
  ///
  /// 마지막 행이 [0,0,0,0,1]인 5x5 아핀 행렬로 보고 곱한 뒤 상위 4행만 취한다.
  static List<double> _compose(List<double> after, List<double> before) {
    final out = List<double>.filled(20, 0);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 5; col++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += after[row * 5 + k] * before[k * 5 + col];
        }
        // 5번째 열(상수항)은 after의 offset이 그대로 더해진다.
        if (col == 4) sum += after[row * 5 + 4];
        out[row * 5 + col] = sum;
      }
    }
    return out;
  }
}

/// 보정 파라미터를 적용해 자식 위젯을 그리는 래퍼.
///
/// 보정값이 전부 0이면 필터 레이어를 아예 만들지 않아 원본 화질 그대로 표시된다.
class FilteredPhoto extends StatelessWidget {
  const FilteredPhoto({super.key, required this.editState, required this.child});

  final EditState? editState;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (PhotoFilter.isIdentity(editState)) return child;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(PhotoFilter.fromEditState(editState)),
      child: child,
    );
  }
}
