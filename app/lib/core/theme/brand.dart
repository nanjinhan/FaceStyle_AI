import 'package:flutter/material.dart';

/// FaceStyle 브랜드 아이덴티티 — 뷰티앱 감성의 보라→핑크 그라데이션.
abstract final class Brand {
  static const primary = Color(0xFF7C5CFF); // 보라
  static const secondary = Color(0xFFFF6FB5); // 핑크
  static const accent = Color(0xFF00D3C7); // 포인트 민트

  /// 브랜드 메인 그라데이션 (로고·CTA·스플래시).
  static const gradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// 은은한 배경 그라데이션 (로그인/스플래시 바탕).
  static const softGradient = LinearGradient(
    colors: [Color(0xFFF3EEFF), Color(0xFFFFF0F7)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const radius = 18.0;
  static const radiusLg = 24.0;
}

/// 브랜드 그라데이션 CTA 버튼. Material FilledButton은 그라데이션을 못 써서 직접 만든다.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.busy = false,
    this.gradient = Brand.gradient,
    this.height = 54,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool busy;
  final Gradient gradient;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(Brand.radius),
          onTap: enabled ? onPressed : null,
          child: Ink(
            height: height,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(Brand.radius),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: Brand.primary.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : DefaultTextStyle.merge(
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      child: IconTheme.merge(
                        data: const IconThemeData(color: Colors.white),
                        child: child,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 브랜드 그라데이션으로 칠해지는 텍스트(로고용).
class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, required this.style, this.gradient = Brand.gradient});

  final String text;
  final TextStyle style;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => gradient.createShader(bounds),
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}
