import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../core/platform/image_saver.dart';
import '../../../core/theme/member_colors.dart';
import '../../room/application/room_controller.dart';
import '../../room/domain/session_models.dart';
import '../rendering/face_warp.dart';
import '../rendering/photo_exporter.dart';
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
  /// 지금 얼굴별 슬라이더가 편집 중인 얼굴 키 (= 서버 Face id). null이면 전역 보정 모드.
  String? _selectedFaceKey;

  /// 선택된 카테고리 index / 카테고리별로 마지막에 고른 항목 key.
  int _categoryIndex = 0;
  final Map<int, String> _itemPerCategory = {};

  /// 편집 거부 스낵바 스팸 방지용.
  String? _lastReason;
  DateTime? _lastRejectAt;

  /// 저장(다운로드) 진행 중 여부.
  bool _saving = false;

  String get sessionId => widget.sessionId;
  String get photoId => widget.photoId;

  /// 보정 카테고리 구성 — 상용 보정 앱과 같은 탭 구조.
  /// isFace=false 는 global.*, true 는 faces.{face}.* 파라미터를 조절한다.
  /// (백엔드 DEFAULT_GLOBAL_PARAMS / DEFAULT_FACE_PARAMS 의 키와 1:1)
  static const _categories = <_EditCategory>[
    _EditCategory('보정', false, [
      _Control('brightness', '밝기', Icons.brightness_6_outlined),
      _Control('contrast', '대비', Icons.contrast),
      _Control('saturation', '채도', Icons.water_drop_outlined),
      _Control('colorTemp', '색온도', Icons.thermostat_outlined),
      _Control('highlights', '하이라이트', Icons.wb_sunny_outlined),
      _Control('shadows', '그림자', Icons.nightlight_outlined),
    ]),
    _EditCategory('피부', true, [
      _Control('skinSmooth', '피부 매끈', Icons.blur_on),
      _Control('blemishRemoval', '잡티 제거', Icons.healing_outlined),
      _Control('skinTone', '피부 톤', Icons.face_retouching_natural),
    ]),
    _EditCategory('얼굴형', true, [
      _Control('faceSlim', '얼굴 축소', Icons.compress),
      _Control('jawSlim', '턱선', Icons.face_outlined),
      _Control('cheekbone', '광대', Icons.face_2_outlined),
    ]),
    _EditCategory('눈', true, [
      _Control('eyeScale', '눈 크기', Icons.remove_red_eye_outlined),
    ]),
    _EditCategory('코', true, [
      _Control('noseHeight', '코 높이', Icons.arrow_upward),
      _Control('noseWidth', '코 너비', Icons.unfold_more),
    ]),
    _EditCategory('입', true, [
      _Control('lipScale', '입술 크기', Icons.face_3_outlined),
      _Control('lipColor', '입술 색', Icons.color_lens_outlined),
    ]),
  ];

  _EditCategory get _category => _categories[_categoryIndex];

  /// 현재 카테고리에서 선택된 항목 (기본: 첫 번째).
  _Control get _item {
    final key = _itemPerCategory[_categoryIndex];
    return _category.items.firstWhere((c) => c.key == key, orElse: () => _category.items.first);
  }

  /// 현재 조절 대상 파라미터 경로. 편집 불가 상태면 null.
  String? get _paramPath {
    if (!_category.isFace) return 'global.${_item.key}';
    if (_selectedFaceKey == null) return null;
    return 'faces.$_selectedFaceKey.${_item.key}';
  }

  /// 지금 얼굴 편집이 막힌 이유(안내 문구). 편집 가능하면 null.
  /// 여기서 미리 막아 서버로 거부될 편집을 아예 보내지 않는다(불필요한 알림 방지).
  String? _faceBlockReason(RoomState state, Photo photo) {
    if (!_category.isFace) return null; // 전역 보정
    if (_selectedFaceKey == null) return '사진에서 내 얼굴을 탭한 뒤 보정할 수 있어요';
    for (final f in photo.faces) {
      if (f.pathKey == _selectedFaceKey) {
        if (f.claimedByMemberId == state.myMemberId) return null; // 내 얼굴 → 편집 가능
        return '내 얼굴만 보정할 수 있어요. 얼굴을 탭해 "이게 나예요"를 눌러주세요';
      }
    }
    return '얼굴을 다시 선택해 주세요';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(roomControllerProvider(sessionId));
    final controller = ref.read(roomControllerProvider(sessionId).notifier);

    // 서버가 편집을 거부하면 그 이유를 알려준다 ("OO님의 영역이에요" 등).
    ref.listen(roomControllerProvider(sessionId), (prev, next) {
      final reason = next.rejection;
      if (reason == null) return;
      controller.clearRejection();
      // 같은 사유가 3초 안에 또 오면 무시 (슬라이더 드래그로 거부가 연속될 때 스팸 방지).
      final now = DateTime.now();
      if (_lastReason == reason &&
          _lastRejectAt != null &&
          now.difference(_lastRejectAt!) < const Duration(seconds: 3)) {
        return;
      }
      _lastReason = reason;
      _lastRejectAt = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(reason), duration: const Duration(seconds: 2)));
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
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            tooltip: '내 갤러리에 저장',
            onPressed: (state.connection == RoomConnection.connected && !_saving)
                ? () => _save(context, state)
                : null,
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

  /// 현재 보정 상태를 원본 해상도로 렌더링해 기기에 저장(웹은 다운로드).
  Future<void> _save(BuildContext context, RoomState state) async {
    final photo = _photoOf(state);
    final editState = state.editStates[photoId];
    if (photo == null || editState == null || photo.width == 0) return;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = '${AppConfig.apiBaseUrl}${photo.url}';
      final image = await _loadImage(url);
      final warps = <FaceWarp>[
        for (final f in photo.faces)
          if (f.landmarks != null)
            FaceWarp(
              landmarks: f.landmarks!,
              params: (k) => (editState.valueAt('faces.${f.pathKey}.$k') as num?)?.toDouble() ?? 0,
            ),
      ];
      final bytes = await PhotoExporter.renderPng(
        image: image,
        imageSize: Size(photo.width.toDouble(), photo.height.toDouble()),
        warps: warps,
        colorMatrix: PhotoFilter.fromEditState(editState),
      );
      await saveImageBytes(bytes, 'facestyle_${DateTime.now().millisecondsSinceEpoch}.png');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('내 갤러리에 저장했어요')));
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('저장하지 못했어요: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<ui.Image> _loadImage(String url) {
    final completer = Completer<ui.Image>();
    final stream = NetworkImage(url).resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (e, _) {
        completer.completeError(e);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
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
    // 각 얼굴의 랜드마크 + 얼굴 파라미터로 워핑 입력을 만든다.
    final warps = <FaceWarp>[
      for (final f in photo.faces)
        if (f.landmarks != null)
          FaceWarp(
            landmarks: f.landmarks!,
            params: (key) => (editState.valueAt('faces.${f.pathKey}.$key') as num?)?.toDouble() ?? 0,
          ),
    ];
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _CompareOnHold(
            editState: editState,
            imageSize: Size(photo.width.toDouble(), photo.height.toDouble()),
            url: url,
            warps: warps,
          ),
          // 얼굴 상자 + 클레임 + 실시간 커서
          FaceOverlay(
            photo: photo,
            state: state,
            controller: controller,
            selectedFaceKey: _selectedFaceKey,
            onSelectFace: (key) => setState(() {
              _selectedFaceKey = key;
              // 얼굴을 고르면 얼굴 카테고리로, 해제하면 전체 보정으로 자동 전환.
              if (key != null && !_category.isFace) {
                _categoryIndex = 1; // 피부
              } else if (key == null && _category.isFace) {
                _categoryIndex = 0; // 보정(전역)
              }
            }),
          ),
        ],
      ),
    );
  }

  /// 하단 편집 패널 — 상용 보정 앱 구조:
  /// [슬라이더 1개] → [카테고리 탭] → [항목 아이콘 칩들]
  Widget _sliderPanel(
    BuildContext context,
    RoomState state,
    RoomController controller,
    EditState editState,
    Photo photo,
  ) {
    final finalized = state.completionOf(photoId).finalized;
    // 편집이 막힌 경우 슬라이더 대신 안내만 → 거부될 편집을 서버로 보내지 않는다.
    final blockReason = _faceBlockReason(state, photo);
    final path = blockReason == null ? _paramPath : null;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sliderRow(context, state, controller, editState, finalized, path, blockReason),
            const Divider(height: 1),
            _categoryTabs(context),
            _itemChips(context, editState),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  /// 선택된 항목 하나만 조절하는 슬라이더 줄.
  Widget _sliderRow(
    BuildContext context,
    RoomState state,
    RoomController controller,
    EditState editState,
    bool finalized,
    String? path,
    String? blockReason,
  ) {
    // 편집 불가 → 슬라이더 대신 안내 (편집 요청을 서버로 보내지 않음).
    if (path == null) {
      return SizedBox(
        height: 56,
        child: Center(
          child: Text(
            blockReason ?? '사진에서 내 얼굴을 탭한 뒤 보정할 수 있어요',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final value = (editState.valueAt(path) as num?)?.toDouble() ?? 0;
    final lockedBy = finalized ? Theme.of(context).disabledColor : _lockOwner(state, path);
    final locked = lockedBy != null;

    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: Text(_item.label, style: const TextStyle(fontSize: 12), maxLines: 2),
          ),
          Expanded(
            child: Slider(
              min: -100,
              max: 100,
              value: value.clamp(-100, 100),
              label: value.round().toString(),
              divisions: 200,
              onChanged: locked
                  ? null
                  : (v) {
                      controller.reportPresence(
                        tool: _item.label,
                        region: _category.isFace ? _selectedFaceKey : 'global',
                      );
                      controller.edit(photoId, path, v.round());
                    },
            ),
          ),
          SizedBox(width: 36, child: Text('${value.round()}', textAlign: TextAlign.end)),
          // 이 항목만 원본으로 (기능별 리셋)
          SizedBox(
            width: 40,
            child: (value.round() != 0 && !locked)
                ? IconButton(
                    icon: const Icon(Icons.restart_alt, size: 18),
                    tooltip: '${_item.label}만 초기화',
                    onPressed: () => controller.resetParam(photoId, path),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  /// 카테고리 탭 (보정 | 피부 | 얼굴형 | 눈 | 코 | 입).
  Widget _categoryTabs(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _categories.length,
        itemBuilder: (context, i) {
          final selected = i == _categoryIndex;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: InkWell(
              onTap: () => setState(() => _categoryIndex = i),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color: selected ? scheme.primary : Colors.transparent,
                    ),
                  ),
                ),
                child: Text(
                  _categories[i].label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 현재 카테고리의 항목 아이콘 칩들. 값이 0이 아닌 항목엔 점 표시.
  Widget _itemChips(BuildContext context, EditState editState) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 72,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _category.items.length,
        itemBuilder: (context, i) {
          final item = _category.items[i];
          final selected = item.key == _item.key;
          final itemPath = _category.isFace
              ? (_selectedFaceKey == null ? null : 'faces.$_selectedFaceKey.${item.key}')
              : 'global.${item.key}';
          final touched = itemPath != null &&
              ((editState.valueAt(itemPath) as num?)?.toDouble() ?? 0).round() != 0;

          return InkWell(
            onTap: () => setState(() => _itemPerCategory[_categoryIndex] = item.key),
            child: SizedBox(
              width: 72,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        item.icon,
                        size: 26,
                        color: selected ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                      if (touched)
                        Positioned(
                          right: -4,
                          top: -2,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: selected ? scheme.primary : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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

/// 사진을 전역 색보정(ColorFilter) + 얼굴 워핑으로 렌더링한다.
/// 길게 누르는 동안에는 보정을 전부 끄고 원본을 보여준다 (보정 전/후 비교).
class _CompareOnHold extends StatefulWidget {
  const _CompareOnHold({
    required this.editState,
    required this.imageSize,
    required this.url,
    required this.warps,
  });

  final EditState editState;
  final Size imageSize;
  final String url;
  final List<FaceWarp> warps;

  @override
  State<_CompareOnHold> createState() => _CompareOnHoldState();
}

class _CompareOnHoldState extends State<_CompareOnHold> {
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    final warpImage = FaceWarpImage(
      url: widget.url,
      imageSize: widget.imageSize,
      warps: _showOriginal ? const [] : widget.warps,
      errorBuilder: (_) => const _Notice(
        icon: Icons.broken_image_outlined,
        message: '사진을 불러오지 못했어요.',
      ),
    );
    return GestureDetector(
      onLongPressStart: (_) => setState(() => _showOriginal = true),
      onLongPressEnd: (_) => setState(() => _showOriginal = false),
      onLongPressCancel: () => setState(() => _showOriginal = false),
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          FilteredPhoto(
            editState: _showOriginal ? null : widget.editState,
            child: warpImage,
          ),
          if (_showOriginal)
            const Positioned(
              top: 12,
              child: Chip(visualDensity: VisualDensity.compact, label: Text('원본')),
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

/// 보정 카테고리 (탭 하나). isFace 면 얼굴을 선택해야 조절할 수 있다.
class _EditCategory {
  const _EditCategory(this.label, this.isFace, this.items);
  final String label;
  final bool isFace;
  final List<_Control> items;
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
