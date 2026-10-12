import 'package:flutter/material.dart';

import '../../app/design_system.dart';

/// 品牌渐变按钮 —— 主行动按钮（粉 → 橘 → 金）。
class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final double height;
  final EdgeInsetsGeometry padding;
  final double fontSize;

  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.height = 44,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
    this.fontSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            gradient: Brand.gradientHero,
            borderRadius: BorderRadius.circular(height / 2),
            boxShadow: [
              if (enabled)
                BoxShadow(
                  color: Brand.heroPink.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(height / 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: fontSize + 4, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
