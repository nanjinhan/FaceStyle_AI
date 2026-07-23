import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config.dart';
import '../../room/data/room_repository.dart';
import '../data/album_models.dart';
import '../data/album_repository.dart';

/// 명세 4. 앨범 (비동기 협업) — 상세: 사진 그리드 + 업로드 + 멤버/초대.
///
/// 슬라이스 1: 조회·업로드·초대까지. 앨범 사진 편집(에디터 진입)은 슬라이스 2.
class AlbumDetailScreen extends ConsumerStatefulWidget {
  const AlbumDetailScreen({super.key, required this.albumId});
  final String albumId;

  @override
  ConsumerState<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen> {
  AlbumDetail? _album;
  Object? _error;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final album = await ref.read(albumRepositoryProvider).get(widget.albumId);
      if (mounted) setState(() { _album = album; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _upload() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    try {
      final photos = <({String filename, Uint8List bytes})>[];
      for (final x in picked) {
        photos.add((filename: x.name, bytes: await x.readAsBytes()));
      }
      final album = await ref.read(albumRepositoryProvider).uploadPhotos(widget.albumId, photos);
      ref.invalidate(myAlbumsProvider);
      if (mounted) setState(() => _album = album);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('업로드 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// 사진 탭 → 편집 세션 열고 실시간 방 에디터로 진입 (앨범 비동기 보정).
  Future<void> _openPhoto(AlbumPhotoInfo photo) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final handle = await ref.read(albumRepositoryProvider).openEditSession(widget.albumId, photo.id);
      ref.read(memberTokenStoreProvider.notifier).save(handle.sessionId, handle.memberToken);
      if (mounted) {
        context.push('/rooms/${handle.sessionId}/photos/${handle.photoId}/edit');
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('편집을 열지 못했어요: $e')));
    }
  }

  void _shareInvite() {
    final album = _album;
    if (album == null) return;
    Clipboard.setData(ClipboardData(text: album.inviteCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('초대 코드 ${album.inviteCode} 를 복사했어요')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final album = _album;
    return Scaffold(
      appBar: AppBar(
        title: Text(album?.name ?? '앨범'),
        actions: [
          if (album != null)
            IconButton(icon: const Icon(Icons.person_add_alt), tooltip: '초대', onPressed: _shareInvite),
        ],
      ),
      body: _body(context, album),
      floatingActionButton: album == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _uploading ? null : _upload,
              icon: _uploading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add_photo_alternate),
              label: Text(_uploading ? '올리는 중…' : '사진 올리기'),
            ),
    );
  }

  Widget _body(BuildContext context, AlbumDetail? album) {
    if (_error != null) {
      return _Notice(
        icon: Icons.error_outline,
        message: '앨범을 불러오지 못했어요.\n$_error',
        onRetry: _load,
      );
    }
    if (album == null) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _memberBar(context, album)),
          if (album.photos.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _Notice(
                icon: Icons.add_photo_alternate_outlined,
                message: '아직 올라온 사진이 없어요.\n"사진 올리기"로 추가해 보세요.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _photoTile(album.photos[i]),
                  childCount: album.photos.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _memberBar(BuildContext context, AlbumDetail album) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(Icons.group_outlined, size: 18, color: muted),
          const SizedBox(width: 6),
          Text('멤버 ${album.members.length}', style: TextStyle(color: muted)),
          const Spacer(),
          Text('초대 코드 ${album.inviteCode}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _photoTile(AlbumPhotoInfo p) {
    return GestureDetector(
      onTap: () => _openPhoto(p),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              '${AppConfig.apiBaseUrl}${p.url}',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Container(color: Colors.black12, child: const Icon(Icons.broken_image_outlined)),
            ),
            if (p.finalized)
              const Positioned(
                right: 4,
                top: 4,
                child: Icon(Icons.check_circle, color: Colors.white, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message, this.onRetry});
  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message, textAlign: TextAlign.center),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ],
      ),
    );
  }
}
