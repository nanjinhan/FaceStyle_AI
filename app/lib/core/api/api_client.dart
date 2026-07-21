import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// 백엔드 REST 클라이언트.
///
/// 토큰 2종 (backend/app/security.py 참고):
///  - userToken:   로그인한 유저 (typ=user)
///  - memberToken: 방/앨범 참여자 (typ=member) — 게스트도 발급받는다
class ApiClient {
  ApiClient({this.userToken});

  String? userToken;

  Uri _uri(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  Map<String, String> _headers({String? memberToken}) => {
        'Content-Type': 'application/json',
        if (memberToken != null)
          'Authorization': 'Bearer $memberToken'
        else if (userToken != null)
          'Authorization': 'Bearer $userToken',
      };

  Future<dynamic> get(String path, {String? memberToken}) async {
    final res = await http.get(_uri(path), headers: _headers(memberToken: memberToken));
    return _decode(res);
  }

  Future<dynamic> post(String path, {Object? body, String? memberToken}) async {
    final res = await http.post(
      _uri(path),
      headers: _headers(memberToken: memberToken),
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(res);
  }

  Future<dynamic> patch(String path, {Object? body, String? memberToken}) async {
    final res = await http.patch(
      _uri(path),
      headers: _headers(memberToken: memberToken),
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(res);
  }

  dynamic _decode(http.Response res) {
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiException($statusCode): $body';
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
