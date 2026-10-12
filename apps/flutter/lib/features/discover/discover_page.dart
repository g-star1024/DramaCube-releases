import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_system.dart';
import '../../core/models/models.dart';
import '../../core/widgets/hero_carousel.dart';
import '../../core/widgets/poster_card.dart';
import 'discover_engine.dart';

/// 发现页 —— Hero 轮播 + 热门电影/剧集/综艺/动漫四分区（对齐 macOS 版 RankView）。
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
  bool _expanded = false; // 18 条收起 / 54 条展开
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
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(Spacing.lg),
                    children: [
                      if (_heroItems.isNotEmpty)
                        HeroCarousel(
                          items: _heroItems
                              .map((e) => e.toDrama('movie'))
                              .toList(),
                          onTap: (d) => _openDouban(d),
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
                  ),
                ),
    );
  }

  Widget _buildError() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: Spacing.md),
            Text(_error!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: Spacing.md),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );

  /// 点击豆瓣卡片 → 聚合详情页（按标题跨源搜索可播版本）。
  void _openDouban(Drama drama) {
    context.push('/detail', extra: {'drama': drama});
  }
}

/// 分区视图 —— 标题行 + 收起横排 / 展开网格 + 展开收起按钮。
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

  String get _kind => switch (title) {
        '热门电影' => 'movie',
        '热门动漫' => 'bangumi',
        _ => 'tv',
      };

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
                      drama: item.toDrama(_kind),
                      rating: double.tryParse(item.rate),
                      onTap: () => onTap(item, _kind),
                    ),
                  );
                },
              ),
            )
          else
            // 展开：网格（54 条）
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 140,
                mainAxisSpacing: Spacing.md,
                crossAxisSpacing: Spacing.md,
                childAspectRatio: 0.55,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                return PosterCard(
                  drama: item.toDrama(_kind),
                  rating: double.tryParse(item.rate),
                  onTap: () => onTap(item, _kind),
                );
              },
            ),
        ],
      ),
    );
  }
}
