import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../models/models.dart';
import 'cover_image.dart';

/// Hero 轮播 —— 自动轮换 + 渐变遮罩 + 左右切换按钮 + 指示点 + 左下角剧名。
///
/// 对齐 macOS 版首页 Hero 轮播（热门电影 Top N）。
class HeroCarousel extends StatefulWidget {
  final List<Drama> items;
  final ValueChanged<Drama>? onTap;
  final Duration interval;

  const HeroCarousel({
    super.key,
    required this.items,
    this.onTap,
    this.interval = const Duration(seconds: 6),
  });

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final PageController _controller = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(HeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _index = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
      setState(() {});
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted || widget.items.isEmpty || !_controller.hasClients) return;
      final next = (_index + 1) % widget.items.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _go(int delta) {
    if (widget.items.isEmpty || !_controller.hasClients) return;
    final next =
        (_index + delta + widget.items.length) % widget.items.length;
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return AspectRatio(
      aspectRatio: 21 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final item = widget.items[i];
                return GestureDetector(
                  onTap: () => widget.onTap?.call(item),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CoverImage(url: item.coverURL, title: item.title),
                      // 底部渐变遮罩（衬剧名）
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [0.55, 1.0],
                            colors: [Colors.transparent, Colors.black87],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            // 左下角剧名
            Positioned(
              left: Spacing.lg,
              bottom: Spacing.lg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.items[_index.clamp(0, widget.items.length - 1)].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black45)],
                    ),
                  ),
                ],
              ),
            ),
            // 左右切换按钮
            Positioned(
              left: Spacing.sm,
              top: 0,
              bottom: 0,
              child: Center(
                child: _ArrowButton(
                  icon: Icons.chevron_left,
                  onTap: () => _go(-1),
                ),
              ),
            ),
            Positioned(
              right: Spacing.sm,
              top: 0,
              bottom: 0,
              child: Center(
                child: _ArrowButton(
                  icon: Icons.chevron_right,
                  onTap: () => _go(1),
                ),
              ),
            ),
            // 指示点（右下角）
            Positioned(
              right: Spacing.lg,
              bottom: Spacing.lg,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  widget.items.length,
                  (i) => Container(
                    width: i == _index ? 18 : 6,
                    height: 6,
                    margin: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      color: i == _index
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 轮播切换按钮（大热区，对齐 macOS 版按钮加大优化）。
class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ArrowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black38,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
