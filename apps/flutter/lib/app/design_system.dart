import 'package:flutter/material.dart';

/// 设计系统 —— 对齐 macOS 版「暖阳奶油」色系（DesignSystem.swift 移植）。
///
/// 浅色：暖米白底 + 奶油次级面板 + 红果粉强调；
/// 深色：暖炭黑底 + 亮粉强调（避免纯黑，保留暖意）。
abstract final class Brand {
  /// 主品牌色（红果粉 #FF2D55，浅色外观）。
  static const Color pink = Color(0xFFFF2D55);

  /// 深色模式下更亮的粉 rgb(1.0, 0.36, 0.53)。
  static const Color pinkDark = Color(0xFFE85C87);

  // MARK: 暖阳色板（浅色 / 深色成对定义，主题层按 brightness 取值）

  /// 窗口底色：暖米白 / 暖炭黑。
  static const Color backgroundLight = Color(0xFFFDFBF7); // (0.992,0.984,0.965)
  static const Color backgroundDark = Color(0xFF1C1A17); // (0.11,0.10,0.09)

  /// 次级面板底：奶油色 / 略亮暖黑。
  static const Color secondaryLight = Color(0xFFF6F0E5); // (0.965,0.941,0.898)
  static const Color secondaryDark = Color(0xFF292522); // (0.16,0.145,0.13)

  /// 图片加载占位 / 失败底色：暖沙色（不再是灰）。
  static const Color placeholderLight = Color(0xFFF2E9DA); // (0.949,0.914,0.855)
  static const Color placeholderDark = Color(0xFF383330); // (0.22,0.20,0.18)

  /// 胶囊 / 卡片填充：近白暖色（在米白底上有轻微层次）。
  static const Color chipFillLight = Color(0xFFFFFEFC); // (1.0,0.996,0.988)
  static const Color chipFillDark = Color(0xFF3D3833); // (0.24,0.22,0.20)

  /// 分隔线：暖褐。
  static const Color separatorLight = Color(0xFFE3DACC); // (0.89,0.855,0.80)
  static const Color separatorDark = Color(0xFF474240); // (0.28,0.26,0.24)

  /// 按外观取背景色。
  static Color background(Brightness b) =>
      b == Brightness.dark ? backgroundDark : backgroundLight;

  /// 按外观取次级面板色。
  static Color secondaryBackground(Brightness b) =>
      b == Brightness.dark ? secondaryDark : secondaryLight;

  /// 按外观取占位色。
  static Color placeholder(Brightness b) =>
      b == Brightness.dark ? placeholderDark : placeholderLight;

  /// 按外观取胶囊填充色。
  static Color chipFill(Brightness b) =>
      b == Brightness.dark ? chipFillDark : chipFillLight;

  /// 按外观取分隔线色。
  static Color separator(Brightness b) =>
      b == Brightness.dark ? separatorDark : separatorLight;

  /// 按外观取强调色。
  static Color accent(Brightness b) => b == Brightness.dark ? pinkDark : pink;
}

/// 间距（对齐 macOS 版 Spacing）。
abstract final class Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 20;
  static const double xl = 32;
}

/// 圆角（对齐 macOS 版 Radius）。
abstract final class Radii {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 16;
}
