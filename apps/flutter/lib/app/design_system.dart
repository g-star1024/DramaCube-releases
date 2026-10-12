import 'package:flutter/material.dart';

/// 配色方案（主题的一整套色板）。
///
/// 每套 = 强调色（浅/深）+ 暖色阶背景体系 + 品牌渐变三段 + TV 焦点色。
/// 切换 = 换 [Brand.palette]，主题层在下次 build 时整体生效。
class AppPalette {
  final String id;
  final String name;

  /// 强调色：浅色外观 / 深色外观。
  final Color accent;
  final Color accentDark;

  /// 窗口底色：浅 / 深。
  final Color backgroundLight;
  final Color backgroundDark;

  /// 次级面板底：浅 / 深。
  final Color secondaryLight;
  final Color secondaryDark;

  /// 图片加载占位 / 失败底色：浅 / 深。
  final Color placeholderLight;
  final Color placeholderDark;

  /// 胶囊 / 卡片填充：浅 / 深。
  final Color chipFillLight;
  final Color chipFillDark;

  /// 分隔线：浅 / 深。
  final Color separatorLight;
  final Color separatorDark;

  /// 品牌渐变三段（左 → 右）。
  final Color heroStart;
  final Color heroMid;
  final Color heroEnd;

  /// TV 焦点色（金辉光 / hover 描边同源）。
  final Color focus;

  const AppPalette({
    required this.id,
    required this.name,
    required this.accent,
    required this.accentDark,
    required this.backgroundLight,
    required this.backgroundDark,
    required this.secondaryLight,
    required this.secondaryDark,
    required this.placeholderLight,
    required this.placeholderDark,
    required this.chipFillLight,
    required this.chipFillDark,
    required this.separatorLight,
    required this.separatorDark,
    required this.heroStart,
    required this.heroMid,
    required this.heroEnd,
    required this.focus,
  });

  /// 渐变（左 → 右）。
  LinearGradient get gradient => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [heroStart, heroMid, heroEnd],
      );
}

/// 内置配色方案（设置中心一键切换）。
abstract final class AppPalettes {
  /// 红果粉（默认，S1-S3 v2.5 基线）。
  static const hongguo = AppPalette(
    id: 'hongguo',
    name: '红果粉',
    accent: Color(0xFFFF2D55),
    accentDark: Color(0xFFE85C87),
    backgroundLight: Color(0xFFFDFBF7),
    backgroundDark: Color(0xFF1C1A17),
    secondaryLight: Color(0xFFF6F0E5),
    secondaryDark: Color(0xFF292522),
    placeholderLight: Color(0xFFF2E9DA),
    placeholderDark: Color(0xFF383330),
    chipFillLight: Color(0xFFFFFEFC),
    chipFillDark: Color(0xFF3D3833),
    separatorLight: Color(0xFFE3DACC),
    separatorDark: Color(0xFF474240),
    heroStart: Color(0xFFFF2D55),
    heroMid: Color(0xFFFF9A62),
    heroEnd: Color(0xFFFFD166),
    focus: Color(0xFFFFD166),
  );

  /// 玫瑰金（HIS 锁定风格移植）。
  static const rose = AppPalette(
    id: 'rose',
    name: '玫瑰金',
    accent: Color(0xFFC9184A),
    accentDark: Color(0xFFF05C8F),
    backgroundLight: Color(0xFFFBF5F3),
    backgroundDark: Color(0xFF1F1719),
    secondaryLight: Color(0xFFF5E7E2),
    secondaryDark: Color(0xFF2E2226),
    placeholderLight: Color(0xFFEFDCD6),
    placeholderDark: Color(0xFF3E2B31),
    chipFillLight: Color(0xFFFFFCFB),
    chipFillDark: Color(0xFF432F36),
    separatorLight: Color(0xFFE7CFC9),
    separatorDark: Color(0xFF4E3A40),
    heroStart: Color(0xFFC9184A),
    heroMid: Color(0xFFE98A6B),
    heroEnd: Color(0xFFF2C14E),
    focus: Color(0xFFF2C14E),
  );

  /// 科技蓝。
  static const blue = AppPalette(
    id: 'blue',
    name: '科技蓝',
    accent: Color(0xFF2E6FF2),
    accentDark: Color(0xFF6FA8FF),
    backgroundLight: Color(0xFFF7F9FC),
    backgroundDark: Color(0xFF0F141D),
    secondaryLight: Color(0xFFEAEFF7),
    secondaryDark: Color(0xFF1A2230),
    placeholderLight: Color(0xFFDFE7F2),
    placeholderDark: Color(0xFF27303F),
    chipFillLight: Color(0xFFFFFFFF),
    chipFillDark: Color(0xFF2A3444),
    separatorLight: Color(0xFFD5DEEA),
    separatorDark: Color(0xFF35404F),
    heroStart: Color(0xFF2E6FF2),
    heroMid: Color(0xFF4F8DF5),
    heroEnd: Color(0xFF6EC6FF),
    focus: Color(0xFF6EC6FF),
  );

