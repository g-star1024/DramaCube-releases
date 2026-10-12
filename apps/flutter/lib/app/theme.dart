import 'package:flutter/material.dart';

import 'design_system.dart';

/// 主题 —— 「暖阳奶油」色系（对齐 macOS 版 DesignSystem.swift）。
class AppTheme {
  AppTheme._();

  static ThemeData light(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = Brand.background(brightness);
    final secondary = Brand.secondaryBackground(brightness);
    final accent = Brand.accent(brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: Colors.white,
        secondary: accent,
        onSecondary: Colors.white,
        surface: background,
        onSurface: dark ? const Color(0xFFF0EBE4) : const Color(0xFF2A2620),
        surfaceContainerHighest: secondary,
        onSurfaceVariant: dark ? const Color(0xFFB5AEA4) : const Color(0xFF7A7265),
        error: const Color(0xFFE05252),
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: background,
      dividerColor: Brand.separator(brightness),
      cardTheme: CardThemeData(
        elevation: 0,
        color: secondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: dark ? const Color(0xFFF0EBE4) : const Color(0xFF2A2620),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: secondary,
        indicatorColor: accent.withValues(alpha: 0.15),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: background,
        indicatorColor: accent.withValues(alpha: 0.15),
        selectedIconTheme: IconThemeData(color: accent),
        selectedLabelTextStyle: TextStyle(color: accent, fontWeight: FontWeight.w600),
        unselectedIconTheme: IconThemeData(
          color: dark ? const Color(0xFF8F887E) : const Color(0xFF9A917F),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Brand.chipFill(brightness),
        selectedColor: accent.withValues(alpha: 0.18),
        side: BorderSide(color: Brand.separator(brightness)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? Brand.secondaryDark : Brand.chipFillLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        thumbColor: accent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? accent : null,
        ),
      ),
    );
  }

  static ThemeData get lightTheme => light(Brightness.light);

  static ThemeData get darkTheme => light(Brightness.dark);
}
