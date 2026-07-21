import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/album/presentation/album_detail_screen.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/mypage_screen.dart';
import '../../features/auth/presentation/nickname_screen.dart';
import '../../features/camera/presentation/camera_screen.dart';
import '../../features/editor/presentation/editor_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/room/presentation/join_screen.dart';
import '../../features/room/presentation/room_screen.dart';

/// 화면 라우팅. 명세서 페이지 구성(1.회원관리 / 2.홈 / 3.실시간 방 / 4.앨범)과 1:1 대응.
///
/// 로그인 상태에 따라 redirect 한다. 초대 링크(/join)는 로그인 없이도 접근 가능(게스트, A10).
/// TODO(M2+): 딥링크 facestyle://join?token=... OS 연동 (A9)
final appRouterProvider = Provider<GoRouter>((ref) {
  // 로그인 상태가 바뀌면 redirect 를 다시 평가하도록 알린다.
  // (라우터 자체는 한 번만 만들어 네비게이션 히스토리를 보존한다.)
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      // 초대로 들어오는 경로는 로그인 없이 허용 (게스트 참여)
      final isGuestPath = loc.startsWith('/join');
      final isLoginPath = loc == '/login';

      switch (auth.status) {
        case AuthStatus.unknown:
          return null; // 토큰 복원 중 — 그대로 둔다
        case AuthStatus.signedOut:
          return (isLoginPath || isGuestPath) ? null : '/login';
        case AuthStatus.signedIn:
          return isLoginPath ? '/home' : null;
      }
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/nickname', builder: (_, _) => const NicknameScreen()),
      GoRoute(path: '/mypage', builder: (_, _) => const MyPageScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/camera', builder: (_, _) => const CameraScreen()),
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
      // 초대 코드/토큰으로 참여 (게스트 포함)
      GoRoute(
        path: '/join',
        builder: (_, state) => JoinScreen(invite: state.uri.queryParameters['invite']),
      ),
      GoRoute(
        path: '/rooms/:sessionId',
        builder: (_, state) => RoomScreen(sessionId: state.pathParameters['sessionId']!),
      ),
      GoRoute(
        path: '/rooms/:sessionId/photos/:photoId/edit',
        builder: (_, state) => EditorScreen(
          sessionId: state.pathParameters['sessionId']!,
          photoId: state.pathParameters['photoId']!,
        ),
      ),
      GoRoute(
        path: '/albums/:albumId',
        builder: (_, state) => AlbumDetailScreen(albumId: state.pathParameters['albumId']!),
      ),
    ],
  );
});
