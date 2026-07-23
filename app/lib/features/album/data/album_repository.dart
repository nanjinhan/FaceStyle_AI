import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/api/api_client.dart';
import '../../../core/config.dart';
import 'album_models.dart';

/// 앨범 REST 저장소 (명세 4장). 유저 토큰(로그인)으로 호출한다.
class AlbumRepository {
  AlbumRepository(this._api);

  final ApiClient _api;

  Future<List<AlbumSummary>> myAlbums() async {
    final json = await _api.get('/albums') as List<dynamic>;
    return json.map((a) => AlbumSummary.fromJson(a as Map<String, dynamic>)).toList();
  }

  Future<AlbumDetail> create(String name) async {
    final json = await _api.post('/albums', body: {'name': name}) as Map<String, dynamic>;
    return AlbumDetail.fromJson(json);
  }

  Future<AlbumDetail> get(String id) async {
    final json = await _api.get('/albums/$id') as Map<String, dynamic>;
    return AlbumDetail.fromJson(json);
  }

  Future<AlbumDetail> join(String invite) async {
    final json = await _api.post('/albums/join', body: {'invite': invite}) as Map<String, dynamic>;
    return AlbumDetail.fromJson(json);
  }

  /// 사진 여러 장 업로드 (멀티파트).
  Future<AlbumDetail> uploadPhotos(String albumId, List<({String filename, Uint8List bytes})> photos) async {
    final token = _api.userToken;
    if (token == null) throw ApiException(401, '로그인이 필요해요');
    final req = http.MultipartRequest('POST', Uri.parse('${AppConfig.apiBaseUrl}/albums/$albumId/photos'));
    req.headers['Authorization'] = 'Bearer $token';
    for (final p in photos) {
      req.files.add(http.MultipartFile.fromBytes('files', p.bytes, filename: p.filename));
    }
    final res = await http.Response.fromStream(await req.send());
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode >= 400) throw ApiException(res.statusCode, body);
    return AlbumDetail.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }
}

final albumRepositoryProvider = Provider<AlbumRepository>(
  (ref) => AlbumRepository(ref.watch(apiClientProvider)),
);

/// 내 앨범 목록 (홈에서 구독). 로그인 후 자동 로드.
final myAlbumsProvider = FutureProvider.autoDispose<List<AlbumSummary>>(
  (ref) => ref.watch(albumRepositoryProvider).myAlbums(),
);
