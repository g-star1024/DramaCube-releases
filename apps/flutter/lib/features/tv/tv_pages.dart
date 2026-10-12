import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/models/models.dart';
import '../catalog/catalog_repository.dart';
import '../discover/discover_engine.dart';
import '../live/live_manager.dart';
import '../player/player_page.dart';
import 'tv_focus.dart';
import 'tv_keyboard.dart';
import 'tv_shelf.dart';
import 'tv_spotlight.dart';
import 'tv_theme.dart';

// MARK: - TV 首页（聚光灯 + 陈列栏）

/// TV 首页 —— 聚光灯 Top6 + 四分区陈列栏。
class TvHomePage extends ConsumerStatefulWidget {
  const TvHomePage({super.key});

  @override
  ConsumerState<TvHomePage> createState() => _TvHomePageState();
}

class _TvHomePageState extends ConsumerState<TvHomePage> {
  List<TvSpotlightItem> _spotlight = [];
  final List<_TvSection> _sections = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final engine = ref.read(discoverEngineProvider);
    final movie = await engine.doubanHot(kind: 'movie', category: '热门', type: '全部', limit: 18);
    final tv = await engine.doubanHot(kind: 'tv', category: 'tv', type: 'tv', limit: 18);
    final show = await engine.doubanHot(kind: 'tv', category: 'show', type: 'show', limit: 18);
    final anime = await engine.bilibiliBangumiRank(limit: 18);
    if (!mounted) return;
    setState(() {
      _spotlight = movie.take(6).map((e) => TvSpotlightItem(
            title: e.title,
            subtitle: e.rate.isNotEmpty ? '豆瓣 ${e.rate} 分' : null,
            coverURL: e.poster,
          )).toList();
      _sections
        ..clear()
        ..addAll([
          if (movie.isNotEmpty) _TvSection('热门电影', movie, 'movie'),
          if (tv.isNotEmpty) _TvSection('热门剧集', tv, 'tv'),
          if (show.isNotEmpty) _TvSection('热门综艺', show, 'tv'),
          if (anime.isNotEmpty) _TvSection('热门动漫', anime, 'bangumi'),
        ]);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: TvColors.focus),
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        TvSpotlight(
          items: _spotlight,
          onPlay: (i) => _openSpotlight(i),
        ),
        for (final s in _sections)
          TvShelf(
            title: s.title,
            itemCount: s.items.length,
            onItemPressed: (i) => _openItem(s.items[i], s.kind),
            itemBuilder: (context, i, focused) => TvPosterCard(
              title: s.items[i].title,
              subtitle: s.items[i].rate.isNotEmpty ? s.items[i].rate : null,
              coverURL: s.items[i].poster,
              focused: focused,
            ),
          ),
        const SizedBox(height: 40),
      ],
    );
  }

  void _openSpotlight(int i) {
    if (_sections.isEmpty) return;
    _openItem(_sections.first.items[i], _sections.first.kind);
  }

  void _openItem(DoubanHotItem item, String kind) {
    context.push('/tv/detail', extra: {'drama': item.toDrama(kind)});
  }
}

class _TvSection {
  final String title;
  final List<DoubanHotItem> items;
  final String kind;
  _TvSection(this.title, this.items, this.kind);
}

// MARK: - TV 详情页

/// TV 详情页 —— 信息 + 选集（焦点网格）；豆瓣条目先聚合搜索可播源。
class TvDetailPage extends ConsumerStatefulWidget {
  final Drama drama;
  const TvDetailPage({super.key, required this.drama});

  @override
  ConsumerState<TvDetailPage> createState() => _TvDetailPageState();
}

class _TvDetailPageState extends ConsumerState<TvDetailPage> {
  Drama? _drama;
  DramaDetail? _detail;
  bool _loading = false;
  bool _searching = false;
  final List<({String site, List<Drama> results})> _groups = [];

  @override
  void initState() {
    super.initState();
    _drama = widget.drama;
    _init();
  }

  Future<void> _init() async {
    final parts = _drama!.id.split('|');
    if (parts.first == 'douban') {
      _aggregate();
    } else {
      await _loadDetail();
    }
  }

