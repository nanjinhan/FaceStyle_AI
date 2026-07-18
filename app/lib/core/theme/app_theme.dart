import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seed = Color(0xFF5A6AE8);

  static ThemeData get light => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        useMaterial3: true,
      );

  static ThemeData get dark => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
        useMaterial3: true,
      );
}
