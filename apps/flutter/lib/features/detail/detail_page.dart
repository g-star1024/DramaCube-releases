import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_system.dart';
import '../../core/models/models.dart';
import '../../core/widgets/cover_image.dart';
import '../catalog/catalog_repository.dart';
import '../discover/discover_engine.dart';

/// 剧集详情页 —— 封面/标题/豆瓣简介 + 跨源可播结果 + 选集胶囊网格。
///
/// 入参两种：
/// - `{'drama': Drama}`：tvbox 直载选集；douban 条目先聚合搜索可播版本。
class DetailPage extends ConsumerStatefulWidget {
  final Drama drama;
  const DetailPage({super.key, required this.drama});

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _SiteGroup {
  final String siteName;
  final List<Drama> results;
  _SiteGroup(this.siteName, this.results);
}

class _DetailPageState extends ConsumerState<DetailPage> {
  Drama? _drama; // 当前可播剧（聚合搜索后从豆瓣条目切到具体源结果）
  DramaDetail? _detail;
  DoubanSubject? _subject;
  bool _loadingDetail = false;
  bool _searching = false;
  bool _allDone = false;
  String? _error;
  final List<_SiteGroup> _groups = [];
  String _queryTitle = '';

  @override
  void initState() {
    super.initState();
    _drama = widget.drama;
    // 标题归一化（去季/年份/全N集/更新至），提高跨源搜索命中率。
    _queryTitle = DiscoverEngine.normalize(widget.drama.title);
    final parts = widget.drama.id.split('|');
    if (parts.isNotEmpty && parts.first == 'douban') {
      // 豆瓣条目：拉简介 + 聚合搜索可播版本
      _loadDouban(parts[1], parts.length > 2 ? parts[2] : '');
      _aggregate();
    } else {
      _loadDetail();
    }
  }

  Future<void> _loadDouban(String kind, String id) async {
    if (id.isEmpty) return;
    final subject = await ref
        .read(discoverEngineProvider)
        .doubanSubject(id: id, kind: kind);
    if (mounted && subject != null) setState(() => _subject = subject);
  }

  /// 跨源聚合搜索（流式补组）。
  void _aggregate() {
    setState(() {
      _searching = true;
      _groups.clear();
      _allDone = false;
    });
    ref.read(catalogRepositoryProvider).aggregateSearch(
          query: _queryTitle,
          onSiteDone: (siteName, results) {
            if (!mounted) return;
            setState(() => _groups.add(_SiteGroup(siteName, results)));
          },
          onAllDone: () {
            if (mounted) setState(() { _searching = false; _allDone = true; });
          },
        );
  }

