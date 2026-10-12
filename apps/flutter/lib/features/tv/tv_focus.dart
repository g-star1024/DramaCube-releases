import 'package:flutter/material.dart';

import 'tv_theme.dart';

/// TV 焦点引擎 —— 焦点三态（缩放 1.12 + 金辉光 + 邻居压暗）。
///
/// 用法：
/// ```dart
/// TvFocusable(
///   onPressed: () => ...,
///   child: TvPosterCard(...),
/// )
/// ```
/// 行级压暗由 [TvFocusRow] / [TvShelf] 统一处理（焦点项之外的兄弟项 alpha 0.45）。
class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;

  const TvFocusable({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.onDoubleTap,
    this.autofocus = false,
    this.onFocusChange,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  void _setFocus(bool v) {
    if (_focused == v) return;
    setState(() => _focused = v);
    widget.onFocusChange?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: _setFocus,
      child: GestureDetector(
        onTap: widget.onPressed,
        onDoubleTap: widget.onDoubleTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _focused ? TvText.focusScale : 1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: TvColors.focusGlow,
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ]
                  : const [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// 焦点感知容器 —— 横向陈列行：焦点项 1.0，兄弟项压暗 0.45；末项露出 peekFraction。
///
/// 行内每项自带焦点态（缩放 + 辉光），压暗由本行统一按 focusedIndex 处理。
class TvFocusRow extends StatefulWidget {
  final int itemCount;
  final void Function(int index)? onItemPressed;
  final void Function(int index)? onItemLongPress;
  final Widget Function(BuildContext context, int index, bool focused) itemBuilder;
  final double height;
  final double peekFraction; // 末项露出比例（默认 0.3）

  const TvFocusRow({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.onItemPressed,
    this.onItemLongPress,
    this.height = 320,
    this.peekFraction = 0.3,
  });

  @override
  State<TvFocusRow> createState() => _TvFocusRowState();
}

class _TvFocusRowState extends State<TvFocusRow> {
  int _focusedIndex = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) return const SizedBox.shrink();

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (context, constraints) {
        // 末项露出 peekFraction：总槽位 = n + peek 个卡宽
        const gap = 20.0;
        final n = (constraints.maxWidth / (280 + gap)).floor().clamp(1, 99);
        final cardWidth =
            (constraints.maxWidth - gap * n) / (n + widget.peekFraction);

        return ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: widget.itemCount,
          itemBuilder: (context, i) {
            final focused = i == _focusedIndex;
            return Padding(
              padding: EdgeInsets.only(right: gap),
              child: SizedBox(
                width: cardWidth,
                child: TvFocusable(
                  autofocus: i == 0,
                  onFocusChange: (v) {
                    if (v && _focusedIndex != i) {
                      setState(() => _focusedIndex = i);
                    }
                  },
                  onPressed: widget.onItemPressed == null
                      ? null
                      : () => widget.onItemPressed!(i),
                  onLongPress: widget.onItemLongPress == null
                      ? null
                      : () => widget.onItemLongPress!(i),
                  // 兄弟压暗：焦点项 1.0，其余 0.45
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: focused ? 1.0 : 0.45,
                    child: widget.itemBuilder(context, i, focused),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
