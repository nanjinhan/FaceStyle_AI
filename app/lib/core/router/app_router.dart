import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/album/presentation/album_detail_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/mypage_screen.dart';
import '../../features/auth/presentation/nickname_screen.dart';
import '../../features/camera/presentation/camera_screen.dart';
import '../../features/editor/presentation/editor_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/room/presentation/room_screen.dart';

/// 화면 라우팅. 명세서 페이지 구성(1.회원관리 / 2.홈 / 3.실시간 방 / 4.앨범)과 1:1 대응.
///
/// TODO(M2): 로그인 상태에 따른 redirect, 딥링크 facestyle://join?token=... 처리 (로드맵 A9)
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/nickname', builder: (_, _) => const NicknameScreen()),
      GoRoute(path: '/mypage', builder: (_, _) => const MyPageScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/camera', builder: (_, _) => const CameraScreen()),
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
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
