import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth/application/auth_controller.dart';
import '../../room/data/room_repository.dart';

/// 명세 2. 메인페이지 (홈).
///  - "같이 보정하기": 사진 골라 실시간 방 생성 → 방 입장
///  - 카메라 진입, 알림, 마이페이지
/// TODO(M3): 내 앨범 목록 + 최근 작업 + 할 일 배너 (GET /albums, 무한 스크롤)
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _creating = false;

  /// 사진을 골라 방을 만들고 입장한다.
  Future<void> _createRoom() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();
    if (picked.isEmpty || !mounted) return;

    setState(() => _creating = true);
    try {
      final photos = <UploadPhoto>[];
      for (final x in picked) {
        photos.add(UploadPhoto(filename: x.name, bytes: await x.readAsBytes()));
      }
      final repo = ref.read(roomRepositoryProvider);
      // 방 생성(호스트) → 같은 초대로 join 해서 호스트 member 토큰 확보
      final session = await repo.createSession(photos);
      final joined = await repo.join(invite: session.inviteToken);
      ref.read(memberTokenStoreProvider.notifier).save(session.id, joined.memberToken);
      if (mounted) context.go('/rooms/${session.id}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('방을 만들지 못했어요: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('FaceStyle'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.push('/mypage'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (user != null)
            Text('${user.nickname}님, 반가워요 👋',
                style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('친구들과 같이 보정하기',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('단체사진을 올리면 각자 자기 얼굴을 실시간으로 보정할 수 있어요.'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _creating ? null : _createRoom,
                    icon: _creating
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.group_add),
                    label: Text(_creating ? '방 만드는 중…' : '사진 올려서 방 만들기'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.login),
              title: const Text('초대 코드로 참여'),
              subtitle: const Text('친구가 보낸 코드를 입력해요'),
              onTap: () => context.push('/join'),
            ),
          ),
          const SizedBox(height: 24),
          // TODO(M3): 내 앨범 목록 + 할 일 배너
          Text('내 앨범', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.photo_album_outlined),
              title: Text('앨범 기능은 준비 중이에요 (M3)'),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'camera',
        onPressed: () => context.push('/camera'),
        child: const Icon(Icons.photo_camera),
      ),
    );
  }
}
