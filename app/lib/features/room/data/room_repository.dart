import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../domain/session_models.dart';

/// 방 참여 결과: member 토큰 + 세션 스냅샷.
class JoinResult {
  const JoinResult({required this.memberToken, required this.session});

  final String memberToken;
  final SessionDetail session;
}

/// 실시간 방 REST 저장소. WS 이전의 REST 계약(sessions.py)을 감싼다.
class RoomRepository {
  RoomRepository(this._api);

  final ApiClient _api;

  /// 초대 토큰 또는 6자리 코드로 참여. 게스트는 [nickname]만으로 참여 가능(AUTH-02).
  Future<JoinResult> join({required String invite, String? nickname}) async {
    final json = await _api.post('/sessions/join', body: {
      'invite': invite,
      'nickname': ?nickname,
    }) as Map<String, dynamic>;
    return JoinResult(
      memberToken: json['memberToken'] as String,
      session: SessionDetail.fromJson(json['session'] as Map<String, dynamic>),
    );
  }

  /// 이미 발급받은 member 토큰으로 세션 상태 재조회.
  Future<SessionDetail> getSession(String sessionId, {required String memberToken}) async {
    final json = await _api.get('/sessions/$sessionId', memberToken: memberToken)
        as Map<String, dynamic>;
    return SessionDetail.fromJson(json);
  }
}

final roomRepositoryProvider = Provider<RoomRepository>(
  (ref) => RoomRepository(ref.watch(apiClientProvider)),
);

/// 방별 member 토큰 보관소. 참여(join) 시 저장하고, WS 연결/세션 재조회에 쓴다.
///
/// M2에서 딥링크/게스트 join 플로우가 이 store에 토큰을 채운다.
/// 현재는 인메모리 — 앱 재시작 시 재참여 필요.
class MemberTokenStore extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  String? tokenFor(String sessionId) => state[sessionId];

  void save(String sessionId, String token) {
    state = {...state, sessionId: token};
  }
}

final memberTokenStoreProvider =
    NotifierProvider<MemberTokenStore, Map<String, String>>(MemberTokenStore.new);
