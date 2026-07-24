import 'package:flutter/material.dart';

import 'brand.dart';

/// FaceStyle 테마 — 보라(바이올렛) 브랜드 + 라벤더 표면 + 부드러운 라운드.
///
/// 예약앱류의 모던한 톤을 목표로 한다: 라벤더 화이트 배경, 화이트 카드,
/// 넉넉한 라운드(16~20px), 보라 포인트, 은은한 그림자. 색·형태 토큰은
/// [Brand] 를 원본으로 삼고, 여기서 Material 테마로 옮긴다.
abstract final class AppTheme {
  static const radius = 14.0; // 버튼·인풋 기본 라운드
  static const radiusLg = 20.0; // 카드 라운드

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isLight = b == Brightness.light;
    final bg = isLight ? Brand.canvasLight : Brand.canvasDark;
    final fg = isLight ? Brand.inkLight : Brand.inkDark;
    final card = isLight ? Brand.cardLight : Brand.cardDark;
    final muted = isLight ? Brand.violetSoft : Brand.cardDark;
    final mutedFg = isLight ? Brand.mutedInkLight : Brand.mutedInkDark;
    final border = isLight ? Brand.borderLight : Brand.borderDark;

    final scheme = ColorScheme(
      brightness: b,
      primary: Brand.violet,
      onPrimary: Colors.white,
      primaryContainer: Brand.violetSoft,
      onPrimaryContainer: Brand.violetDark,
      secondary: isLight ? Brand.violetSoft : Brand.cardDark,
      onSecondary: fg,
      surface: card,
      onSurface: fg,
      surfaceContainerLowest: bg,
      surfaceContainerLow: bg,
      surfaceContainer: muted,
      surfaceContainerHigh: muted,
      surfaceContainerHighest: muted,
      onSurfaceVariant: mutedFg,
      outline: border,
      outlineVariant: border,
      error: Brand.danger,
      onError: Colors.white,
    );

    RoundedRectangleBorder rr([double r = radius, BorderSide side = BorderSide.none]) =>
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(r), side: side);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      dividerColor: border,
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        elevation: 0,
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: fg,
        titleTextStyle: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      ),
      // 카드: 화이트 표면 + 큰 라운드 + 아주 옅은 테두리 (그림자는 위젯에서)
      cardTheme: CardThemeData(
        elevation: 0,
        color: card,
        shadowColor: Brand.violet.withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: rr(radiusLg, BorderSide(color: border)),
      ),
      // 기본 버튼 = 보라 solid, 넉넉한 라운드
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Brand.violet,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shape: rr(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Brand.violet,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: rr(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Brand.violetDark,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: isLight ? Brand.violetSoft : border),
          shape: rr(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Brand.violet,
          shape: rr(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      // 인풋: 옅은 라벤더/카드 채움 + 라운드, 포커스 시 보라 테두리
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? Brand.violetSoft.withValues(alpha: 0.4) : card,
        hintStyle: TextStyle(color: mutedFg),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: Brand.violet, width: 1.6)),
      ),
      // 칩: 알약형. 선택 시 보라 채움.
      chipTheme: ChipThemeData(
        backgroundColor: muted,
        selectedColor: Brand.violet,
        side: BorderSide.none,
        shape: rr(999),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        labelStyle: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? Brand.inkLight : Brand.cardDark,
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        shape: rr(radius),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: rr(radiusLg),
      ),
      listTileTheme: const ListTileThemeData(iconColor: Brand.violet),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: Brand.violet,
        foregroundColor: Colors.white,
        elevation: 4,
        highlightElevation: 4,
        shape: rr(18),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: Brand.violet),
    );
  }
}
