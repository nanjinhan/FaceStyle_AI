import 'package:flutter/material.dart';

/// shadcn/ui 디자인 언어를 Flutter 테마로 옮긴 것.
/// 중립(zinc) 팔레트 · 얇은 1px 테두리 · 8px 라운드 · muted 보조텍스트 · 미니멀 컴포넌트.
///
/// shadcn은 React/Tailwind라 코드는 못 가져오고, 디자인 토큰과 컴포넌트 스타일을 재현한다.
abstract final class AppTheme {
  // ── shadcn 토큰 (zinc) ────────────────────────────────────────────────
  // Light
  static const _bgLight = Color(0xFFFFFFFF);
  static const _fgLight = Color(0xFF09090B); // zinc-950
  static const _mutedLight = Color(0xFFF4F4F5); // zinc-100
  static const _mutedFgLight = Color(0xFF71717A); // zinc-500
  static const _borderLight = Color(0xFFE4E4E7); // zinc-200
  static const _primaryLight = Color(0xFF18181B); // zinc-900
  // Dark
  static const _bgDark = Color(0xFF09090B);
  static const _fgDark = Color(0xFFFAFAFA);
  static const _cardDark = Color(0xFF18181B); // zinc-900
  static const _mutedDark = Color(0xFF27272A); // zinc-800
  static const _mutedFgDark = Color(0xFFA1A1AA); // zinc-400
  static const _borderDark = Color(0xFF27272A); // zinc-800
  static const _primaryDark = Color(0xFFFAFAFA);

  static const _danger = Color(0xFFEF4444);
  static const radius = 8.0; // shadcn --radius (rounded-lg 근처)

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isLight = b == Brightness.light;
    final bg = isLight ? _bgLight : _bgDark;
    final fg = isLight ? _fgLight : _fgDark;
    final card = isLight ? _bgLight : _cardDark;
    final muted = isLight ? _mutedLight : _mutedDark;
    final mutedFg = isLight ? _mutedFgLight : _mutedFgDark;
    final border = isLight ? _borderLight : _borderDark;
    final primary = isLight ? _primaryLight : _primaryDark;
    final onPrimary = isLight ? _bgLight : _fgLight;

    final scheme = ColorScheme(
      brightness: b,
      primary: primary,
      onPrimary: onPrimary,
      secondary: muted,
      onSecondary: fg,
      surface: bg,
      onSurface: fg,
      surfaceContainerHighest: muted,
      surfaceContainerHigh: muted,
      onSurfaceVariant: mutedFg,
      outline: border,
      outlineVariant: border,
      error: _danger,
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
        foregroundColor: fg,
        titleTextStyle: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.w600),
      ),
      // shadcn Card: 배경 카드색 + 1px 테두리 + 라운드, 그림자 없음
      cardTheme: CardThemeData(
        elevation: 0,
        color: card,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: rr(radius + 4, BorderSide(color: border)),
      ),
      // Button = default(solid primary)
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size.fromHeight(44),
          elevation: 0,
          shape: rr(),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size.fromHeight(44),
          elevation: 0,
          shape: rr(),
        ),
      ),
      // Button = outline
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          minimumSize: const Size.fromHeight(44),
          side: BorderSide(color: border),
          shape: rr(),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      // Button = ghost
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: fg,
          shape: rr(),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        hintStyle: TextStyle(color: mutedFg),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: BorderSide(color: fg, width: 1.5)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: muted,
        side: BorderSide(color: border),
        shape: rr(radius),
        labelStyle: TextStyle(color: fg, fontSize: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? _fgLight : _cardDark,
        contentTextStyle: TextStyle(color: isLight ? _bgLight : _fgDark),
        shape: rr(radius),
      ),
      listTileTheme: ListTileThemeData(iconColor: mutedFg),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 1,
      ),
    );
  }
}
