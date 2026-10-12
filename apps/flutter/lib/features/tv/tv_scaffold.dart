import 'package:flutter/material.dart';

import 'tv_focus.dart';
import 'tv_theme.dart';

/// TV 脚手架 —— 常驻左侧窄轨侧栏（56 → 200dp 展开）。
///
/// - 默认 56dp 窄轨（图标）
/// - 焦点进入侧栏时展开 200dp（图标 + 文字）
/// - 右侧内容区带安全区内距
class TvScaffold extends StatefulWidget {
  final List<TvNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final Widget child;

  const TvScaffold({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelect,
    required this.child,
  });

  @override
  State<TvScaffold> createState() => _TvScaffoldState();
}

/// 侧栏导航项。
class TvNavItem {
  final IconData icon;
  final String label;
  final String path;
  const TvNavItem(this.icon, this.label, this.path);
}

class _TvScaffoldState extends State<TvScaffold> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvColors.background,
      body: Row(
        children: [
          // 侧栏：焦点进入展开
          Focus(
            onFocusChange: (v) => setState(() => _expanded = v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              width: _expanded ? 200 : 56,
              color: TvColors.surface,
              child: Column(
                children: [
                  const SizedBox(height: TvSafeArea.top / 2),
                  // Logo
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Icon(Icons.movie_filter_rounded,
                        color: TvColors.focus,
                        size: _expanded ? 32 : 24),
                  ),
                  if (_expanded)
                    Text('剧立方',
                        style: TextStyle(
                            color: TvColors.onSurface,
                            fontSize: TvText.caption)),
                  const SizedBox(height: 20),
                  for (var i = 0; i < widget.items.length; i++)
                    _RailItem(
                      item: widget.items[i],
                      selected: i == widget.currentIndex,
                      expanded: _expanded,
                      onPressed: () => widget.onSelect(i),
                    ),
                ],
              ),
            ),
          ),
          // 内容区
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 16),
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final TvNavItem item;
  final bool selected;
  final bool expanded;
  final VoidCallback onPressed;

  const _RailItem({
    required this.item,
    required this.selected,
    required this.expanded,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      child: TvFocusable(
        onPressed: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? TvColors.focus.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon,
                  color: selected ? TvColors.focus : TvColors.muted, size: 24),
              if (expanded) ...[
                const SizedBox(width: 12),
                Text(item.label,
                    style: TextStyle(
                        color: selected
                            ? TvColors.focus
                            : TvColors.onSurface,
                        fontSize: TvText.caption)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
