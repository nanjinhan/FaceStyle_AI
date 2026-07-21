import 'package:flutter/material.dart';

import '../../../core/theme/brand.dart';

/// 초기 로딩 화면. 저장된 로그인 토큰을 복원하는 동안(AuthStatus.unknown) 표시된다.
/// 복원이 끝나면 라우터가 홈 또는 로그인으로 보낸다.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: Brand.softGradient),
        child: Center(
          child: FadeTransition(
            opacity: _c,
            child: ScaleTransition(
              scale: Tween(begin: 0.85, end: 1.0).animate(
                CurvedAnimation(parent: _c, curve: Curves.easeOutBack),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      gradient: Brand.gradient,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Brand.primary.withValues(alpha: 0.4),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.auto_awesome, color: Colors.white, size: 48),
                  ),
                  const SizedBox(height: 24),
                  GradientText(
                    'FaceStyle',
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '친구들과 같이 보정하는 단체 사진',
                    style: TextStyle(color: Colors.black.withValues(alpha: 0.55)),
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
