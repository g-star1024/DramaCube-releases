import 'package:flutter/material.dart';

import '../../app/design_system.dart';

/// 统一空状态 —— 五种预设（网络/历史/收藏/下载/搜索）+ 自定义。
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  /// 网络异常。
  factory EmptyState.network({String? subtitle, VoidCallback? onRetry}) =>
      EmptyState(
        icon: Icons.wifi_off_rounded,
        title: '网络不给力',
        subtitle: subtitle ?? '检查网络连接后重试',
        actionLabel: onRetry != null ? '重试' : null,
        onAction: onRetry,
      );

  /// 无播放历史。
  factory EmptyState.history() =>
      const EmptyState(icon: Icons.history_rounded, title: '暂无播放历史');

  /// 无收藏。
  factory EmptyState.favorites() => const EmptyState(
        icon: Icons.favorite_border_rounded,
        title: '还没有收藏',
        subtitle: '看到喜欢的剧，点 ❤ 收藏起来',
      );

  /// 无下载任务。
  factory EmptyState.downloads() => const EmptyState(
        icon: Icons.download_rounded,
        title: '暂无下载任务',
        subtitle: '在详情页选择剧集即可离线缓存',
      );

  /// 搜索无结果。
  factory EmptyState.search({String? keyword}) => EmptyState(
        icon: Icons.search_off_rounded,
        title: '没有找到相关内容',
        subtitle: keyword == null || keyword.isEmpty ? '换个关键词试试' : '未找到「$keyword」相关内容',
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Brand.secondaryBackground(theme.brightness),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: muted),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
              textAlign: TextAlign.center,
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            FilledButton.tonal(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
