import 'dart:ui';

import 'package:flutter/material.dart';

/// 毛玻璃面板 —— 桌面端 OSD / 悬浮控制条用。
///
/// [blur] 控制模糊强度；[tint] 控制玻璃底色与不透明度。
class GlassPanel extends StatelessWidget {
  final Widget child;
  final double blur;
  final Color tint;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final bool showBorder;

  const GlassPanel({
    super.key,
    required this.child,
    this.blur = 20,
    this.tint = const Color(0x33201815),
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final effectiveTint = brightness == Brightness.dark
        ? tint
        : const Color(0x66FFFFFF);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: effectiveTint,
            borderRadius: borderRadius,
            border: showBorder
                ? Border.all(
                    color: brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.06),
                  )
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}
