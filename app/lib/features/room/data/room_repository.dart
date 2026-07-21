import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/api/api_client.dart';
import '../../../core/config.dart';
import '../domain/session_models.dart';

/// 업로드할 사진 1장 (image_picker 결과에서 만든다).
class UploadPhoto {
  const UploadPhoto({required this.filename, required this.bytes});
  final String filename;
  final Uint8List bytes;
}

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

  /// 사진 여러 장으로 실시간 방 생성 (SES-01/02). 로그인 유저 토큰이 필요하다.
  /// 생성자는 호스트가 되지만 member 토큰은 별도로 발급받아야 한다(join 또는 아래 hostToken).
  Future<SessionDetail> createSession(List<UploadPhoto> photos) async {
    final token = _api.userToken;
    if (token == null) {
      throw ApiException(401, '로그인이 필요해요');
    }
    final req = http.MultipartRequest('POST', Uri.parse('${AppConfig.apiBaseUrl}/sessions'));
    req.headers['Authorization'] = 'Bearer $token';
    for (final p in photos) {
      req.files.add(http.MultipartFile.fromBytes('files', p.bytes, filename: p.filename));
    }
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, body);
    }
    return SessionDetail.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// "이게 나예요" — 얼굴 클레임(FACE-02). 이미 남이 클레임했으면 409.
  /// 결과 브로드캐스트(face_claimed)는 WS로 오므로 여기서는 요청만 보낸다.
  Future<void> claimFace(
    String sessionId,
    String photoId,
    String faceId, {
    required String memberToken,
  }) =>
      _api.post(
        '/sessions/$sessionId/photos/$photoId/faces/$faceId/claim',
        memberToken: memberToken,
      );

  Future<void> unclaimFace(
    String sessionId,
    String photoId,
    String faceId, {
    required String memberToken,
  }) =>
      _api.post(
        '/sessions/$sessionId/photos/$photoId/faces/$faceId/unclaim',
        memberToken: memberToken,
      );
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
