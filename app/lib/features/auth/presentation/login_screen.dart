import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/brand.dart';
import '../application/auth_controller.dart';

/// 명세 1. 회원관리 — 계정 가입 / 로그인.
///
/// 실제 소셜 로그인(카카오/Google/Apple)은 앱 키가 준비되면 붙인다(docs/출시-준비물.md).
/// 지금은 닉네임만으로 로그인하는 개발용 진입을 제공한다(백엔드 social-login 스텁).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _nickname = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final nickname = _nickname.text.trim();
    if (nickname.isEmpty) {
      setState(() => _error = '닉네임을 입력해주세요');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signInWithNickname(nickname);
      if (mounted) context.go('/home');
    } catch (e) {
      // 원인 파악을 위해 실제 예외를 그대로 보여준다 (안정화되면 친절한 문구로 교체)
      if (mounted) setState(() => _error = '로그인 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: Brand.softGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        gradient: Brand.gradient,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Brand.primary.withValues(alpha: 0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 42),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: GradientText(
                      'FaceStyle',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '친구들과 같이 보정하는 단체 사진',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black.withValues(alpha: 0.55)),
                  ),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _nickname,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _start(),
                    decoration: InputDecoration(
                      labelText: '닉네임',
                      hintText: '환영해요! 사용할 닉네임을 정해주세요',
                      prefixIcon: const Icon(Icons.person_outline),
                      errorText: _error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GradientButton(
                    onPressed: _start,
                    busy: _busy,
                    child: const Text('시작하기'),
                  ),
                  const SizedBox(height: 24),
                  // 실제 소셜 로그인은 키 준비 후 (docs/출시-준비물.md M2)
                  Text(
                    '카카오·구글 로그인은 준비 중이에요',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.4)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
