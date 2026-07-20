import 'dart:convert';

import 'package:facestyle/features/room/domain/session_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// B7 완료 확정의 클라이언트측 판정 로직.
///
/// 서버(ws.py)와 같은 기준이어야 한다: 분모는 "그 사진에서 얼굴을 클레임한 멤버".
void main() {
  group('WS completion_update 파싱', () {
    test('completed / required / finalized 를 읽는다', () {
      final c = CompletionState.fromJson({
        'completed': ['mem_a'],
        'required': ['mem_a', 'mem_b'],
        'finalized': false,
      });

      expect(c.doneCount, 1);
      expect(c.totalCount, 2);
      expect(c.finalized, isFalse);
    });

    test('REST 응답의 completedBy / requiredBy 도 같은 모델로 읽는다', () {
      final c = CompletionState.fromJson({
        'completedBy': ['mem_a'],
        'requiredBy': ['mem_a', 'mem_b'],
        'finalized': true,
      });

      expect(c.doneCount, 1);
      expect(c.totalCount, 2);
      expect(c.finalized, isTrue);
    });

    test('필드가 없으면 빈 상태로 처리한다', () {
      final c = CompletionState.fromJson({});

      expect(c.hasNobody, isTrue);
      expect(c.finalized, isFalse);
    });
  });

  group('완료 버튼 표시 판정', () {
    const completion = CompletionState(
      completed: ['mem_a'],
      requiredMembers: ['mem_a', 'mem_b'],
    );

    test('내가 이미 완료했으면 완료함으로 보인다', () {
      expect(completion.isDoneBy('mem_a'), isTrue);
      expect(completion.isDoneBy('mem_b'), isFalse);
    });

    test('얼굴을 지정한 사람만 완료 체크 대상이다', () {
      expect(completion.isRequiredOf('mem_b'), isTrue);
      // 방에 있지만 얼굴을 지정하지 않은 사람 → 대상 아님 (서버도 거부한다)
      expect(completion.isRequiredOf('mem_구경꾼'), isFalse);
      expect(completion.isRequiredOf(null), isFalse);
    });

    test('아무도 얼굴을 지정하지 않았으면 완료 현황을 감춘다', () {
      expect(const CompletionState().hasNobody, isTrue);
      expect(completion.hasNobody, isFalse);
    });
  });

  /// 서버 응답과 같은 경로(jsonDecode)를 타야 중첩 맵 타입까지 실제와 같아진다.
  Map<String, dynamic> decode(String raw) => jsonDecode(raw) as Map<String, dynamic>;

  group('Photo 파싱', () {
    test('사진 JSON에서 완료 현황까지 함께 읽는다', () {
      final photo = Photo.fromJson(decode('''
        {
          "id": "photo_1", "url": "/media/x.png", "width": 100, "height": 100,
          "faces": [],
          "editState": {"photoId": "photo_1", "version": 3, "global": {}, "faces": {}},
          "completedBy": ["mem_a"], "requiredBy": ["mem_a"], "finalized": true
        }
      '''));

      expect(photo.completion.finalized, isTrue);
      expect(photo.completion.doneCount, 1);
      expect(photo.editState.version, 3);
    });

    test('완료 필드가 없는 예전 응답도 깨지지 않는다', () {
      final photo = Photo.fromJson(decode('''
        {
          "id": "photo_1", "url": "/media/x.png", "width": 100, "height": 100,
          "faces": [],
          "editState": {"photoId": "photo_1", "version": 0, "global": {}, "faces": {}}
        }
      '''));

      expect(photo.completion.hasNobody, isTrue);
      expect(photo.completion.finalized, isFalse);
    });
  });
}