  /// 森林绿。
  static const forest = AppPalette(
    id: 'forest',
    name: '森林绿',
    accent: Color(0xFF1F9D63),
    accentDark: Color(0xFF5FD6A0),
    backgroundLight: Color(0xFFF5FAF7),
    backgroundDark: Color(0xFF101814),
    secondaryLight: Color(0xFFE6F1EA),
    secondaryDark: Color(0xFF1B2B23),
    placeholderLight: Color(0xFFD8E9DF),
    placeholderDark: Color(0xFF26382F),
    chipFillLight: Color(0xFFFDFEFD),
    chipFillDark: Color(0xFF2B3B33),
    separatorLight: Color(0xFFCFE2D6),
    separatorDark: Color(0xFF35473D),
    heroStart: Color(0xFF1F9D63),
    heroMid: Color(0xFF45B57E),
    heroEnd: Color(0xFF9BDFB0),
    focus: Color(0xFF9BDFB0),
  );

  /// 暗夜紫。
  static const purple = AppPalette(
    id: 'purple',
    name: '暗夜紫',
    accent: Color(0xFF6C4CF0),
    accentDark: Color(0xFFB39DFF),
    backgroundLight: Color(0xFFF8F7FD),
    backgroundDark: Color(0xFF15121F),
    secondaryLight: Color(0xFFECE8F8),
    secondaryDark: Color(0xFF221D31),
    placeholderLight: Color(0xFFE0DAF3),
    placeholderDark: Color(0xFF2E2842),
    chipFillLight: Color(0xFFFEFEFF),
    chipFillDark: Color(0xFF322B47),
    separatorLight: Color(0xFFD6CFEE),
    separatorDark: Color(0xFF3D3555),
    heroStart: Color(0xFF6C4CF0),
    heroMid: Color(0xFF8B6FF5),
    heroEnd: Color(0xFFC4A8FF),
    focus: Color(0xFFC4A8FF),
  );

  static const all = [hongguo, rose, blue, forest, purple];

  static AppPalette byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return hongguo;
  }
}

/// 设计系统 —— 当前色板由 [palette] 驱动（设置中心一键切换，默认「红果粉」）。
///
/// 浅色：暖底 + 强调色；深色：暖炭黑底 + 亮强调（避免纯黑，保留暖意）。
abstract final class Brand {
  /// 当前色板（应用启动 / 设置切换时由 DramaCubeApp 赋值）。
  static AppPalette palette = AppPalettes.hongguo;

  /// 主品牌色（浅色外观强调）。
  static Color get pink => palette.accent;

  /// 深色模式下更亮的强调色。
  static Color get pinkDark => palette.accentDark;

  // MARK: 暖阳色板（浅色 / 深色成对定义，主题层按 brightness 取值）

  /// 窗口底色：浅 / 深。
  static Color get backgroundLight => palette.backgroundLight;
  static Color get backgroundDark => palette.backgroundDark;

  /// 次级面板底：浅 / 深。
  static Color get secondaryLight => palette.secondaryLight;
  static Color get secondaryDark => palette.secondaryDark;

  /// 图片加载占位 / 失败底色：浅 / 深。
  static Color get placeholderLight => palette.placeholderLight;
  static Color get placeholderDark => palette.placeholderDark;

  /// 胶囊 / 卡片填充：浅 / 深。
  static Color get chipFillLight => palette.chipFillLight;
  static Color get chipFillDark => palette.chipFillDark;

  /// 分隔线：浅 / 深。
  static Color get separatorLight => palette.separatorLight;
  static Color get separatorDark => palette.separatorDark;

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

  // MARK: v3 品牌渐变 / 焦点（三端分风格统一基底，随色板切换）

  /// 渐变起点。
  static Color get heroPink => palette.heroStart;

  /// 渐变中段。
  static Color get heroAmber => palette.heroMid;

  /// 渐变终点。
  static Color get heroGold => palette.heroEnd;

  /// 焦点色（TV 金辉光 / 桌面 hover 描边同源）。
  static Color get focusGold => palette.focus;

  /// 品牌渐变（左 → 右）。
  static LinearGradient get gradientHero => palette.gradient;
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