  Future<void> _loadDetail() async {
    final drama = _drama;
    if (drama == null) return;
    final parts = drama.id.split('|');
    if (parts.first != 'tvbox' || parts.length < 3) return;
    setState(() {
      _loadingDetail = true;
      _error = null;
    });
    final detail = await ref
        .read(catalogRepositoryProvider)
        .detail(siteKey: parts[1], vodId: parts.sublist(2).join('|'));
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _loadingDetail = false;
      if (detail == null || detail.episodes.isEmpty) {
        _error = '该源暂无可播放集数，可尝试下方其他源';
      }
    });
  }

  void _play(int index) {
    final detail = _detail;
    if (detail == null || detail.episodes.isEmpty) return;
    context.push('/player', extra: {
      'detail': detail,
      'startIndex': index,
    });
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final text = brightness == Brightness.dark
        ? const Color(0xFFF0EBE4)
        : const Color(0xFF2A2620);
    final subtitle = text.withValues(alpha: 0.6);
    final drama = _drama;

    return Scaffold(
      appBar: AppBar(title: Text(drama?.title ?? '详情')),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          // 头部：封面 + 信息
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Radius.md),
                child: SizedBox(
                  width: 110,
                  height: 147,
                  child: CoverImage(url: drama?.coverURL, title: drama?.title ?? ''),
                ),
              ),
              const SizedBox(width: Spacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      drama?.title ?? '',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: text),
                    ),
                    if ((drama?.remark ?? '').isNotEmpty) ...[
                      const SizedBox(height: Spacing.xs),
                      Text(drama!.remark!, style: TextStyle(fontSize: 13, color: subtitle)),
                    ],
                    if (_subject != null && _subject!.cardSubtitle.isNotEmpty) ...[
                      const SizedBox(height: Spacing.xs),
                      Text(_subject!.cardSubtitle, style: TextStyle(fontSize: 13, color: subtitle)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // 豆瓣简介
          if (_subject != null && _subject!.intro.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('简介', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: text)),
                  const SizedBox(height: Spacing.sm),
                  Text(_subject!.intro, style: TextStyle(fontSize: 13, height: 1.6, color: subtitle)),
                ],
              ),
            ),
          // 选集（已选源）
          if (_loadingDetail)
            const Padding(
              padding: EdgeInsets.all(Spacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_detail != null && _detail!.episodes.isNotEmpty)
            _EpisodesView(detail: _detail!, onPlay: _play)
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.lg),
              child: Text(_error!, style: TextStyle(fontSize: 13, color: subtitle)),
            ),
          // 跨源聚合搜索结果
          if (_groups.isNotEmpty || _searching)
            _AggregateResults(
              groups: _groups,
              searching: _searching,
              allDone: _allDone,
              queryTitle: _queryTitle,
              currentId: drama?.id,
              onSelect: (d) {
                setState(() {
                  _drama = d;
                  _detail = null;
                  _error = null;
                });
                _loadDetail();
              },
            ),
        ],
      ),
    );
  }
}

/// 选集胶囊网格（对齐 macOS 版选集面板）。
class _EpisodesView extends StatelessWidget {
  final DramaDetail detail;
  final void Function(int) onPlay;

  const _EpisodesView({required this.detail, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final eps = detail.episodes;
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选集（${eps.length} 集）',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: Spacing.md),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 110,
              mainAxisSpacing: Spacing.sm,
              crossAxisSpacing: Spacing.sm,
              childAspectRatio: 2.6,
            ),
            itemCount: eps.length,
            itemBuilder: (context, i) {
              return OutlinedButton(
                onPressed: () => onPlay(i),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  side: BorderSide(color: Brand.separator(Theme.of(context).brightness)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radius.sm),
                  ),
                ),
                child: Text(
                  eps[i].title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 跨源聚合搜索结果（按源分组，流式补组）。
class _AggregateResults extends StatelessWidget {
  final List<_SiteGroup> groups;
  final bool searching;
  final bool allDone;
  final String queryTitle;
  final String? currentId;
  final void Function(Drama) onSelect;

  const _AggregateResults({
    required this.groups,
    required this.searching,
    required this.allDone,
    required this.queryTitle,
    required this.currentId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('可播来源', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: Spacing.sm),
              if (searching)
                SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: subtitle),
                ),
              if (searching) const SizedBox(width: Spacing.sm),
              if (searching)
                Expanded(
                  child: Text(
                    allDone ? '' : '正在检索各源…（搜到一个显一个）',
                    style: TextStyle(fontSize: 12, color: subtitle),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          if (!searching && groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
              child: Text('未在各源找到「$queryTitle」的可播版本', style: TextStyle(fontSize: 13, color: subtitle)),
            ),
          for (final group in groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: Spacing.sm, bottom: Spacing.xs),
              child: Text(group.siteName,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: subtitle)),
            ),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                for (final r in group.results.take(12))
                  ActionChip(
                    label: Text(
                      r.title,
                      style: TextStyle(
                        fontSize: 12,
                        color: r.id == currentId
                            ? Brand.accent(Theme.of(context).brightness)
                            : null,
                      ),
                    ),
                    onPressed: () => onSelect(r),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
