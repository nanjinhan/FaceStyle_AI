import 'package:flutter/material.dart';

import '../../../core/theme/member_colors.dart';
import '../../room/application/room_controller.dart';
import '../../room/domain/session_models.dart';

/// 사진 위에 얼굴 클레임 상자와 실시간 커서를 겹쳐 그리는 레이어 (M1 4단계).
///
/// - 얼굴 상자를 탭하면 "이게 나예요" 클레임 / 내 얼굴이면 해제
/// - 내 얼굴 = 실선 + 강조, 남의 얼굴 = 그 사람 색 + 잠금 아이콘, 빈 얼굴 = 점선
/// - 현재 편집 중인 얼굴은 굵은 테두리로 표시
/// - 다른 참여자의 커서(presence.cursor, 0~1 정규화)를 색상 점으로 표시
///
/// 서버가 준 얼굴 bbox는 **원본 이미지 픽셀 좌표**다. 이미지가 BoxFit.contain 으로
/// 레터박스되어 표시되므로, 실제 그려진 이미지 영역을 계산해 그 안으로 좌표를 매핑한다.
class FaceOverlay extends StatelessWidget {
  const FaceOverlay({
    super.key,
    required this.photo,
    required this.state,
    required this.controller,
    required this.selectedFaceKey,
    required this.onSelectFace,
  });

  final Photo photo;
  final RoomState state;
  final RoomController controller;

  /// 현재 얼굴별 슬라이더가 편집 중인 얼굴 (예: "face_0"). 없으면 null.
  final String? selectedFaceKey;
  final ValueChanged<String?> onSelectFace;

  @override
  Widget build(BuildContext context) {
    final imageSize = Size(photo.width.toDouble(), photo.height.toDouble());
    if (imageSize.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;
        // BoxFit.contain 으로 실제 그려지는 이미지 사각형을 계산한다.
        final fitted = applyBoxFit(BoxFit.contain, imageSize, box);
        final dest = fitted.destination;
        final rect = Alignment.center.inscribe(dest, Offset.zero & box);
        final scale = dest.width / imageSize.width; // 원본→화면 배율

        Offset toScreen(double px, double py) =>
            Offset(rect.left + px * scale, rect.top + py * scale);

        // 화면 좌표 → 이미지 기준 0~1 정규화 (커서 공유용)
        void reportCursor(Offset local) {
          if (!rect.contains(local)) return;
          final nx = ((local.dx - rect.left) / dest.width).clamp(0.0, 1.0);
          final ny = ((local.dy - rect.top) / dest.height).clamp(0.0, 1.0);
          controller.reportPresence(cursor: {'x': nx, 'y': ny});
        }

        return MouseRegion(
          onHover: (e) => reportCursor(e.localPosition),
          child: Stack(
            children: [
              for (final face in photo.faces)
                _faceBox(context, face, toScreen, scale),
              ..._cursors(context, toScreen, imageSize),
            ],
          ),
        );
      },
    );
  }

  Widget _faceBox(
    BuildContext context,
    Face face,
    Offset Function(double, double) toScreen,
    double scale,
  ) {
    final topLeft = toScreen(face.bbox[0].toDouble(), face.bbox[1].toDouble());
    final w = face.bbox[2] * scale;
    final h = face.bbox[3] * scale;

    final owner = face.claimedByMemberId;
    final isMine = owner != null && owner == state.myMemberId;
    final isTaken = owner != null && !isMine;
    final isSelected = face.pathKey == selectedFaceKey;

    final color = owner == null
        ? Colors.white
        : MemberColors.fromHex(null, fallbackSeed: owner);

    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: w,
      height: h,
      child: GestureDetector(
        onTap: () => _onTapFace(context, face, isMine, isTaken),
        onLongPress: isMine ? () => _confirmUnclaim(context, face) : null,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: color,
              width: isSelected ? 3.5 : 2,
            ),
            borderRadius: BorderRadius.circular(6),
            color: isMine ? color.withValues(alpha: 0.12) : null,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (isTaken)
                const Positioned(
                  right: 2,
                  top: 2,
                  child: Icon(Icons.lock, size: 16, color: Colors.white),
                ),
              // 빈 얼굴 안내 라벨
              if (owner == null)
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      color: Colors.black54,
                      child: const Text(
                        '이게 나예요',
                        style: TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _onTapFace(BuildContext context, Face face, bool isMine, bool isTaken) {
    if (isTaken) {
      final nick = _nicknameOf(face.claimedByMemberId) ?? '다른 참여자';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$nick 님의 얼굴이에요')));
      return;
    }
    if (isMine) {
      // 내 얼굴을 다시 탭 → 이 얼굴을 편집 대상으로 선택(토글). 길게 눌러야 클레임 해제.
      onSelectFace(face.pathKey == selectedFaceKey ? null : face.pathKey);
      return;
    }
    controller.claimFace(photo.id, face.id);
    onSelectFace(face.pathKey);
  }

  Future<void> _confirmUnclaim(BuildContext context, Face face) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('내 얼굴 선택을 해제할까요?'),
        content: const Text('해제하면 이 얼굴의 보정 권한이 사라지고, 다른 사람이 선택할 수 있어요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('해제')),
        ],
      ),
    );
    if (ok ?? false) {
      controller.unclaimFace(photo.id, face.id);
      if (selectedFaceKey == face.pathKey) onSelectFace(null);
    }
  }

  /// 다른 참여자의 커서를 색상 점 + 닉네임으로 그린다.
  List<Widget> _cursors(
    BuildContext context,
    Offset Function(double, double) toScreen,
    Size imageSize,
  ) {
    final widgets = <Widget>[];
    for (final entry in state.presence.entries) {
      if (entry.key == state.myMemberId || !entry.value.connected) continue;
      final cursor = entry.value.cursor;
      if (cursor == null) continue;
      // 정규화(0~1) → 원본 픽셀 → 화면 좌표
      final pos = toScreen(cursor.dx * imageSize.width, cursor.dy * imageSize.height);
      final color = MemberColors.fromHex(null, fallbackSeed: entry.key);
      final nick = _nicknameOf(entry.key) ?? '참여자';
      widgets.add(Positioned(
        left: pos.dx,
        top: pos.dy,
        child: IgnorePointer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.navigation, size: 18, color: color),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(nick, style: const TextStyle(color: Colors.white, fontSize: 10)),
              ),
            ],
          ),
        ),
      ));
    }
    return widgets;
  }

  String? _nicknameOf(String? memberId) {
    if (memberId == null) return null;
    for (final m in state.session?.members ?? const <Member>[]) {
      if (m.id == memberId) return m.nickname;
    }
    return null;
  }
}
