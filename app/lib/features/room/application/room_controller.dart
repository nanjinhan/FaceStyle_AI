import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/ws_client.dart';
import '../data/room_repository.dart';
import '../domain/session_models.dart';

enum RoomConnection { idle, connecting, connected, needsJoin, error }

/// 다른 참여자의 현재 작업 상태 (실시간 커서/라벨용).
///  - tool:   "밝기", "잡티 제거" 등 사용 중인 도구
///  - region: "global" 또는 "face_0" 등 편집 중 영역
class PresenceInfo {
  const PresenceInfo({this.tool, this.region, this.connected = true});

  final String? tool;
  final String? region;
  final bool connected;

  PresenceInfo copyWith({String? tool, String? region, bool? connected}) => PresenceInfo(
        tool: tool ?? this.tool,
        region: region ?? this.region,
        connected: connected ?? this.connected,
      );
}

/// 방 화면 전체가 구독하는 불변 상태 스냅샷.
class RoomState {
  const RoomState({
    this.connection = RoomConnection.idle,
    this.session,
    this.currentPhotoId,
    this.editStates = const {},
    this.presence = const {},
    this.locks = const {},
    this.myMemberId,
    this.error,
  });

  final RoomConnection connection;
  final SessionDetail? session;
  final String? currentPhotoId;

  /// photoId → EditState (state_sync/edit_applied 로 갱신되는 라이브 파라미터).
  final Map<String, EditState> editStates;

  /// memberId → 프레즌스.
  final Map<String, PresenceInfo> presence;

  /// param path → 잠근 memberId (소프트 락).
  final Map<String, String> locks;

  final String? myMemberId;
  final String? error;

  Photo? get currentPhoto {
    if (session == null) return null;
    final id = currentPhotoId ?? (session!.photos.isEmpty ? null : session!.photos.first.id);
    if (id == null) return null;
    for (final p in session!.photos) {
      if (p.id == id) return p;
    }
    return null;
  }

  EditState? get currentEditState {
    final p = currentPhoto;
    return p == null ? null : editStates[p.id];
  }

  RoomState copyWith({
    RoomConnection? connection,
    SessionDetail? session,
    String? currentPhotoId,
    Map<String, EditState>? editStates,
    Map<String, PresenceInfo>? presence,
    Map<String, String>? locks,
    String? myMemberId,
    String? error,
  }) =>
      RoomState(
        connection: connection ?? this.connection,
        session: session ?? this.session,
        currentPhotoId: currentPhotoId ?? this.currentPhotoId,
        editStates: editStates ?? this.editStates,
        presence: presence ?? this.presence,
        locks: locks ?? this.locks,
        myMemberId: myMemberId ?? this.myMemberId,
        error: error,
      );
}

/// 실시간 방의 코어 컨트롤러. 세션 로드 → WS 연결 → 메시지 수신/편집 전송.
///
/// sessionId 를 family 인자로 받는다. member 토큰은 [memberTokenStoreProvider]
/// 에서 가져오며, 없으면 needsJoin 상태로 남는다(M2 join 플로우가 채운다).
class RoomController extends Notifier<RoomState> {
  RoomController(this._sessionId);

  /// family 인자(sessionId)는 생성자로 전달된다 (Riverpod 3.x NotifierProvider.family).
  final String _sessionId;

  RoomSocket? _socket;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  RoomState build() {
    ref.onDispose(_teardown);
    // build 는 동기 — 로드는 백그라운드로 시작한다.
    Future.microtask(bootstrap);
    return const RoomState(connection: RoomConnection.connecting);
  }

  void _teardown() {
    _sub?.cancel();
    _socket?.close();
    _socket = null;
    _sub = null;
  }

  Future<void> bootstrap() async {
    final token = ref.read(memberTokenStoreProvider.notifier).tokenFor(_sessionId);
    if (token == null) {
      state = state.copyWith(connection: RoomConnection.needsJoin);
      return;
    }
    await _loadAndConnect(token);
  }

