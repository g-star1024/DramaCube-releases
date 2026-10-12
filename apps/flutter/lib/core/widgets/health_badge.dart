import 'package:flutter/material.dart';

/// 连通性健康徽标（视频源 / 直播源 / 资源库弹层共用）。
///
/// 未测试 = 灰色「未测试」；可用 = 绿色「123 ms」；失效 = 红色「失效」。
class HealthBadge extends StatelessWidget {
  final bool tested;
  final bool ok;
  final int? latencyMs;

  const HealthBadge({super.key, required this.tested, required this.ok, this.latencyMs});

  /// 便捷构造：未测试。
  const HealthBadge.untested({super.key})
      : tested = false,
        ok = false,
        latencyMs = null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color color;
    final String text;
    if (!tested) {
      color = theme.disabledColor;
      text = '未测试';
    } else if (!ok) {
      color = theme.colorScheme.error;
      text = '失效';
    } else {
      color = const Color(0xFF2FA84F);
      text = latencyMs == null ? '可用' : '$latencyMs ms';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
