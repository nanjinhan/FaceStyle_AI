import 'package:flutter/material.dart';

/// 명세 2. 메인페이지 — 알림 목록 (업로드/완료/초대).
/// 정책: 알림 클릭 시 해당 사진/앨범으로 이동, 앨범별 on/off.
///
/// TODO(M3): GET /notifications 연동 + FCM 수신 (로드맵 B11, A4)
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('알림')),
      body: const Center(child: Text('알림 리스트 (TODO M3)')),
    );
  }
}
