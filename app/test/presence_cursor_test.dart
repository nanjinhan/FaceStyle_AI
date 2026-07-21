import 'dart:convert';

import 'package:facestyle/features/room/application/room_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// 실시간 커서(presence.cursor) 파싱 검증.
/// 서버는 이미지 기준 0~1 정규화 좌표 {x, y}를 보낸다.
void main() {
  group('PresenceInfo.parseCursor', () {
    test('정상 좌표를 Offset으로 읽는다', () {
      final decoded = jsonDecode('{"x": 0.25, "y": 0.75}');
      final cursor = PresenceInfo.parseCursor(decoded);
      expect(cursor, const Offset(0.25, 0.75));
    });

    test('정수 좌표도 double로 읽는다', () {
      final cursor = PresenceInfo.parseCursor(jsonDecode('{"x": 0, "y": 1}'));
      expect(cursor, const Offset(0, 1));
    });

    test('null이나 형식이 틀리면 null', () {
      expect(PresenceInfo.parseCursor(null), isNull);
      expect(PresenceInfo.parseCursor('여기'), isNull);
      expect(PresenceInfo.parseCursor(jsonDecode('{"x": 0.5}')), isNull);
    });
  });

  group('PresenceInfo.copyWith', () {
    test('cursor를 유지하면서 다른 필드를 바꾼다', () {
      const info = PresenceInfo(tool: '밝기', cursor: Offset(0.1, 0.2));
      final next = info.copyWith(connected: false);
      expect(next.cursor, const Offset(0.1, 0.2));
      expect(next.tool, '밝기');
      expect(next.connected, isFalse);
    });
  });
}
