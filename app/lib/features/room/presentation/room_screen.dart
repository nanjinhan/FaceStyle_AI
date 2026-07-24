import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config.dart';
import '../../../core/theme/member_colors.dart';
import '../../../core/ui/ui.dart';
import '../application/room_controller.dart';
import '../domain/session_models.dart';

/// 명세 3. 실시간 방 — 초대·인원 표시·컷 선택.
/// 정책: 방 인원 제한 6명, 24시간 후 자동 만료 → 앨범 이관 (로드맵 B9).
///
/// M1 슬라이스: 세션 상태 로드 + 참여자 아바타(고유 색상) + 컷 선택 → 에디터 진입.
/// TODO(M2): 초대 링크 딥링크(facestyle://join?token=...) 공유 + 게스트 입장 (A9)
/// TODO(B8): 사진 다중 업로드 + 컷 선택 (현재 백엔드는 세션당 1장)
class RoomScreen extends ConsumerWidget {
  const RoomScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(roomControllerProvider(sessionId));
    final controller = ref.read(roomControllerProvider(sessionId).notifier);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          tooltip: '홈',
          onPressed: () => context.go('/home'),
        ),
        title: const Text('같이 보정하기'),
        actions: [
          if (state.session != null)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: '초대',
              onPressed: () => _shareInvite(context, state.session!),
            ),
        ],
      ),
      body: _body(context, state, controller),
    );
  }

  Widget _body(BuildContext context, RoomState state, RoomController controller) {
    switch (state.connection) {
      case RoomConnection.connecting:
      case RoomConnection.idle:
        return const Center(child: CircularProgressIndicator());
      case RoomConnection.needsJoin:
        return _RoomNotice(
          icon: Icons.link_off,
          message: '이 방에 참여한 기록이 없어요.\n홈에서 새로 만들거나 초대 코드로 입장해 주세요.',
          onRetry: () => context.go('/home'),
          retryLabel: '홈으로',
        );
      case RoomConnection.error:
        return _RoomNotice(
          icon: Icons.wifi_off,
          message: '방을 불러오지 못했어요.\n${state.error ?? ''}',
          onRetry: controller.bootstrap,
        );
      case RoomConnection.connected:
        break;
    }

    final session = state.session!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _memberStrip(context, session),
        const SizedBox(height: 8),
        _inviteCard(context, session),
        const SizedBox(height: 24),
        Text('어떤 컷으로 보정할까요?',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (session.photos.isEmpty)
          const _RoomNotice(icon: Icons.add_a_photo_outlined, message: '아직 올라온 사진이 없어요.')
        else
          for (final photo in session.photos) _photoTile(context, photo),
      ],
    );
  }

  Widget _memberStrip(BuildContext context, SessionDetail session) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (final m in session.members) _memberAvatar(m),
        if (session.members.length < session.maxMembers)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(Icons.person_add_alt, color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 4),
              Text('${session.maxMembers - session.members.length}자리',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
      ],
    );
  }

  Widget _memberAvatar(Member m) {
    final color = MemberColors.fromHex(null, fallbackSeed: m.id);
    final initial = m.nickname.isEmpty ? '?' : m.nickname.characters.first;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            CircleAvatar(
              backgroundColor: color,
              child: Text(initial, style: const TextStyle(color: Colors.white)),
            ),
            if (m.connected)
              const Positioned(
                right: 0,
                bottom: 0,
                child: CircleAvatar(radius: 6, backgroundColor: Color(0xFF4CB782)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(m.isHost ? '${m.nickname} 👑' : m.nickname),
      ],
    );
  }

  Widget _inviteCard(BuildContext context, SessionDetail session) {
    return ShadCard(
      leading: const Icon(Icons.qr_code_2),
      title: '초대 코드  ${session.inviteCode}',
      description: '탭하면 코드를 복사해요',
      trailing: const Icon(Icons.copy, size: 18),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: session.inviteCode));
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('초대 코드를 복사했어요')));
        }
      },
    );
  }

  Widget _photoTile(BuildContext context, Photo photo) {
    final url = '${AppConfig.apiBaseUrl}${photo.url}';
    final claimed = photo.faces.where((f) => f.isClaimed).length;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiTokens.radiusLg),
          side: BorderSide(color: scheme.outline),
        ),
        child: InkWell(
          onTap: () => context.push('/rooms/$sessionId/photos/${photo.id}/edit'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: photo.width == 0 ? 16 / 9 : photo.width / photo.height,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Colors.black12,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Text('얼굴 ${photo.faces.length} · 클레임 $claimed',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                    const Spacer(),
                    Text('보정하기', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface)),
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _shareInvite(BuildContext context, SessionDetail session) {
    // TODO(A9): OS 공유 시트 + facestyle://join?token= 딥링크. 지금은 코드 복사로 대체.
    Clipboard.setData(ClipboardData(
      text: '${AppConfig.deepLinkScheme}://join?token=${session.inviteToken}',
    ));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('초대 링크를 복사했어요')));
  }
}

class _RoomNotice extends StatelessWidget {
  const _RoomNotice({
    required this.icon,
    required this.message,
    this.onRetry,
    this.retryLabel = '다시 시도',
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ],
        ),
      ),
    );
  }
}
