import 'package:flutter/material.dart';

/// 명세 1. 회원관리 — 계정 (로그아웃 / 탈퇴).
/// 정책: 탈퇴 시 본인이 방장인 앨범은 위임 또는 삭제 선택 필수 (로드맵 B2).
///
/// TODO(M2): 닉네임 변경, 고유 색상 표시, 로그아웃, 탈퇴 플로우
/// 탈퇴 확인 문구: "보정 기록과 앨범 접근 권한이 사라져요"
class MyPageScreen extends StatelessWidget {
  const MyPageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('마이페이지')),
      body: ListView(
        children: const [
          ListTile(leading: Icon(Icons.edit), title: Text('닉네임 변경')),
          ListTile(leading: Icon(Icons.logout), title: Text('로그아웃')),
          ListTile(leading: Icon(Icons.delete_forever), title: Text('회원 탈퇴')),
        ],
      ),
    );
  }
}
