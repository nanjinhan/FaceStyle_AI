import 'package:flutter/material.dart';

/// FaceStyle 브랜드 아이덴티티 — 보라(바이올렛) 계열의 부드러운 모던 톤.
///
/// 예약앱류의 라벤더 배경 + 화이트 카드 + 보라 그라데이션 CTA 느낌을 목표로 한다.
/// 색·그라데이션·그림자 토큰의 원본(source of truth). 테마([AppTheme])와
/// 공용 위젯([ShadButton]/[ShadCard]/[BrandMark])이 여기서 값을 가져다 쓴다.
abstract final class Brand {
  // ── 코어 보라 ─────────────────────────────────────────────────────────
  static const violet = Color(0xFF7C5CFC); // 메인 보라 (버튼/포인트)
  static const violetDark = Color(0xFF6A45F0); // 눌림/짙은 톤
  static const violetLight = Color(0xFFA78BFA); // 밝은 보라 (그라데이션 끝)
  static const violetSoft = Color(0xFFEDE9FE); // 아주 옅은 보라 (선택 배경/토큰)

  // ── 라벤더 표면 ───────────────────────────────────────────────────────
  static const canvasLight = Color(0xFFF6F5FD); // 화면 배경 (라벤더 화이트)
  static const cardLight = Color(0xFFFFFFFF);
  static const borderLight = Color(0xFFECEAF6); // 아주 옅은 테두리
  static const inkLight = Color(0xFF1B1B2F); // 본문 (딥 인디고블랙)
  static const mutedInkLight = Color(0xFF8A8AA3); // 보조 텍스트

  // ── 다크 ──────────────────────────────────────────────────────────────
  static const canvasDark = Color(0xFF14131F);
  static const cardDark = Color(0xFF1E1C2E);
  static const borderDark = Color(0xFF2C2A3D);
  static const inkDark = Color(0xFFF4F3FB);
  static const mutedInkDark = Color(0xFF9B98B5);

  static const danger = Color(0xFFF43F5E);

  /// 메인 CTA·로고에 쓰는 보라 그라데이션 (좌상 → 우하).
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violetLight, violet],
  );

  /// 화면 배경에 은은하게 까는 라벤더 그라데이션.
  static const canvasGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF3EEFF), canvasLight],
  );

  /// 카드·버튼에 쓰는 보라빛 소프트 섀도.
  static List<BoxShadow> softShadow({double y = 10, double blur = 30, double opacity = 0.10}) => [
        BoxShadow(
          color: violet.withValues(alpha: opacity),
          blurRadius: blur,
          offset: Offset(0, y),
        ),
      ];
}
