import 'package:flutter/material.dart';

import 'tv_focus.dart';
import 'tv_theme.dart';

/// TV 聚光灯 —— 首页大幅焦点位（Netflix Billboard 式）。
///
/// - 单项聚焦：背景铺满 + 标题/简介 + 「播放」按钮
/// - ←/→ 切换条目（焦点引擎驱动）
class TvSpotlight extends StatefulWidget {
  final List<TvSpotlightItem> items;
  final ValueChanged<int>? onPlay;

  const TvSpotlight({super.key, required this.items, this.onPlay});

  @override
  State<TvSpotlight> createState() => _TvSpotlightState();
}

class TvSpotlightItem {
  final String title;
  final String? subtitle;
  final String? coverURL;
  const TvSpotlightItem({required this.title, this.subtitle, this.coverURL});
}

class _TvSpotlightState extends State<TvSpotlight> {
  int _index = 0;

  void _go(int delta) {
    if (widget.items.isEmpty) return;
    setState(() => _index =
        (_index + delta + widget.items.length) % widget.items.length);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final item = widget.items[_index];

    return SizedBox(
      height: 420,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景（渐变兜底，图片加载失败不塌方）
          Container(color: TvColors.surface),
          if (item.coverURL != null && item.coverURL!.isNotEmpty)
            Image.network(
              item.coverURL!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          // 渐变衬底（左浓右淡）
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xF20E0D0B), Color(0x800E0D0B), Colors.transparent],
              ),
            ),
          ),
          // 信息区
          Padding(
            padding: const EdgeInsets.only(
              left: TvSafeArea.left,
              right: TvSafeArea.right,
              bottom: 48,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TvColors.onSurface,
                      fontSize: TvText.hero,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      item.subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: TvColors.muted, fontSize: TvText.body),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      TvFocusable(
                        onPressed: () => widget.onPlay?.call(_index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 14),
                          decoration: BoxDecoration(
                            color: TvColors.focus,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.play_arrow_rounded,
                                  color: TvColors.background, size: 28),
                              SizedBox(width: 8),
                              Text(
                                '播放',
                                style: TextStyle(
                                  color: TvColors.background,
                                  fontSize: TvText.body,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // 左右切换（焦点可达）
                      _SpotlightArrow(
                        icon: Icons.chevron_left,
                        onTap: () => _go(-1),
                      ),
                      const SizedBox(width: 8),
                      _SpotlightArrow(
                        icon: Icons.chevron_right,
                        onTap: () => _go(1),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 指示点
          Positioned(
            right: TvSafeArea.right,
            bottom: 48,
            child: Row(
              children: [
                for (var i = 0; i < widget.items.length; i++)
                  Container(
                    width: i == _index ? 24 : 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      color: i == _index
                          ? TvColors.focus
                          : TvColors.onSurface.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SpotlightArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onPressed: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: TvColors.surfaceHi,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: TvColors.onSurface, size: 28),
      ),
    );
  }
}
