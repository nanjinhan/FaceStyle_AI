import 'package:flutter/material.dart';

/// 명세 2. 메인페이지 — 인앱 카메라.
///
/// TODO(M4): camera 패키지 연동, 촬영 → 방/앨범 업로드 플로우 (로드맵 A3)
class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('촬영')),
      body: const Center(child: Text('인앱 카메라 (TODO M4)')),
    );
  }
}
