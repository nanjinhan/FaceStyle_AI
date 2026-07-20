import 'package:facestyle/features/editor/rendering/photo_filter.dart';
import 'package:facestyle/features/room/domain/session_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// A7 렌더링 파이프라인 검증.
///
/// 화면 없이 수식만 확인한다. 모든 참여자가 같은 파라미터로 같은 결과를 렌더링해야 하므로
/// (아키텍처 "최종 렌더링 일관성") 이 변환은 결정적이어야 한다.
void main() {
  EditState stateWith(Map<String, dynamic> global) => EditState(
        photoId: 'photo_test',
        version: 1,
        global: <String, dynamic>{
          'brightness': 0,
          'contrast': 0,
          'saturation': 0,
          'colorTemp': 0,
          'highlights': 0,
          'shadows': 0,
          ...global,
        },
        faces: <String, Map<String, dynamic>>{},
      );

  /// 행렬을 (r,g,b) 픽셀에 적용한 결과. 채널값은 0~255.
  List<double> apply(List<double> m, double r, double g, double b) => <double>[
        m[0] * r + m[1] * g + m[2] * b + m[4],
        m[5] * r + m[6] * g + m[7] * b + m[9],
        m[10] * r + m[11] * g + m[12] * b + m[14],
      ];

  group('isIdentity', () {
    test('모든 값이 0이면 원본 그대로 (필터 레이어 생략)', () {
      expect(PhotoFilter.isIdentity(stateWith({})), isTrue);
      expect(PhotoFilter.isIdentity(null), isTrue);
    });

    test('하나라도 0이 아니면 필터를 건다', () {
      expect(PhotoFilter.isIdentity(stateWith({'brightness': 1})), isFalse);
      expect(PhotoFilter.isIdentity(stateWith({'shadows': -3})), isFalse);
    });
  });

  group('개별 보정', () {
    test('밝기 +100 은 전 채널을 +80 만큼 올린다', () {
      final m = PhotoFilter.fromEditState(stateWith({'brightness': 100}));
      final out = apply(m, 100, 100, 100);
      expect(out[0], closeTo(180, 0.001));
      expect(out[1], closeTo(180, 0.001));
      expect(out[2], closeTo(180, 0.001));
    });

    test('밝기 음수는 어둡게 만든다', () {
      final m = PhotoFilter.fromEditState(stateWith({'brightness': -50}));
      expect(apply(m, 100, 100, 100)[0], closeTo(60, 0.001));
    });

    test('대비는 중간톤(128)을 고정축으로 삼는다', () {
      final m = PhotoFilter.fromEditState(stateWith({'contrast': 50}));
      // 128은 그대로, 그보다 밝은 값은 더 밝게, 어두운 값은 더 어둡게.
      expect(apply(m, 128, 128, 128)[0], closeTo(128, 0.001));
      expect(apply(m, 200, 200, 200)[0], greaterThan(200));
      expect(apply(m, 50, 50, 50)[0], lessThan(50));
    });

    test('채도 -100 이면 완전 흑백 (RGB 세 채널이 같아진다)', () {
      final m = PhotoFilter.fromEditState(stateWith({'saturation': -100}));
      final out = apply(m, 200, 100, 50);
      expect(out[0], closeTo(out[1], 0.001));
      expect(out[1], closeTo(out[2], 0.001));
      // Rec.709 휘도값과 일치해야 한다.
      expect(out[0], closeTo(0.2126 * 200 + 0.7152 * 100 + 0.0722 * 50, 0.001));
    });

    test('채도는 회색 픽셀을 바꾸지 않는다', () {
      final m = PhotoFilter.fromEditState(stateWith({'saturation': 80}));
      final out = apply(m, 120, 120, 120);
      expect(out[0], closeTo(120, 0.001));
      expect(out[2], closeTo(120, 0.001));
    });

    test('색온도 +는 따뜻하게(R↑ B↓), -는 차갑게(R↓ B↑)', () {
      final warm = apply(PhotoFilter.fromEditState(stateWith({'colorTemp': 100})), 100, 100, 100);
      expect(warm[0], greaterThan(100));
      expect(warm[1], closeTo(100, 0.001)); // G는 유지
      expect(warm[2], lessThan(100));

      final cool = apply(PhotoFilter.fromEditState(stateWith({'colorTemp': -100})), 100, 100, 100);
      expect(cool[0], lessThan(100));
      expect(cool[2], greaterThan(100));
    });

    test('하이라이트는 밝은 영역을 어두운 영역보다 크게 움직인다', () {
      final m = PhotoFilter.fromEditState(stateWith({'highlights': 100}));
      final brightDelta = apply(m, 240, 240, 240)[0] - 240;
      final darkDelta = apply(m, 20, 20, 20)[0] - 20;
      expect(brightDelta, greaterThan(darkDelta));
    });

    test('그림자 +는 어두운 영역을 들어올린다', () {
      final m = PhotoFilter.fromEditState(stateWith({'shadows': 100}));
      expect(apply(m, 10, 10, 10)[0], greaterThan(10));
    });
  });

  group('합성', () {
    test('여러 보정을 함께 걸어도 각각의 방향이 유지된다', () {
      final m = PhotoFilter.fromEditState(stateWith({
        'brightness': 20,
        'contrast': 15,
        'saturation': -30,
        'colorTemp': 10,
      }));
      final out = apply(m, 120, 90, 60);
      // 밝기·대비가 올라갔으니 중간톤보다 밝아지고, 채도가 내려갔으니 R-B 간격이 좁아진다.
      final originalSpread = 120 - 60;
      final newSpread = out[0] - out[2];
      expect(newSpread, lessThan(originalSpread));
      expect(out[0], greaterThan(0));
    });

    test('같은 파라미터는 항상 같은 행렬을 만든다 (렌더링 일관성)', () {
      final params = {'brightness': 33, 'contrast': -12, 'saturation': 45, 'shadows': 7};
      expect(
        PhotoFilter.fromEditState(stateWith(params)),
        equals(PhotoFilter.fromEditState(stateWith(params))),
      );
    });

    test('보정값 0은 항등 행렬', () {
      expect(PhotoFilter.fromEditState(stateWith({})), equals(PhotoFilter.identity));
    });
  });
}
