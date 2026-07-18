import 'package:flutter/material.dart';

/// 명세 4. 앨범 (비동기 협업).
///  - 사진별 상태 뱃지: 대기중/보정중/완료 (예: 2/3 완료) — 클레임 인원 기준
///  - 할 일 필터: "내가 보정할 사진" (최신순/할일순)
///  - 업로드(전체 멤버), 멤버 관리(초대/내보내기/위임 — 방장), 방장 마감
///
/// TODO(M3): GET /albums/{id} 연동, 사진 그리드 + 상태 뱃지 (로드맵 B10, A8)
/// TODO(M3): 사진 탭 → 에디터 진입 (실시간 방과 동일 권한 정책)
/// TODO(M3): 업로드 푸시 알림 "수진님이 사진 3장을 올렸어요" (B11)
class AlbumDetailScreen extends StatelessWidget {
  const AlbumDetailScreen({super.key, required this.albumId});

  final String albumId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('앨범 $albumId'),
        actions: [
          IconButton(icon: const Icon(Icons.filter_list), onPressed: () {/* 내가 보정할 사진 필터 */}),
          IconButton(icon: const Icon(Icons.group), onPressed: () {/* 멤버 관리 */}),
        ],
      ),
      body: const Center(child: Text('사진 그리드 + 상태 뱃지 (TODO M3)')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {/* 사진 업로드 */},
        child: const Icon(Icons.add_photo_alternate),
      ),
    );
  }
}