  /// join 결과로 받은 토큰/세션으로 곧바로 연결 (M2 딥링크 진입 경로).
  Future<void> enterWith({required String memberToken, SessionDetail? session}) async {
    ref.read(memberTokenStoreProvider.notifier).save(_sessionId, memberToken);
    if (session != null) {
      state = _withSession(session, memberToken);
    }
    await _loadAndConnect(memberToken, preloaded: session);
  }

  Future<void> _loadAndConnect(String memberToken, {SessionDetail? preloaded}) async {
    state = state.copyWith(connection: RoomConnection.connecting);
    try {
      final session = preloaded ??
          await ref
              .read(roomRepositoryProvider)
              .getSession(_sessionId, memberToken: memberToken);
      state = _withSession(session, memberToken);
      _connectSocket(memberToken);
    } catch (e) {
      state = state.copyWith(connection: RoomConnection.error, error: e.toString());
    }
  }

  RoomState _withSession(SessionDetail session, String memberToken) {
    final editStates = <String, EditState>{
      for (final p in session.photos) p.id: p.editState,
    };
    return state.copyWith(
      session: session,
      editStates: editStates,
      myMemberId: _memberIdFromToken(memberToken),
      currentPhotoId: state.currentPhotoId ??
          (session.photos.isEmpty ? null : session.photos.first.id),
    );
  }

  void _connectSocket(String memberToken) {
    _teardown();
    final socket = RoomSocket.connect(sessionId: _sessionId, memberToken: memberToken);
    _socket = socket;
    _sub = socket.messages.listen(
      _onMessage,
      onError: (Object e) =>
          state = state.copyWith(connection: RoomConnection.error, error: e.toString()),
      onDone: () {
        if (state.connection == RoomConnection.connected) {
          state = state.copyWith(connection: RoomConnection.error, error: 'connection closed');
        }
      },
    );
  }

  void selectPhoto(String photoId) => state = state.copyWith(currentPhotoId: photoId);

  // ---- 서버 → 클라 메시지 처리 ------------------------------------------------

  void _onMessage(Map<String, dynamic> msg) {
    switch (msg['type'] as String?) {
      case 'state_sync':
        _onStateSync(msg);
      case 'edit_applied':
        _onEditApplied(msg);
      case 'presence_update':
        _onPresenceUpdate(msg);
      case 'param_locked':
        _setLock(msg['path'] as String, msg['memberId'] as String?);
      case 'param_unlocked':
        _setLock(msg['path'] as String, null);
      case 'face_claimed':
        _onFaceClaim(msg['faceId'] as String?, msg['memberId'] as String?);
      case 'face_released':
        _onFaceClaim(msg['faceId'] as String?, null);
      case 'member_kicked':
        _onMemberGone(msg['memberId'] as String?);
    }
  }

  void _onStateSync(Map<String, dynamic> msg) {
    final photos = (msg['photos'] as Map<String, dynamic>?) ?? const {};
    final editStates = <String, EditState>{
      for (final entry in photos.entries)
        entry.key: EditState.fromJson(entry.value as Map<String, dynamic>),
    };
    final presence = <String, PresenceInfo>{};
    (msg['presence'] as Map<String, dynamic>?)?.forEach((memberId, raw) {
      final info = raw as Map<String, dynamic>;
      presence[memberId] = PresenceInfo(
        tool: info['tool'] as String?,
        region: info['region'] as String?,
      );
    });
    final locks = <String, String>{};
    (msg['locks'] as Map<String, dynamic>?)?.forEach((path, memberId) {
      locks[path] = memberId as String;
    });
    state = state.copyWith(
      connection: RoomConnection.connected,
      editStates: editStates.isEmpty ? state.editStates : editStates,
      presence: presence,
      locks: locks,
    );
  }

  void _onEditApplied(Map<String, dynamic> msg) {
    final photoId = msg['photoId'] as String;
    final es = state.editStates[photoId];
    if (es == null) return;
    es.setAt(msg['path'] as String, msg['to']);
    es.version = (msg['seq'] as int?) ?? es.version;
    // EditState 는 가변 → 리스너 갱신을 위해 맵 참조를 새로 만든다.
    state = state.copyWith(editStates: {...state.editStates});
  }

