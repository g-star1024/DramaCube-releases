import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_system.dart';
import '../../core/models/models.dart';
import '../../core/widgets/cinema_hero.dart';
import '../../core/widgets/continue_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/hero_carousel.dart';
import '../../core/widgets/media_row.dart';
import '../../core/widgets/poster_card.dart';
import '../../core/widgets/shimmer.dart';
import 'discover_engine.dart';

/// 发现页 —— 三端分风格（v2.5）：
/// - 桌面（≥900）：Cinema Hero 16:6 + 继续观看 + MediaRow 陈列栏（末项露出 30%）
/// - 移动：Hero 轮播 + 继续观看 + 四分区（收起横排 / 展开双列瀑布流）
class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _SectionData {
  final String title;
  final List<DoubanHotItem> items;
  _SectionData(this.title, this.items);
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  List<DoubanHotItem> _heroItems = [];
  final List<_SectionData> _sections = [];
  bool _loading = true;
  bool _expanded = false; // 移动端：18 条收起 / 54 条展开
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final engine = ref.read(discoverEngineProvider);
    final limit = _expanded ? 54 : 18;

    final movie = await engine.doubanHot(kind: 'movie', category: '热门', type: '全部', limit: limit);
    final tv = await engine.doubanHot(kind: 'tv', category: 'tv', type: 'tv', limit: limit);
    final show = await engine.doubanHot(kind: 'tv', category: 'show', type: 'show', limit: limit);
    final anime = await engine.bilibiliBangumiRank(limit: limit);

    if (!mounted) return;
    setState(() {
      _heroItems = movie.take(6).toList();
      _sections
        ..clear()
        ..addAll([
          if (movie.isNotEmpty) _SectionData('热门电影', movie),
          if (tv.isNotEmpty) _SectionData('热门剧集', tv),
          if (show.isNotEmpty) _SectionData('热门综艺', show),
          if (anime.isNotEmpty) _SectionData('热门动漫', anime),
        ]);
      _loading = false;
      if (_sections.isEmpty) _error = '加载失败，请检查网络后重试';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('发现'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '聚合搜索',
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
      body: _loading
          ? _buildSkeleton()
          : _error != null
              ? EmptyState.network(subtitle: _error, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: isWide ? _buildWide() : _buildMobile(),
                ),
    );
  }

  /// 桌面布局：Cinema Hero + 继续观看 + 陈列栏行。
  Widget _buildWide() {
    return ListView(
      padding: const EdgeInsets.only(top: Spacing.lg, bottom: Spacing.xl),
      children: [
        if (_heroItems.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: CinemaHero(
              items: _heroItems.map((e) => e.toDrama('movie')).toList(),
              onTap: _openDouban,
            ),
          ),
        const SizedBox(height: Spacing.xl),
        ContinueSection(
          onSelect: (h) => context.push(
            '/detail',
            extra: {
              'drama': Drama(
                id: h.dramaId,
                title: h.title,
                coverURL: h.coverURL,
              ),
              // 历史入口：详情加载完自动续播到本剧最新进度那一集
              'resumeFromHistory': true,
            },
          ),
        ),
        for (final section in _sections) ...[
          const SizedBox(height: Spacing.xl),
          MediaRow<DoubanHotItem>(
            title: section.title,
            items: section.items,
            itemWidth: 140,
            itemHeight: 250,
            itemBuilder: (context, item) => PosterCard(
              drama: item.toDrama(kindOf(section.title)),
              rating: double.tryParse(item.rate),
              onTap: () => _openDouban(item.toDrama(kindOf(section.title))),
            ),
          ),
        ],
      ],
    );
  }

  /// 移动布局：Hero 轮播 + 继续观看 + 分区（收起横排 / 展开瀑布流）。
  Widget _buildMobile() {
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        if (_heroItems.isNotEmpty)
          HeroCarousel(
            items: _heroItems.map((e) => e.toDrama('movie')).toList(),
            onTap: _openDouban,
          ),
        ContinueSection(
          onSelect: (h) => context.push(
            '/detail',
            extra: {
              'drama': Drama(
                id: h.dramaId,
                title: h.title,
                coverURL: h.coverURL,
              ),
              'resumeFromHistory': true,
            },
          ),
        ),
        for (final section in _sections)
          _SectionView(
            title: section.title,
            items: section.items,
            expanded: _expanded,
            onToggle: () {
              setState(() => _expanded = !_expanded);
              _load();
            },
            onTap: (item, kind) => _openDouban(item.toDrama(kind)),
          ),
      ],
    );
  }

  /// 加载骨架屏（微光）。
  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        ShimmerSkeleton.landscape(height: 200),
        const SizedBox(height: Spacing.xl),
        ShimmerSkeleton(
          height: 20,
          width: 120,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: Spacing.md),
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 6,
            separatorBuilder: (_, __) => const SizedBox(width: Spacing.md),
            itemBuilder: (_, __) => ShimmerSkeleton.poster(width: 140),
          ),
        ),
      ],
    );
  }

  /// 点击豆瓣卡片 → 聚合详情页（按标题跨源搜索可播版本）。
  void _openDouban(Drama drama) {
    context.push('/detail', extra: {'drama': drama});
  }
}

/// 分区 kind 映射。
String kindOf(String title) => switch (title) {
      '热门电影' => 'movie',
      '热门动漫' => 'bangumi',
      _ => 'tv',
    };

/// 移动端分区视图 —— 标题行 + 收起横排 / 展开双列瀑布流。
class _SectionView extends StatelessWidget {
  final String title;
  final List<DoubanHotItem> items;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(DoubanHotItem, String) onTap;

  const _SectionView({
    required this.title,
    required this.items,
    required this.expanded,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final text = brightness == Brightness.dark
        ? const Color(0xFFF0EBE4)
        : const Color(0xFF2A2620);

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: text,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onToggle,
                icon: Icon(expanded ? Icons.unfold_less : Icons.unfold_more,
                    size: 18),
                label: Text(expanded ? '收起' : '展开'),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          if (!expanded)
            // 收起：横向滚动画廊（18 条）
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: Spacing.md),
                itemBuilder: (context, i) {
                  final item = items[i];
                  return SizedBox(
                    width: 126,
                    child: PosterCard(
                      drama: item.toDrama(kindOf(title)),
                      rating: double.tryParse(item.rate),
                      onTap: () => onTap(item, kindOf(title)),
                    ),
                  );
                },
              ),
            )
          else
            // 展开：双列瀑布流（54 条，交替纵横比制造错落感）
            MasonryGridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: Spacing.md,
              crossAxisSpacing: Spacing.md,
              padding: EdgeInsets.zero,
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                // 交替纵横比（3:4 与 3:4.8）形成瀑布错落
                final ratio = i.isEven ? 0.72 : 0.60;
                return AspectRatio(
                  aspectRatio: ratio,
                  child: PosterCard(
                    drama: item.toDrama(kindOf(title)),
                    rating: double.tryParse(item.rate),
                    onTap: () => onTap(item, kindOf(title)),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
