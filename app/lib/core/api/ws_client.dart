import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';

/// 실시간 방 WebSocket 클라이언트.
///
/// 프로토콜은 docs/아키텍처.md "실시간 프로토콜(WS)" 표와 backend/app/routers/ws.py가 기준.
/// 서버 → 클라 메시지: state_sync, edit_applied, presence_update, param_locked/unlocked,
/// face_claimed/released, member_kicked, export_ready, reaction,
/// (추가 예정) completion_update, finalized
class RoomSocket {
  RoomSocket._(this._channel);

  final WebSocketChannel _channel;

  static RoomSocket connect({required String sessionId, required String memberToken}) {
    final uri = Uri.parse('${AppConfig.wsBaseUrl}/ws/sessions/$sessionId?token=$memberToken');
    return RoomSocket._(WebSocketChannel.connect(uri));
  }

  Stream<Map<String, dynamic>> get messages =>
      _channel.stream.map((raw) => jsonDecode(raw as String) as Map<String, dynamic>);

  void _send(Map<String, dynamic> msg) => _channel.sink.add(jsonEncode(msg));

  /// 파라미터 편집. path 예: "global.brightness", "faces.face_0.skinSmooth"
  void edit(String photoId, String path, dynamic value) =>
      _send({'type': 'edit', 'photoId': photoId, 'path': path, 'value': value});

  void undo(String photoId) => _send({'type': 'undo', 'photoId': photoId});

  void redo(String photoId) => _send({'type': 'redo', 'photoId': photoId});

  /// 작업 상태 + 커서 위치 공유 (실시간 커서 / "OO — 잡티 제거 중" 라벨)
  void presence({String? tool, String? region, Map<String, double>? cursor}) =>
      _send({'type': 'presence', 'tool': tool, 'region': region, 'cursor': cursor});

  void lockParam(String path) => _send({'type': 'lock_param', 'path': path});

  void unlockParam(String path) => _send({'type': 'unlock_param', 'path': path});

  void reaction(String emoji) => _send({'type': 'reaction', 'emoji': emoji});

  /// 기능별 리셋 (명세: 되돌리기 — 기능별 리셋) — 백엔드 추가 예정 (로드맵 B6)
  void resetParam(String photoId, String path) =>
      _send({'type': 'reset_param', 'photoId': photoId, 'path': path});

  /// 완료 확정 체크 (명세: 저장 — 완료 확정) — 백엔드 추가 예정 (로드맵 B7)
  void complete(String photoId, {required bool done}) =>
      _send({'type': done ? 'complete' : 'uncomplete', 'photoId': photoId});

  void close() => _channel.sink.close();
}
