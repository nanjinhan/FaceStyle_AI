import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../domain/app_user.dart';

/// 로그인 상태.
///  - unknown: 앱 시작 직후 저장된 토큰 복원 중
///  - signedOut / signedIn
enum AuthStatus { unknown, signedOut, signedIn }

class AuthState {
  const AuthState({this.status = AuthStatus.unknown, this.user, this.token});

  final AuthStatus status;
  final AppUser? user;
  final String? token;

  bool get isSignedIn => status == AuthStatus.signedIn;

  AuthState copyWith({AuthStatus? status, AppUser? user, String? token}) => AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        token: token ?? this.token,
      );
}

const _kTokenKey = 'user_token';
const _kProviderIdKey = 'device_provider_id';

/// 회원/인증 컨트롤러 (명세 1장).
///
/// 실제 카카오/구글 OAuth는 앱 키가 준비되면 붙인다(docs/출시-준비물.md). 지금은
/// 백엔드 social-login 스텁(검증 생략)을 그대로 써서 "기기 단위 개발 계정"으로 로그인한다.
/// 토큰은 shared_preferences 에 저장해 앱을 다시 켜도 로그인이 유지된다.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    _restore();
    return const AuthState();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kTokenKey);
    if (token == null) {
      state = const AuthState(status: AuthStatus.signedOut);
      return;
    }
    ref.read(apiClientProvider).userToken = token;
    try {
      final json = await ref.read(apiClientProvider).get('/auth/me') as Map<String, dynamic>;
      state = AuthState(status: AuthStatus.signedIn, user: AppUser.fromJson(json), token: token);
    } catch (_) {
      // 토큰 만료/무효 → 로그아웃 상태로
      await prefs.remove(_kTokenKey);
      ref.read(apiClientProvider).userToken = null;
      state = const AuthState(status: AuthStatus.signedOut);
    }
  }

  /// 닉네임으로 로그인/가입 (개발용). 기기마다 고정된 provider_id 를 만들어
  /// 같은 기기는 항상 같은 계정으로 이어지게 한다.
  Future<void> signInWithNickname(String nickname) async {
    final prefs = await SharedPreferences.getInstance();
    var providerId = prefs.getString(_kProviderIdKey);
    if (providerId == null) {
      // 1 << 32 는 웹(JS)에서 0이 되므로 사용 금지 — 2^31-1 로 충분하다.
      providerId = 'dev-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(0x7fffffff)}';
      await prefs.setString(_kProviderIdKey, providerId);
    }

    final json = await ref.read(apiClientProvider).post('/auth/social-login', body: {
      'provider': 'dev',
      'provider_id': providerId,
      'nickname': nickname,
    }) as Map<String, dynamic>;

    final token = json['access_token'] as String;
    final user = AppUser.fromJson(json['user'] as Map<String, dynamic>);
    await prefs.setString(_kTokenKey, token);
    ref.read(apiClientProvider).userToken = token;
    state = AuthState(status: AuthStatus.signedIn, user: user, token: token);
  }

  /// 닉네임 변경 (명세 1장 — 회원정보 수정).
  Future<void> updateNickname(String nickname) async {
    final json = await ref.read(apiClientProvider).patch('/auth/me', body: {'nickname': nickname})
        as Map<String, dynamic>;
    state = state.copyWith(user: AppUser.fromJson(json));
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenKey);
    ref.read(apiClientProvider).userToken = null;
    state = const AuthState(status: AuthStatus.signedOut);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