  void _onPresenceUpdate(Map<String, dynamic> msg) {
    final memberId = msg['memberId'] as String?;
    if (memberId == null) return;
    final connected = msg['connected'] as bool? ?? true;
    final next = {...state.presence};
    if (!connected && !msg.containsKey('tool')) {
      next[memberId] = (next[memberId] ?? const PresenceInfo()).copyWith(connected: false);
    } else {
      next[memberId] = PresenceInfo(
        tool: msg['tool'] as String?,
        region: msg['region'] as String?,
        connected: connected,
      );
    }
    state = state.copyWith(presence: next);
  }

  void _setLock(String path, String? memberId) {
    final next = {...state.locks};
    if (memberId == null) {
      next.remove(path);
    } else {
      next[path] = memberId;
    }
    state = state.copyWith(locks: next);
  }

  void _onFaceClaim(String? faceId, String? memberId) {
    final session = state.session;
    if (session == null || faceId == null) return;
    final photos = session.photos
        .map((p) => p.copyWith(
              faces: p.faces
                  .map((f) => f.id == faceId ? f.copyWith(claimedByMemberId: memberId) : f)
                  .toList(),
            ))
        .toList();
    state = state.copyWith(session: _replacePhotos(session, photos));
  }

  void _onMemberGone(String? memberId) {
    if (memberId == null) return;
    final next = {...state.presence};
    next[memberId] = (next[memberId] ?? const PresenceInfo()).copyWith(connected: false);
    state = state.copyWith(presence: next);
  }

  // ---- 클라 → 서버 (낙관적 로컬 반영 + 전송) ---------------------------------

  /// 전역 파라미터 편집. 슬라이더가 즉시 반응하도록 로컬 먼저 반영하고 서버로 보낸다.
  void editGlobal(String photoId, String key, dynamic value) {
    _edit(photoId, 'global.$key', value);
  }

  /// 얼굴 파라미터 편집. path 예: face_0 / skinSmooth.
  void editFace(String photoId, String faceKey, String key, dynamic value) {
    _edit(photoId, 'faces.$faceKey.$key', value);
  }

  void _edit(String photoId, String path, dynamic value) {
    final es = state.editStates[photoId];
    if (es != null) {
      es.setAt(path, value);
      state = state.copyWith(editStates: {...state.editStates});
    }
    _socket?.edit(photoId, path, value);
  }

  void undo(String photoId) => _socket?.undo(photoId);

  void redo(String photoId) => _socket?.redo(photoId);

  /// 편집 중 도구/영역 브로드캐스트 (실시간 커서 라벨).
  void reportPresence({String? tool, String? region}) =>
      _socket?.presence(tool: tool, region: region);

  void lockParam(String path) => _socket?.lockParam(path);
  void unlockParam(String path) => _socket?.unlockParam(path);
  void reaction(String emoji) => _socket?.reaction(emoji);

  // ---- helpers ---------------------------------------------------------------

  static SessionDetail _replacePhotos(SessionDetail s, List<Photo> photos) => SessionDetail(
        id: s.id,
        status: s.status,
        inviteToken: s.inviteToken,
        inviteCode: s.inviteCode,
        maxMembers: s.maxMembers,
        expiresAt: s.expiresAt,
        members: s.members,
        photos: photos,
      );

  /// member JWT(payload.sub)에서 내 memberId 추출. 실패 시 null.
  static String? _memberIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      payload = payload.padRight((payload.length + 3) & ~3, '=');
      final json = jsonDecode(utf8.decode(base64.decode(payload))) as Map<String, dynamic>;
      return json['sub'] as String?;
    } catch (_) {
      return null;
    }
  }
}

final roomControllerProvider =
    NotifierProvider.family<RoomController, RoomState, String>(RoomController.new);
