import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../../app/motion.dart';
import '../models/models.dart';
import 'cover_image.dart';

/// 桌面端 Cinema Hero —— 16:6 宽幅轮播 + 视差 + 三段渐变 + 右侧竖排指示条。
///
/// 对齐设计文档 v2.5： Netflix 式 Billboard，左下剧名+备注+行动区，
/// 右侧竖排指示条（当前项拉长），封面按页位移做视差平移。
class CinemaHero extends StatefulWidget {
  final List<Drama> items;
  final ValueChanged<Drama>? onTap;
  final Duration interval;

  const CinemaHero({
    super.key,
    required this.items,
    this.onTap,
    this.interval = const Duration(seconds: 7),
  });

  @override
  State<CinemaHero> createState() => _CinemaHeroState();
}

class _CinemaHeroState extends State<CinemaHero> {
  final PageController _controller = PageController(viewportFraction: 1.0);
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(CinemaHero oldWidget) {
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
      _go(1);
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
    final next = (_index + delta + widget.items.length) % widget.items.length;
    _controller.animateToPage(
      next,
      duration: Motion.durSlow,
      curve: Motion.curveEmphasized,
    );
  }

  void _jump(int page) {
    if (!_controller.hasClients) return;
    _controller.animateToPage(
      page,
      duration: Motion.durSlow,
      curve: Motion.curveEmphasized,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final count = widget.items.length;
    final safeIndex = _index.clamp(0, count - 1);
    final current = widget.items[safeIndex];

    // 高度封顶：16/6 比例在宽窗口（如 macOS 全屏 2560px）会把轮播撑到近 1000px 高，
    // 严重挤压下方内容。按宽度算比例高度后 clamp 到 [220, 380]，窗口再宽也不继续长高。
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = (w * 6 / 16).clamp(220.0, 380.0);
        return SizedBox(
      height: h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 页面（带视差）
            PageView.builder(
              controller: _controller,
              itemCount: count,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final item = widget.items[i];
                return GestureDetector(
                  onTap: () => widget.onTap?.call(item),
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      // 视差：按页偏移平移封面（最多 ±40px）
                      double offset = 0;
                      if (_controller.hasClients &&
                          _controller.position.haveDimensions) {
                        final page = _controller.page ?? _index.toDouble();
                        offset = (page - i).clamp(-1.0, 1.0) * 40;
                      }
                      return ClipRect(
                        child: Transform.translate(
                          offset: Offset(offset, 0),
                          child: Transform.scale(
                            scale: 1.12, // 超采样，避免视差平移露边
                            child: CoverImage(
                              url: item.coverURL,
                              title: item.title,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            // 三段渐变遮罩（左下信息区衬底）
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: [0.0, 0.45, 1.0],
                  colors: [
                    Color(0xE6140D0B),
                    Color(0x66000000),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.55, 1.0],
                  colors: [Colors.transparent, Color(0x99000000)],
                ),
              ),
            ),
            // 左下信息区
            Positioned(
              left: Spacing.xl,
              bottom: Spacing.xl,
              right: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    current.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (current.remark != null && current.remark!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      current.remark!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _PillAction(
                        icon: Icons.play_arrow_rounded,
                        label: '立即观看',
                        gradient: true,
                        onTap: () => widget.onTap?.call(current),
                      ),
                      const SizedBox(width: Spacing.sm),
                      _PillAction(
                        icon: Icons.info_outline_rounded,
                        label: '详情',
                        onTap: () => widget.onTap?.call(current),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 左右箭头（hover 区域，桌面端）
            Positioned(
              left: Spacing.sm,
              top: 0,
              bottom: 0,
              child: Center(
                child: _ArrowButton(icon: Icons.chevron_left, onTap: () => _go(-1)),
              ),
            ),
            Positioned(
              right: Spacing.sm,
              top: 0,
              bottom: 0,
              child: Center(
                child: _ArrowButton(icon: Icons.chevron_right, onTap: () => _go(1)),
              ),
            ),
            // 右侧竖排指示条
            Positioned(
              right: Spacing.md,
              top: 0,
              bottom: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(count, (i) {
                    final active = i == safeIndex;
                    return GestureDetector(
                      onTap: () => _jump(i),
                      child: AnimatedContainer(
                        duration: Motion.durMed,
                        curve: Motion.curveEmphasized,
                        width: 4,
                        height: active ? 28 : 12,
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        decoration: BoxDecoration(
                          color: active
                              ? Brand.heroGold
                              : Colors.white.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
        );
      },
    );
  }
}

/// Hero 行动胶囊。
class _PillAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool gradient;
  final VoidCallback onTap;

  const _PillAction({
    required this.icon,
    required this.label,
    this.gradient = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: gradient ? Colors.transparent : Colors.white.withValues(alpha: 0.16),
      shape: const StadiumBorder(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient ? Brand.gradientHero : null,
          borderRadius: BorderRadius.circular(22),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
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

/// 轮播箭头按钮。
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
