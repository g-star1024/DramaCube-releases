import 'package:flutter/material.dart';

/// 主题（对齐 macOS 版轻主题 #F4F5FA + 24px 圆角美学）。
class AppTheme {
  AppTheme._();

  static const Color _background = Color(0xFFF4F5FA);
  static const Color _accent = Color(0xFFE94560); // 玫瑰金（对齐 macOS 版 Brand.accent）

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.light,
          surface: _background,
        ),
        scaffoldBackgroundColor: _background,
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _background,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.dark,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      );
}
