import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../core/theme/member_colors.dart';
import '../../room/application/room_controller.dart';
import '../../room/domain/session_models.dart';
import '../rendering/photo_filter.dart';
import 'face_overlay.dart';

/// 명세 3·4 공용 보정 에디터. 실시간 방과 앨범 비동기 보정이 같은 화면을 쓴다.
///
/// 이번 슬라이스(M1)에서 구현:
///  - RoomSocket state_sync → 전역 파라미터 슬라이더에 반영, 값 변경 시 edit 전송
///  - 다른 참여자 프레즌스: "OO — △△ 편집 중" 라벨 + 실시간 커서
///  - undo/redo, 기능별 리셋, 완료 확정
///  - 전역 파라미터 → 이미지 실시간 렌더링 (A7, `rendering/photo_filter.dart`)
///  - 얼굴 클레임("이게 나예요") + 본인/타인 영역 잠금 표시 + 얼굴별 파라미터
/// TODO(M4): 얼굴별 워핑·스무딩을 실제 픽셀에 렌더링 (지금은 파라미터 값만 동기화)
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.sessionId, required this.photoId});

  final String sessionId;
  final String photoId;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  /// 지금 얼굴별 슬라이더가 편집 중인 얼굴 키 (예: "face_0"). null이면 전역 보정 모드.
  String? _selectedFaceKey;

  String get sessionId => widget.sessionId;
  String get photoId => widget.photoId;

  /// 전역 보정 슬라이더 구성 (백엔드 DEFAULT_GLOBAL_PARAMS 의 스칼라 항목).
  static const _globalControls = <_Control>[
    _Control('brightness', '밝기', Icons.brightness_6_outlined),
    _Control('contrast', '대비', Icons.contrast),
    _Control('saturation', '채도', Icons.water_drop_outlined),
    _Control('colorTemp', '색온도', Icons.thermostat_outlined),
    _Control('highlights', '하이라이트', Icons.wb_sunny_outlined),
    _Control('shadows', '그림자', Icons.nightlight_outlined),
  ];

  /// 얼굴별 보정 슬라이더 (백엔드 DEFAULT_FACE_PARAMS).
  static const _faceControls = <_Control>[
    _Control('skinSmooth', '피부 매끈', Icons.blur_on),
    _Control('blemishRemoval', '잡티 제거', Icons.healing_outlined),
    _Control('skinTone', '피부 톤', Icons.face_retouching_natural),
    _Control('jawSlim', '턱선', Icons.face_outlined),
    _Control('faceSlim', '얼굴 축소', Icons.compress),
    _Control('cheekbone', '광대', Icons.face_2_outlined),
    _Control('eyeScale', '눈 크기', Icons.remove_red_eye_outlined),
    _Control('noseHeight', '코 높이', Icons.arrow_upward),
    _Control('noseWidth', '코 너비', Icons.unfold_more),
    _Control('lipScale', '입술 크기', Icons.face_3_outlined),
    _Control('lipColor', '입술 색', Icons.color_lens_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(roomControllerProvider(sessionId));
    final controller = ref.read(roomControllerProvider(sessionId).notifier);

    // 서버가 편집을 거부하면 그 이유를 알려준다 ("OO님의 영역이에요" 등).
    ref.listen(roomControllerProvider(sessionId), (prev, next) {
      final reason = next.rejection;
      if (reason == null || reason == prev?.rejection) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(reason)));
      controller.clearRejection();
    });

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
          _completeButton(context, state, controller),
        ],
      ),
      body: _body(context, ref, state, controller),
    );
  }

  /// 완료 체크 버튼. 전원이 누르면 서버가 최종본을 확정한다.
  Widget _completeButton(BuildContext context, RoomState state, RoomController controller) {
    final completion = state.completionOf(photoId);
    if (completion.finalized) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Center(child: Text('확정됨')),
      );
    }

    final iAmDone = completion.isDoneBy(state.myMemberId);
    // 얼굴을 지정하지 않은 사람은 완료 대상이 아니다 (서버도 같은 기준으로 거부한다).
    final canComplete = completion.isRequiredOf(state.myMemberId);

    return TextButton.icon(
      onPressed: canComplete
          ? () => controller.setComplete(photoId, done: !iAmDone)
          : () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('먼저 "이게 나예요"로 내 얼굴을 지정해주세요')),
              ),
      icon: Icon(iAmDone ? Icons.check_circle : Icons.check_circle_outline),
      label: Text(iAmDone ? '완료함' : '완료'),
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

    // 클레임이 풀린(또는 남에게 넘어간) 얼굴을 편집 중이었다면 선택 해제.
    if (_selectedFaceKey != null) {
      final face = _faceByKey(photo, _selectedFaceKey!);
      if (face == null || face.claimedByMemberId != state.myMemberId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedFaceKey = null);
        });
      }
    }

    return Column(
      children: [
        _presenceBar(context, state),
        _completionBar(context, state),
        Expanded(child: _canvas(context, state, controller, photo, editState)),
        _sliderPanel(context, state, controller, editState, photo),
      ],
    );
  }

  Face? _faceByKey(Photo photo, String key) {
    for (final f in photo.faces) {
      if (f.pathKey == key) return f;
    }
    return null;
  }

  /// 완료 현황 — "2/3 완료" + 누가 아직인지. 확정되면 잠금 안내로 바뀐다.
  Widget _completionBar(BuildContext context, RoomState state) {
    final completion = state.completionOf(photoId);
    if (completion.hasNobody) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    if (completion.finalized) {
      return Container(
        width: double.infinity,
        color: scheme.primaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 18, color: scheme.onPrimaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '모두 완료! 최종본이 저장됐어요',
                style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    final waiting = completion.requiredMembers
        .where((id) => !completion.completed.contains(id))
        .map((id) => _nicknameOf(state, id) ?? '참여자')
        .toList();

    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '${completion.doneCount}/${completion.totalCount} 완료',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              waiting.isEmpty ? '확정하는 중…' : '${waiting.join(", ")} 님을 기다리는 중',
              style: TextStyle(color: scheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
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

  /// 원본 이미지에 전역 보정 파라미터를 실시간 적용해 보여준다 (A7) + 얼굴 클레임 오버레이.
  ///
  /// 길게 누르면 보정 전 원본과 비교할 수 있다.
  Widget _canvas(
    BuildContext context,
    RoomState state,
    RoomController controller,
    Photo photo,
    EditState editState,
  ) {
    final url = '${AppConfig.apiBaseUrl}${photo.url}';
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _CompareOnHold(
            editState: editState,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => const _Notice(
                icon: Icons.broken_image_outlined,
                message: '사진을 불러오지 못했어요.',
              ),
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : const CircularProgressIndicator(),
            ),
          ),
          // 얼굴 상자 + 클레임 + 실시간 커서
          FaceOverlay(
            photo: photo,
            state: state,
            controller: controller,
            selectedFaceKey: _selectedFaceKey,
            onSelectFace: (key) => setState(() => _selectedFaceKey = key),
          ),
        ],
      ),
    );
  }

  Widget _sliderPanel(
    BuildContext context,
    RoomState state,
    RoomController controller,
    EditState editState,
    Photo photo,
  ) {
    final finalized = state.completionOf(photoId).finalized;
    final editingFace = _selectedFaceKey != null;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SizedBox(
        height: 240,
        child: Column(
          children: [
            _panelHeader(context, state, editingFace),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: editingFace
                    ? [
                        for (final c in _faceControls)
                          _slider(context, state, controller, editState, finalized,
                              'faces.$_selectedFaceKey.${c.key}', c),
                      ]
                    : [
                        for (final c in _globalControls)
                          _slider(context, state, controller, editState, finalized,
                              'global.${c.key}', c),
                      ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 슬라이더 패널 상단 — 전역/얼굴 모드 전환 표시.
  Widget _panelHeader(BuildContext context, RoomState state, bool editingFace) {
    if (!editingFace) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          children: [
            Icon(Icons.public, size: 16),
            SizedBox(width: 6),
            Text('전체 보정', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(width: 8),
            Expanded(child: Text('얼굴을 탭해 내 얼굴을 보정하세요', style: TextStyle(fontSize: 12))),
          ],
        ),
      );
    }
    final color = MemberColors.fromHex(null, fallbackSeed: state.myMemberId ?? '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Icon(Icons.face, size: 16, color: color),
          const SizedBox(width: 6),
          const Text('내 얼굴 보정', style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() => _selectedFaceKey = null),
            child: const Text('전체 보정으로'),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    BuildContext context,
    RoomState state,
    RoomController controller,
    EditState editState,
    bool finalized,
    String path,
    _Control c,
  ) {
    final region = path.startsWith('faces.') ? _selectedFaceKey : 'global';
    return _GlobalSlider(
      control: c,
      value: (editState.valueAt(path) as num?)?.toDouble() ?? 0,
      lockedBy: finalized ? Theme.of(context).disabledColor : _lockOwner(state, path),
      onChanged: (v) {
        controller.reportPresence(tool: c.label, region: region);
        controller.edit(photoId, path, v.round());
      },
      onReset: finalized ? null : () => controller.resetParam(photoId, path),
    );
  }

  /// 다른 사람이 잠근 파라미터면 그 색상을 반환(내 잠금/무잠금은 null).
  Color? _lockOwner(RoomState state, String path) {
    final owner = state.locks[path];
    if (owner == null || owner == state.myMemberId) return null;
    return MemberColors.fromHex(null, fallbackSeed: owner);
  }
}

/// 길게 누르는 동안 보정을 끄고 원본을 보여준다 (보정 전/후 비교).
class _CompareOnHold extends StatefulWidget {
  const _CompareOnHold({required this.editState, required this.child});

  final EditState editState;
  final Widget child;

  @override
  State<_CompareOnHold> createState() => _CompareOnHoldState();
}

class _CompareOnHoldState extends State<_CompareOnHold> {
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => setState(() => _showOriginal = true),
      onLongPressEnd: (_) => setState(() => _showOriginal = false),
      onLongPressCancel: () => setState(() => _showOriginal = false),
      child: Stack(
        alignment: Alignment.center,
        children: [
          FilteredPhoto(
            editState: _showOriginal ? null : widget.editState,
            child: widget.child,
          ),
          if (_showOriginal)
            const Positioned(
              top: 12,
              child: Chip(
                visualDensity: VisualDensity.compact,
                label: Text('원본'),
              ),
            ),
        ],
      ),
    );
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
    this.onReset,
  });

  final _Control control;
  final double value;
  final ValueChanged<double> onChanged;
  final Color? lockedBy;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final locked = lockedBy != null;
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
              onChanged: locked ? null : onChanged,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text('${value.round()}', textAlign: TextAlign.end),
          ),
          // 값이 0이 아닐 때만 리셋 버튼을 노출한다.
          SizedBox(
            width: 40,
            child: (value.round() != 0 && !locked && onReset != null)
                ? IconButton(
                    icon: const Icon(Icons.restart_alt, size: 18),
                    tooltip: '${control.label}만 초기화',
                    onPressed: onReset,
                  )
                : null,
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
