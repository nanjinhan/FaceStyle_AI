import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 명세 1. 회원관리 — 닉네임 설정.
/// 정책: 닉네임 중복 허용 (구분은 유저 고유 색상으로).
///
/// TODO(M2): 저장 API 연동, 가입 직후엔 "환영해요! 사용할 닉네임을 정해주세요" 문구 노출
class NicknameScreen extends StatelessWidget {
  const NicknameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('닉네임 설정')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TextField(
              decoration: InputDecoration(
                labelText: '닉네임',
                helperText: '닉네임은 언제든 바꿀 수 있어요',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/home'),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }
}
