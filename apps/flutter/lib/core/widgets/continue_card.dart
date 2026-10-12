import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../db/database.dart';
import 'cover_image.dart';

/// 继续观看卡 —— 16:9 封面 + 底部进度线 + 剧名/集名。
class ContinueCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? coverURL;
  final double progress; // 0..1
  final VoidCallback? onTap;

  const ContinueCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.coverURL,
    required this.progress,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final text = brightness == Brightness.dark
        ? const Color(0xFFF0EBE4)
        : const Color(0xFF2A2620);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.md),
                    border: Border.all(
                      color: Brand.separator(brightness),
                      width: 0.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: CoverImage(url: coverURL, title: title),
                  ),
                ),
                // 中央播放徽标
                Center(
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 28),
                  ),
                ),
                // 底部进度线
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(Radii.md),
                    ),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: Colors.black38,
                      valueColor:
                          const AlwaysStoppedAnimation(Brand.heroPink),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Spacing.sm, left: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: text,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: text.withValues(alpha: 0.55),
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

/// 「继续观看」区 —— 读取本地播放历史，按剧聚合取最新一集，横向排列。
class ContinueSection extends StatefulWidget {
  final void Function(History history)? onSelect;
  final int maxItems;

  const ContinueSection({super.key, this.onSelect, this.maxItems = 12});

  @override
  State<ContinueSection> createState() => _ContinueSectionState();
}

class _ContinueSectionState extends State<ContinueSection> {
  List<History> _latest = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await AppDatabase().allHistories();
    if (!mounted) return;
    // 按剧聚合：取每部剧 updatedAt 最新的一条
    final byDrama = <String, History>{};
    for (final h in all) {
      final cur = byDrama[h.dramaId];
      if (cur == null || h.updatedAt.isAfter(cur.updatedAt)) {
        byDrama[h.dramaId] = h;
      }
    }
    final list = byDrama.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    setState(() => _latest = list.take(widget.maxItems).toList());
  }

  String _formatDuration(double seconds) {
    final d = Duration(seconds: seconds.round());
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_latest.isEmpty) return const SizedBox.shrink();
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
                '继续观看',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: text,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            itemCount: _latest.length,
            separatorBuilder: (_, __) => const SizedBox(width: Spacing.md),
            itemBuilder: (context, i) {
              final h = _latest[i];
              final ratio =
                  h.duration > 0 ? (h.position / h.duration).clamp(0.0, 1.0) : 0.0;
              return SizedBox(
                width: 240,
                child: ContinueCard(
                  title: h.title,
                  subtitle:
                      '${h.episodeTitle} · ${_formatDuration(h.position)}',
                  coverURL: h.coverURL,
                  progress: ratio,
                  onTap: () => widget.onSelect?.call(h),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