  Future<void> _loadDetail() async {
    final parts = _drama!.id.split('|');
    if (parts.first != 'tvbox' || parts.length < 3) return;
    setState(() => _loading = true);
    final detail = await ref.read(catalogRepositoryProvider).detail(
          siteKey: parts[1],
          vodId: parts.sublist(2).join('|'),
        );
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _loading = false;
    });
  }

  void _aggregate() {
    setState(() {
      _searching = true;
      _groups.clear();
    });
    ref.read(catalogRepositoryProvider).aggregateSearch(
          query: DiscoverEngine.normalize(_drama!.title),
          onSiteDone: (site, results) {
            if (!mounted) return;
            setState(() => _groups.add((site: site, results: results)));
          },
          onAllDone: () {
            if (mounted) setState(() => _searching = false);
          },
        );
  }

  void _play(int index) {
    final detail = _detail;
    if (detail == null || detail.episodes.isEmpty) return;
    context.push('/tv/player', extra: {
      'detail': detail,
      'startIndex': index,
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail?.drama ?? _drama!;
    return Scaffold(
      backgroundColor: TvColors.background,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            TvSafeArea.left, TvSafeArea.top / 2, TvSafeArea.right, TvSafeArea.bottom / 2),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 180,
                  height: 240,
                  child: d.coverURL != null && d.coverURL!.isNotEmpty
                      ? Image.network(d.coverURL!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: TvColors.surfaceHi))
                      : Container(color: TvColors.surfaceHi),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.title,
                        style: const TextStyle(
                            color: TvColors.onSurface,
                            fontSize: TvText.title,
                            fontWeight: FontWeight.bold)),
                    if ((d.remark ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(d.remark!,
                          style: const TextStyle(
                              color: TvColors.muted, fontSize: TvText.body)),
                    ],
                    if (_detail != null) ...[
                      const SizedBox(height: 20),
                      TvFocusable(
                        onPressed: () => _play(0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 14),
                          decoration: BoxDecoration(
                            color: TvColors.focus,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded,
                                  color: TvColors.background, size: 28),
                              SizedBox(width: 8),
                              Text('播放',
                                  style: TextStyle(
                                      color: TvColors.background,
                                      fontSize: TvText.body,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          if (_loading)
            Center(
                child: CircularProgressIndicator(color: TvColors.focus)),
          if (_detail != null && _detail!.episodes.isNotEmpty) ...[
            Text('选集（${_detail!.episodes.length} 集）',
                style: const TextStyle(
                    color: TvColors.onSurface, fontSize: TvText.body)),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 2.4,
              ),
              itemCount: _detail!.episodes.length,
              itemBuilder: (context, i) => TvFocusable(
                autofocus: i == 0,
                onPressed: () => _play(i),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: TvColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: TvColors.surfaceHi),
                  ),
                  child: Text(
                    _detail!.episodes[i].title,
                    style: const TextStyle(
                        color: TvColors.onSurface, fontSize: TvText.caption),
                  ),
                ),
              ),
            ),
          ],
          if (_searching || _groups.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text(
              _searching ? '正在检索各源…' : '可播来源',
              style: const TextStyle(
                  color: TvColors.onSurface, fontSize: TvText.body),
            ),
            const SizedBox(height: 12),
            for (final g in _groups)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.site,
                        style: TextStyle(
                            color: TvColors.focus, fontSize: TvText.caption)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final r in g.results.take(12))
                          TvFocusable(
                            onPressed: () {
                              setState(() {
                                _drama = r;
                                _detail = null;
                              });
                              _loadDetail();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 12),
                              decoration: BoxDecoration(
                                color: TvColors.surface,
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: TvColors.surfaceHi),
                              ),
                              child: Text(r.title,
                                  style: const TextStyle(
                                      color: TvColors.onSurface,
                                      fontSize: TvText.caption)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// MARK: - TV 搜索页

/// TV 搜索页 —— 大格键盘 + 聚合结果陈列栏。
class TvSearchPage extends ConsumerStatefulWidget {
  const TvSearchPage({super.key});

  @override
  ConsumerState<TvSearchPage> createState() => _TvSearchPageState();
}

class _TvSearchPageState extends ConsumerState<TvSearchPage> {
  bool _searching = false;
  String? _playingId; // 正在拉取详情准备播放的结果 id
  final List<({String site, List<Drama> results})> _groups = [];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// 点击搜索结果直接播放第一集（不再经详情页跳转）；长按才进详情。
  Future<void> _play(Drama r) async {
    final parts = r.id.split('|');
    if (parts.length != 3) return;
    setState(() => _playingId = r.id);
    final detail = await ref
        .read(catalogRepositoryProvider)
        .detail(siteKey: parts[1], vodId: parts[2]);
    if (!mounted) return;
    setState(() => _playingId = null);
    if (detail == null || detail.episodes.isEmpty) return;
    context.push('/tv/player', extra: {
      'detail': detail,
      'startIndex': 0,
    });
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (q.trim().isEmpty) {
        setState(() => _groups.clear());
        return;
      }
      _search(q.trim());
    });
  }

  void _search(String q) {
    setState(() {
      _searching = true;
      _groups.clear();
    });
    ref.read(catalogRepositoryProvider).aggregateSearch(
          query: q,
          onSiteDone: (site, results) {
            if (!mounted) return;
            setState(() => _groups.add((site: site, results: results)));
          },
          onAllDone: () {
            if (mounted) setState(() => _searching = false);
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvColors.background,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            TvSafeArea.left, TvSafeArea.top / 2, TvSafeArea.right, TvSafeArea.bottom / 2),
        children: [
          const Text('搜索',
              style: TextStyle(
                  color: TvColors.onSurface,
                  fontSize: TvText.title,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          TvKeyboard(onChanged: _onQueryChanged),
          const SizedBox(height: 24),
          if (_searching)
            Center(
                child: CircularProgressIndicator(color: TvColors.focus)),
          for (final g in _groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.site,
                      style: TextStyle(
                          color: TvColors.focus, fontSize: TvText.caption)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final r in g.results.take(12))
                        TvFocusable(
                          onPressed: () => _play(r),
                          onLongPress: () => context.push('/tv/detail',
                              extra: {'drama': r}),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 12),
                            decoration: BoxDecoration(
                              color: TvColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: TvColors.surfaceHi),
                            ),
                            child: _playingId == r.id
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: TvColors.focus),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(r.title,
                                          style: const TextStyle(
                                              color: TvColors.onSurface,
                                              fontSize: TvText.caption)),
                                    ],
                                  )
                                : Text(r.title,
                                    style: const TextStyle(
                                        color: TvColors.onSurface,
                                        fontSize: TvText.caption)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// MARK: - TV 直播页

/// TV 直播页 —— 频道列表（焦点可达），选中后进入全屏直播播放。
class TvLivePage extends ConsumerStatefulWidget {
  const TvLivePage({super.key});

  @override
  ConsumerState<TvLivePage> createState() => _TvLivePageState();
}

class _TvLivePageState extends ConsumerState<TvLivePage> {
  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveManagerProvider);
    final channels = live.channels;
    return Scaffold(
      backgroundColor: TvColors.background,
      body: channels.isEmpty
          ? const Center(
              child: Text('暂无直播源，请在设置中添加',
                  style: TextStyle(
                      color: TvColors.muted, fontSize: TvText.body)),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(
                  TvSafeArea.left, 40, TvSafeArea.right, TvSafeArea.bottom / 2),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
                childAspectRatio: 1.6,
              ),
              itemCount: channels.length,
              itemBuilder: (context, i) => TvFocusable(
                autofocus: i == 0,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _TvLivePlayerPage(channel: channels[i]),
                  ),
                ),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: TvColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: TvColors.surfaceHi),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.live_tv_rounded,
                          color: TvColors.focus, size: 36),
                      const SizedBox(height: 10),
                      Text(channels[i].name,
                          style: const TextStyle(
                              color: TvColors.onSurface,
                              fontSize: TvText.caption)),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// TV 直播全屏播放（轻量内嵌播放器）。
class _TvLivePlayerPage extends StatefulWidget {
  final LiveChannel channel;
  const _TvLivePlayerPage({required this.channel});

  @override
  State<_TvLivePlayerPage> createState() => _TvLivePlayerPageState();
}

class _TvLivePlayerPageState extends State<_TvLivePlayerPage> {
  late final _player = Player();
  late final _controller = VideoController(_player);

  @override
  void initState() {
    super.initState();
    _player.open(Media(widget.channel.url));
    _player.play();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Video(controller: _controller),
          Positioned(
            top: TvSafeArea.top / 3,
            left: TvSafeArea.left,
            child: TvFocusable(
              onPressed: () => Navigator.of(context).pop(),
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: TvColors.surfaceHi,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: TvColors.onSurface),
              ),
            ),
          ),
          Positioned(
            top: TvSafeArea.top / 3,
            left: TvSafeArea.left + 64,
            child: Text(widget.channel.name,
                style: const TextStyle(
                    color: TvColors.onSurface, fontSize: TvText.body)),
          ),
        ],
      ),
    );
  }
}

// MARK: - TV 我的（收藏/历史入口占位）

/// TV 我的 —— 收藏与历史概览（只读列表，管理请在手机/桌面端完成）。
class TvMinePage extends ConsumerStatefulWidget {
  const TvMinePage({super.key});

  @override
  ConsumerState<TvMinePage> createState() => _TvMinePageState();
}

class _TvMinePageState extends ConsumerState<TvMinePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvColors.background,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
            TvSafeArea.left, 40, TvSafeArea.right, TvSafeArea.bottom / 2),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('我的',
                style: TextStyle(
                    color: TvColors.onSurface,
                    fontSize: TvText.title,
                    fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            Text('收藏与播放历史请在手机 / 桌面端管理，电视端仅提供观看。',
                style: TextStyle(color: TvColors.muted, fontSize: TvText.body)),
          ],
        ),
      ),
    );
  }
}

/// TV 播放器包装（电视模式下 PlayerPage 自动切换 TV OSD）。
Widget tvPlayerRouteBuilder(DramaDetail detail, int startIndex) =>
    PlayerPage(detail: detail, startIndex: startIndex);
