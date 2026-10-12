import 'package:flutter/material.dart';

import '../../app/design_system.dart';

/// 微光骨架屏 —— 加载占位，替代生硬的 CircularProgressIndicator。
class ShimmerSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const ShimmerSkeleton({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  /// 海报卡骨架（3:4）。
  factory ShimmerSkeleton.poster({double width = 140}) => ShimmerSkeleton(
        width: width,
        height: width * 4 / 3,
        borderRadius: BorderRadius.circular(10),
      );

  /// 16:9 横图骨架。
  factory ShimmerSkeleton.landscape({double? width, double height = 180}) =>
      ShimmerSkeleton(
        width: width ?? double.infinity,
        height: height,
        borderRadius: BorderRadius.circular(10),
      );

  @override
  State<ShimmerSkeleton> createState() => _ShimmerSkeletonState();
}

class _ShimmerSkeletonState extends State<ShimmerSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final base = Brand.placeholder(brightness);
    final highlight = brightness == Brightness.dark
        ? const Color(0xFF4A443E)
        : const Color(0xFFFAF5EC);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * t, 0),
              end: Alignment(0 + 2 * t, 0),
              colors: [base, highlight, base],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}
