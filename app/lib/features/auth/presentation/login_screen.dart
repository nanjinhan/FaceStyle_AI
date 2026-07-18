import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 명세 1. 회원관리 — 계정 가입 / 로그인.
///
/// TODO(M2): 소셜 로그인(카카오/Google/Apple) 연동 → POST /auth/login (로드맵 B13, A1)
/// TODO(M2): 초대 링크로 진입한 게스트는 로그인 없이 닉네임만 입력하고 입장 (A10)
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'FaceStyle',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('친구들과 같이 보정하는 단체 사진', textAlign: TextAlign.center),
              const SizedBox(height: 48),
              FilledButton(
                onPressed: () => context.go('/nickname'),
                child: const Text('시작하기 (로그인 TODO)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
