import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 명세 2. 메인페이지 (홈).
///  - 내 앨범 목록 + 최근 작업 사진, 무한 스크롤 (로드맵 A2, B12)
///  - 할 일 배너: "친구들이 기다리고 있어요! 보정할 사진 N장" (0장이면 미노출)
///  - 같이 보정하기(실시간 방 생성), 카메라 진입, 알림
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
          // TODO(M2): 할 일 배너 — 보정 대기 N장 (0장이면 숨김)
          Card(
            child: ListTile(
              leading: const Icon(Icons.face_retouching_natural),
              title: const Text('친구들이 기다리고 있어요! 보정할 사진 N장'),
              onTap: () {},
            ),
          ),
          const SizedBox(height: 16),
          const Text('내 앨범', style: TextStyle(fontWeight: FontWeight.bold)),
          // TODO(M3): 앨범 카드 리스트 (GET /albums, 무한 스크롤)
          Card(
            child: ListTile(
              title: const Text('예시 앨범 (제주 여행)'),
              subtitle: const Text('앨범 상세로 이동'),
              onTap: () => context.push('/albums/demo'),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'camera',
            onPressed: () => context.push('/camera'),
            child: const Icon(Icons.photo_camera),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'room',
            // TODO(M1): POST /sessions 로 방 생성 후 초대 링크 화면으로
            onPressed: () => context.push('/rooms/demo'),
            label: const Text('같이 보정하기'),
            icon: const Icon(Icons.group),
          ),
        ],
      ),
    );
  }
}
