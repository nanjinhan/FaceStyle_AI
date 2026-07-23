import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/brand.dart';
import '../../album/data/album_repository.dart';
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          // 메인 CTA — 브랜드 그라데이션 히어로 카드.
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: Brand.gradient,
              borderRadius: BorderRadius.circular(Brand.radiusLg),
              boxShadow: [
                BoxShadow(
                  color: Brand.primary.withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.white, size: 22),
                    SizedBox(width: 8),
                    Text('친구들과 같이 보정하기',
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '단체사진을 올리면 각자 자기 얼굴을\n실시간으로 보정할 수 있어요.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), height: 1.4),
                ),
                const SizedBox(height: 18),
                GradientButton(
                  onPressed: _createRoom,
                  busy: _creating,
                  gradient: const LinearGradient(colors: [Colors.white, Colors.white]),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, color: Brand.primary),
                      SizedBox(width: 8),
                      Text('사진 올려서 방 만들기', style: TextStyle(color: Brand.primary)),
                    ],
                  ),
                ),
              ],
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
          Row(
            children: [
              Text('내 앨범', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                onPressed: _createAlbum,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('새 앨범'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _albumList(context),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'camera',
        onPressed: () => context.push('/camera'),
        child: const Icon(Icons.photo_camera),
      ),
    );
  }

  /// 내 앨범 목록 — 로드/빈/에러 상태 처리.
  Widget _albumList(BuildContext context) {
    final async = ref.watch(myAlbumsProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('앨범을 불러오지 못했어요'),
          subtitle: Text('$e', maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => ref.invalidate(myAlbumsProvider),
        ),
      ),
      data: (albums) {
        if (albums.isEmpty) {
          return const Card(
            child: ListTile(
              leading: Icon(Icons.photo_album_outlined),
              title: Text('아직 앨범이 없어요'),
              subtitle: Text('"새 앨범"으로 친구들과 사진을 모아보세요'),
            ),
          );
        }
        return Column(
          children: [
            for (final a in albums)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Brand.primary.withValues(alpha: 0.12),
                      foregroundColor: Brand.primary,
                      child: const Icon(Icons.photo_library_outlined),
                    ),
                    title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('사진 ${a.photoCount} · 멤버 ${a.memberCount}'
                        '${a.role == "owner" ? " · 방장" : ""}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/albums/${a.id}'),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// 새 앨범 만들기 — 이름 입력 → 생성 → 상세로 이동.
  Future<void> _createAlbum() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('새 앨범'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '앨범 이름 (예: 제주 여행)'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('만들기')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final album = await ref.read(albumRepositoryProvider).create(name);
      ref.invalidate(myAlbumsProvider);
      if (mounted) context.push('/albums/${album.id}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('앨범을 만들지 못했어요: $e')));
      }
    }
  }
}
