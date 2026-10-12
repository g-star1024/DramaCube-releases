import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_system.dart';
import '../../core/models/models.dart';
import '../../core/widgets/cover_image.dart';
import '../../core/widgets/gradient_button.dart';
import '../catalog/catalog_repository.dart';
import '../discover/discover_engine.dart';
import '../downloads/download_manager.dart';

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

  // MARK: 批量下载选集

  Future<void> _showDownloadDialog() async {
    final detail = _detail!;
    final selected = <int>{0};
    final enqueued = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('下载选集（${detail.episodes.length} 集）'),
          content: SizedBox(
            width: 360,
            child: Column(
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setDialog(() {
                        selected.clear();
                        selected.addAll(List.generate(detail.episodes.length, (i) => i));
                      }),
                      child: const Text('全选'),
                    ),
                    TextButton(
                      onPressed: () => setDialog(() => selected.clear()),
                      child: const Text('清空'),
                    ),
                  ],
                ),
                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 100,
                      mainAxisSpacing: Radii.sm,
                      crossAxisSpacing: Radii.sm,
                      childAspectRatio: 2.4,
                    ),
                    itemCount: detail.episodes.length,
                    itemBuilder: (ctx, i) {
                      final on = selected.contains(i);
                      return FilterChip(
                        label: Text(detail.episodes[i].title,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12)),
                        selected: on,
                        onSelected: (v) => setDialog(() {
                          v ? selected.add(i) : selected.remove(i);
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, selected.length),
              child: Text('下载所选（${selected.length}）'),
            ),
          ],
        ),
      ),
    );
    if (enqueued == null || enqueued == 0) return;
    final mgr = ref.read(downloadManagerProvider.notifier);
    for (final i in selected) {
      final ep = detail.episodes[i];
      if (ep.playURL == null || ep.playURL!.isEmpty) continue;
      await mgr.enqueue(
        dramaId: detail.drama.id,
        episodeId: ep.id,
        title: detail.drama.title,
        episodeTitle: ep.title,
        url: ep.playURL!,
        coverURL: detail.drama.coverURL,
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已加入 $enqueued 个下载任务')),
    );
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
      body: CustomScrollView(
        slivers: [
          // 沉浸式头部：封面铺底虚化压暗 + 前景清晰封面 + 信息
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            title: Text(drama?.title ?? '详情', style: const TextStyle(fontSize: 16)),
            actions: [
              IconButton(
                icon: const Icon(Icons.download_outlined),
                tooltip: '下载选集',
                onPressed: _detail == null || _detail!.episodes.isEmpty
                    ? null
                    : _showDownloadDialog,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // 封面铺底：虚化 + 压暗
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: CoverImage(
                        url: drama?.coverURL, title: drama?.title ?? ''),
                  ),
                  Container(color: Colors.black.withValues(alpha: 0.45)),
                  // 底部渐变融入页面背景
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.5, 1.0],
                        colors: [
                          Colors.transparent,
                          Brand.background(brightness),
                        ],
                      ),
                    ),
                  ),
                  // 前景：清晰封面（Hero 共享元素）+ 标题信息
                  Positioned(
                    left: Spacing.lg,
                    right: Spacing.lg,
                    bottom: Spacing.md,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Hero(
                          tag: 'cover-${drama?.id ?? ''}',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(Radii.md),
                            child: SizedBox(
                              width: 120,
                              height: 160,
                              child: CoverImage(
                                  url: drama?.coverURL,
                                  title: drama?.title ?? ''),
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.lg),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  drama?.title ?? '',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: text),
                                ),
                                if ((drama?.remark ?? '').isNotEmpty) ...[
                                  const SizedBox(height: Spacing.xs),
                                  Text(drama!.remark!,
                                      style: TextStyle(
                                          fontSize: 13, color: subtitle)),
                                ],
                                if (_subject != null &&
                                    _subject!.cardSubtitle.isNotEmpty) ...[
                                  const SizedBox(height: Spacing.xs),
                                  Text(_subject!.cardSubtitle,
                                      style: TextStyle(
                                          fontSize: 13, color: subtitle)),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 胶囊操作区
                  Row(
                    children: [
                      GradientButton(
                        label: '立即观看',
                        icon: Icons.play_arrow_rounded,
                        height: 42,
                        onTap: _detail != null && _detail!.episodes.isNotEmpty
                            ? () => _play(0)
                            : null,
                      ),
                      const SizedBox(width: Spacing.md),
                      OutlinedButton.icon(
                        onPressed: _detail == null || _detail!.episodes.isEmpty
                            ? null
                            : _showDownloadDialog,
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: const Text('下载'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          shape: const StadiumBorder(),
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
                          Text('简介',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: text)),
                          const SizedBox(height: Spacing.sm),
                          Text(_subject!.intro,
                              style: TextStyle(
                                  fontSize: 13,
                                  height: 1.6,
                                  color: subtitle)),
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
                      child: Text(_error!,
                          style: TextStyle(fontSize: 13, color: subtitle)),
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
            ),
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
                    borderRadius: BorderRadius.circular(Radii.sm),
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
