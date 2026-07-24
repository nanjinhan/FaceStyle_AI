import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config.dart';
import '../../../core/theme/brand.dart';
import '../../../core/ui/ui.dart';
import '../../album/data/album_models.dart';
import '../../album/data/album_repository.dart';
import '../../auth/application/auth_controller.dart';
import '../../room/data/room_repository.dart';

/// 명세 2. 메인페이지 (홈) — Meitu식 구성.
///  - 상단 기능 아이콘 그리드 (같이 보정 / 초대 참여 / 카메라 / 알림)
///  - 큰 액션 버튼 2개 (방 만들기 / 초대 코드)
///  - 가로 스크롤 앨범 갤러리
///  - 하단 탭바 (홈 / 카메라 / 알림 / 나)
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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            const BrandMark(size: 30, radius: 9, icon: 17),
            const SizedBox(width: 10),
            Text('FaceStyle',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800, letterSpacing: -0.4, color: scheme.onSurface)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.push('/mypage'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (user != null) ...[
            Text('안녕하세요 👋',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text('${user.nickname}님',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 20),
          ],

          // ── 기능 아이콘 그리드 ─────────────────────────────────────────
          _FeatureGrid(
            items: [
              _Feature('같이 보정', Icons.auto_awesome, Brand.violet, Brand.violetSoft, _createRoom),
              _Feature('초대 참여', Icons.qr_code_rounded, const Color(0xFFEC5A96), const Color(0xFFFCE7F0),
                  () => context.push('/join')),
              _Feature('카메라', Icons.photo_camera_rounded, const Color(0xFF3B9AE8), const Color(0xFFE1F0FC),
                  () => context.push('/camera')),
              _Feature('알림', Icons.notifications_rounded, const Color(0xFFEF9C3B), const Color(0xFFFDEFDC),
                  () => context.push('/notifications')),
            ],
          ),
          const SizedBox(height: 22),

          // ── 큰 액션 버튼 2개 ──────────────────────────────────────────
          SizedBox(
            height: 116,
            child: Row(
              children: [
                Expanded(
                  child: _BigAction.gradient(
                    icon: Icons.add_photo_alternate_outlined,
                    title: '방 만들기',
                    subtitle: '사진 올려\n같이 보정',
                    loading: _creating,
                    onTap: _creating ? null : _createRoom,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BigAction.soft(
                    icon: Icons.login_rounded,
                    title: '초대 참여',
                    subtitle: '친구가 보낸\n코드 입력',
                    onTap: () => context.push('/join'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── 앨범 갤러리 ───────────────────────────────────────────────
          Row(
            children: [
              Text('내 앨범',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton.icon(
                onPressed: _createAlbum,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('새 앨범'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _albumGallery(context),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        onCamera: () => context.push('/camera'),
        onAlerts: () => context.push('/notifications'),
        onMe: () => context.push('/mypage'),
      ),
    );
  }

  /// 내 앨범 — 가로 스크롤 카드 갤러리. 로드/빈/에러 상태 처리.
  Widget _albumGallery(BuildContext context) {
    final async = ref.watch(myAlbumsProvider);
    return async.when(
      loading: () => const SizedBox(
        height: 190,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _EmptyAlbumCard(
        icon: Icons.error_outline,
        title: '앨범을 불러오지 못했어요',
        subtitle: '탭해서 다시 시도',
        onTap: () => ref.invalidate(myAlbumsProvider),
      ),
      data: (albums) {
        if (albums.isEmpty) {
          return _EmptyAlbumCard(
            icon: Icons.add_photo_alternate_outlined,
            title: '아직 앨범이 없어요',
            subtitle: '"새 앨범"으로 사진을 모아보세요',
            onTap: _createAlbum,
          );
        }
        return SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            itemCount: albums.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _AlbumCard(
              album: albums[i],
              onTap: () => context.push('/albums/${albums[i].id}'),
            ),
          ),
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

// ─────────────────────────────────────────────────────────────────────────
// 기능 아이콘 그리드
// ─────────────────────────────────────────────────────────────────────────

class _Feature {
  const _Feature(this.label, this.icon, this.fg, this.bg, this.onTap);
  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;
  final VoidCallback onTap;
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({required this.items});
  final List<_Feature> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final f in items)
          Expanded(
            child: InkWell(
              onTap: f.onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: f.bg,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(f.icon, color: f.fg, size: 26),
                    ),
                    const SizedBox(height: 8),
                    Text(f.label,
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 큰 액션 버튼
// ─────────────────────────────────────────────────────────────────────────

class _BigAction extends StatelessWidget {
  const _BigAction._({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.gradientStyle,
    this.loading = false,
  });

  factory _BigAction.gradient({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool loading = false,
  }) =>
      _BigAction._(
          icon: icon, title: title, subtitle: subtitle, onTap: onTap, gradientStyle: true, loading: loading);

  factory _BigAction.soft({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) =>
      _BigAction._(icon: icon, title: title, subtitle: subtitle, onTap: onTap, gradientStyle: false);

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool gradientStyle;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    final fg = gradientStyle ? Colors.white : Brand.violetDark;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: gradientStyle ? Brand.gradient : null,
        color: gradientStyle ? null : Brand.violetSoft,
        boxShadow: gradientStyle ? Brand.softShadow(y: 10, blur: 24, opacity: 0.28) : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                loading
                    ? SizedBox(
                        height: 26,
                        width: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
                    : Icon(icon, color: fg, size: 26),
                const Spacer(),
                Text(title, style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        color: gradientStyle ? Colors.white.withValues(alpha: 0.85) : Brand.violet,
                        fontSize: 11.5,
                        height: 1.25,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 앨범 카드
// ─────────────────────────────────────────────────────────────────────────

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, required this.onTap});
  final AlbumSummary album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cover = album.coverUrl;
    return SizedBox(
      width: 146,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 커버 (있으면 이미지, 없으면 보라 그라데이션 플레이스홀더)
              AspectRatio(
                aspectRatio: 1,
                child: cover != null && cover.isNotEmpty
                    ? Image.network('${AppConfig.apiBaseUrl}$cover', fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _coverPlaceholder(album.name))
                    : _coverPlaceholder(album.name),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                    const SizedBox(height: 2),
                    Text(
                        '사진 ${album.photoCount} · 멤버 ${album.memberCount}'
                        '${album.role == "owner" ? " · 방장" : ""}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverPlaceholder(String name) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: Brand.gradient),
      child: Center(
        child: Text(
          name.isNotEmpty ? name.characters.first : '📷',
          style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _EmptyAlbumCard extends StatelessWidget {
  const _EmptyAlbumCard(
      {required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 130,
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: Brand.violetSoft, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: Brand.violet, size: 24),
              ),
              const SizedBox(height: 10),
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 하단 탭바
// ─────────────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onCamera, required this.onAlerts, required this.onMe});
  final VoidCallback onCamera;
  final VoidCallback onAlerts;
  final VoidCallback onMe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              _tab(scheme, Icons.home_rounded, '홈', active: true, onTap: () {}),
              _tab(scheme, Icons.photo_camera_outlined, '카메라', active: false, onTap: onCamera),
              _tab(scheme, Icons.notifications_outlined, '알림', active: false, onTap: onAlerts),
              _tab(scheme, Icons.person_outline, '나', active: false, onTap: onMe),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(ColorScheme scheme, IconData icon, String label,
      {required bool active, required VoidCallback onTap}) {
    final color = active ? Brand.violet : scheme.onSurfaceVariant;
    return Expanded(
      child: InkResponse(
        onTap: onTap,
        radius: 44,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
