import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../core/theme/member_colors.dart';
import '../../room/application/room_controller.dart';
import '../../room/domain/session_models.dart';

/// 명세 3·4 공용 보정 에디터. 실시간 방과 앨범 비동기 보정이 같은 화면을 쓴다.
///
/// 이번 슬라이스(M1)에서 구현:
///  - RoomSocket state_sync → 전역 파라미터 슬라이더에 반영, 값 변경 시 edit 전송
///  - 다른 참여자 프레즌스: "OO — △△ 편집 중" 라벨 (색상 점)
///  - undo/redo 전송
/// TODO(M1+): 얼굴 클레임 UI + 본인/타인 영역 잠금, 완료 체크(전원 완료 확정, B7)
/// TODO(M4): MLKit 얼굴검출 + 파라미터→이미지 렌더링 파이프라인 (로드맵 A7)
class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key, required this.sessionId, required this.photoId});

  final String sessionId;
  final String photoId;

  /// 전역 보정 슬라이더 구성 (백엔드 DEFAULT_GLOBAL_PARAMS 의 스칼라 항목).
  static const _globalControls = <_Control>[
    _Control('brightness', '밝기', Icons.brightness_6_outlined),
    _Control('contrast', '대비', Icons.contrast),
    _Control('saturation', '채도', Icons.water_drop_outlined),
    _Control('colorTemp', '색온도', Icons.thermostat_outlined),
    _Control('highlights', '하이라이트', Icons.wb_sunny_outlined),
    _Control('shadows', '그림자', Icons.nightlight_outlined),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(roomControllerProvider(sessionId));
    final controller = ref.read(roomControllerProvider(sessionId).notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('보정하기'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: '실행취소',
            onPressed: state.connection == RoomConnection.connected
                ? () => controller.undo(photoId)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: '다시하기',
            onPressed: state.connection == RoomConnection.connected
                ? () => controller.redo(photoId)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '내 갤러리에 저장',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('개인 저장은 렌더링 파이프라인 연동 후 지원돼요 (M4)')),
            ),
          ),
          // TODO(B7): 완료 체크 → 전원 완료 시 서버가 finalized 브로드캐스트
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('완료 확정은 백엔드 complete 프로토콜 연동 후 (B7)')),
            ),
            child: const Text('완료'),
          ),
        ],
      ),
      body: _body(context, ref, state, controller),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, RoomState state, RoomController controller) {
    switch (state.connection) {
      case RoomConnection.connecting:
      case RoomConnection.idle:
        return const Center(child: CircularProgressIndicator());
      case RoomConnection.needsJoin:
        return const _Notice(
          icon: Icons.link_off,
          message: '방에 참여해야 편집할 수 있어요.\n초대 링크로 다시 입장해 주세요.',
        );
      case RoomConnection.error:
        return _Notice(
          icon: Icons.wifi_off,
          message: '연결에 실패했어요.\n${state.error ?? ''}',
          onRetry: controller.bootstrap,
        );
      case RoomConnection.connected:
        break;
    }

    final photo = _photoOf(state);
    final editState = state.editStates[photoId];
    if (photo == null || editState == null) {
      return const _Notice(icon: Icons.image_not_supported_outlined, message: '사진을 찾을 수 없어요.');
    }

    return Column(
      children: [
        _presenceBar(context, state),
        Expanded(child: _canvas(context, photo)),
        _sliderPanel(context, state, controller, editState),
      ],
    );
  }

  Photo? _photoOf(RoomState state) {
    final photos = state.session?.photos ?? const <Photo>[];
    for (final p in photos) {
      if (p.id == photoId) return p;
    }
    return null;
  }

  /// 다른 참여자의 실시간 작업 상태 라벨.
  Widget _presenceBar(BuildContext context, RoomState state) {
    final others = state.presence.entries
        .where((e) => e.key != state.myMemberId && e.value.connected)
        .toList();
    if (others.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: others.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final memberId = others[i].key;
          final info = others[i].value;
          final nickname = _nicknameOf(state, memberId) ?? '참여자';
          final tool = info.tool;
          return Chip(
            visualDensity: VisualDensity.compact,
            avatar: CircleAvatar(
              backgroundColor: MemberColors.fromHex(null, fallbackSeed: memberId),
              radius: 8,
            ),
            label: Text(tool == null ? nickname : '$nickname — $tool 편집 중'),
          );
        },
      ),
    );
  }

  String? _nicknameOf(RoomState state, String memberId) {
    for (final m in state.session?.members ?? const <Member>[]) {
      if (m.id == memberId) return m.nickname;
    }
    return null;
  }

  Widget _canvas(BuildContext context, Photo photo) {
    final url = '${AppConfig.apiBaseUrl}${photo.url}';
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        // TODO(A7): 여기서 editState 파라미터를 ColorFilter/워핑으로 실제 반영.
        errorBuilder: (context, error, stack) => const _Notice(
          icon: Icons.broken_image_outlined,
          message: '사진을 불러오지 못했어요.',
        ),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : const CircularProgressIndicator(),
      ),
    );
  }

  Widget _sliderPanel(
    BuildContext context,
    RoomState state,
    RoomController controller,
    EditState editState,
  ) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SizedBox(
        height: 220,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final c in _globalControls)
              _GlobalSlider(
                control: c,
                value: (editState.valueAt('global.${c.key}') as num?)?.toDouble() ?? 0,
                lockedBy: _lockOwner(state, 'global.${c.key}'),
                onChanged: (v) {
                  controller.reportPresence(tool: c.label, region: 'global');
                  controller.editGlobal(photoId, c.key, v.round());
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 다른 사람이 잠근 파라미터면 그 색상을 반환(내 잠금/무잠금은 null).
  Color? _lockOwner(RoomState state, String path) {
    final owner = state.locks[path];
    if (owner == null || owner == state.myMemberId) return null;
    return MemberColors.fromHex(null, fallbackSeed: owner);
  }
}

class _Control {
  const _Control(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

class _GlobalSlider extends StatelessWidget {
  const _GlobalSlider({
    required this.control,
    required this.value,
    required this.onChanged,
    this.lockedBy,
  });

  final _Control control;
  final double value;
  final ValueChanged<double> onChanged;
  final Color? lockedBy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(control.icon, size: 20, color: lockedBy),
          const SizedBox(width: 8),
          SizedBox(width: 64, child: Text(control.label)),
          Expanded(
            child: Slider(
              min: -100,
              max: 100,
              value: value.clamp(-100, 100),
              label: value.round().toString(),
              divisions: 200,
              onChanged: lockedBy != null ? null : onChanged,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text('${value.round()}', textAlign: TextAlign.end),
          ),
        ],
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
