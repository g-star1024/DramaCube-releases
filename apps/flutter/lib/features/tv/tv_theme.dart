import 'package:flutter/material.dart';

/// TV 主题令牌 —— Cinema Dark 影院深色（独立于三端移动/桌面）。
abstract final class TvColors {
  /// 背景：近黑暖调。
  static const Color background = Color(0xFF0E0D0B);

  /// 表面层。
  static const Color surface = Color(0xFF1A1815);

  /// 表面高亮层。
  static const Color surfaceHi = Color(0xFF26231F);

  /// 主文字色。
  static const Color onSurface = Color(0xFFEDE8E0);

  /// 弱文字色。
  static const Color muted = Color(0xFF8F887C);

  /// 焦点金辉光。
  static const Color focus = Color(0xFFFFD166);

  /// 焦点辉光强度（rgba）。
  static Color get focusGlow => focus.withValues(alpha: 0.45);
}

/// TV 安全区（10-foot UI）：上/下 60dp，左/右 80dp。
abstract final class TvSafeArea {
  static const double top = 60;
  static const double bottom = 60;
  static const double left = 80;
  static const double right = 80;

  static const EdgeInsets padding = EdgeInsets.only(
    top: top,
    bottom: bottom,
    left: left,
    right: right,
  );
}

/// TV 字阶（≥1.5x 桌面字号，10 英尺可读）。
abstract final class TvText {
  static const double hero = 34;
  static const double title = 26;
  static const double body = 20;
  static const double caption = 16;

  /// 焦点缩放倍率。
  static const double focusScale = 1.12;
}

/// TV 暗色主题（Material 3）。
ThemeData get tvTheme {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: TvColors.background,
    colorScheme: base.colorScheme.copyWith(
      surface: TvColors.surface,
      onSurface: TvColors.onSurface,
      primary: TvColors.focus,
      secondary: TvColors.surfaceHi,
      onSecondary: TvColors.onSurface,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: TvColors.onSurface,
      displayColor: TvColors.onSurface,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: TvColors.focus.withValues(alpha: 0.12),
  );
}
