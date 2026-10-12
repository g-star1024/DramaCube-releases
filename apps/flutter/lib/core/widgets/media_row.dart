import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../../app/motion.dart';

/// 陈列栏行 —— 桌面端分区行组件（Netflix 式）。
///
/// - 末项露出 30%，暗示可横向滚动
/// - 卡片 hover 上浮 + 阴影（桌面）
/// - [previewBuilder] 静默预览钩子（hover 600ms 后浮现，S2 接视频预览）
class MediaRow<T> extends StatelessWidget {
  final String title;
  final List<T> items;
  final Widget Function(BuildContext, T) itemBuilder;
  final Widget Function(BuildContext, T)? previewBuilder;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double itemWidth;
  final double itemHeight;

  const MediaRow({
    super.key,
    required this.title,
    required this.items,
    required this.itemBuilder,
    this.previewBuilder,
    this.actionLabel,
    this.onAction,
    this.itemWidth = 140,
    this.itemHeight = 240,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  gradient: Brand.gradientHero,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: text,
                ),
              ),
              const Spacer(),
              if (actionLabel != null)
                TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ),
        ),
        LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          const gap = Spacing.md;
          const outerPad = Spacing.lg;
          final avail = width - outerPad * 2;
          final n = (avail / (itemWidth + gap)).floor().clamp(1, 99);
          // 末项露出 30%：总槽位 = n + 0.3 个卡宽
          final w = (avail - gap * n) / (n + 0.3);
          final h = itemHeight * (w / itemWidth).clamp(0.75, 1.25);

          return SizedBox(
            height: h,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: outerPad),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: gap),
              itemBuilder: (context, i) => SizedBox(
                width: w,
                child: _HoverLift(
                  preview: previewBuilder == null
                      ? null
                      : previewBuilder!(context, items[i]),
                  child: itemBuilder(context, items[i]),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// hover 上浮 + 可选静默预览浮层。
class _HoverLift extends StatefulWidget {
  final Widget child;
  final Widget? preview;

  const _HoverLift({required this.child, this.preview});

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.03 : 1,
        duration: Motion.durFast,
        curve: Motion.curveEmphasized,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.md),
                boxShadow: _hover
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : const [],
              ),
              child: widget.child,
            ),
            if (_hover && widget.preview != null)
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: Motion.durMed,
                  child: widget.preview!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
