import 'package:flutter/animation.dart';

/// 动效令牌 v3 —— 三端统一时长与曲线。
///
/// - durFast：微交互（hover / 按压反馈 / 焦点）
/// - durMed：组件过渡（卡片上浮 / 面板展开）
/// - durSlow：页面级转场（hero 轮换 / 路由切换）
abstract final class Motion {
  static const Duration durFast = Duration(milliseconds: 150);
  static const Duration durMed = Duration(milliseconds: 250);
  static const Duration durSlow = Duration(milliseconds: 400);

  /// 强调曲线（进入 / 前进方向）。
  static const Curve curveEmphasized = Curves.easeOutCubic;

  /// 弹性曲线（交互回弹）。
  static const Curve curveSpring = Curves.easeOutBack;
}
