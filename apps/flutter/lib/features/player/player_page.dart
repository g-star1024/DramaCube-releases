import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/design_system.dart';
import '../../app/settings_provider.dart';
import '../../core/db/database.dart';
import '../../core/models/models.dart';
import '../catalog/catalog_repository.dart';
import '../discover/discover_engine.dart';

/// 播放器页（media_kit libmpv 内核，U3 功能对齐 macOS 版 mpv）。
///
/// - 选集面板（胶囊网格 + 当前定位 + 已看标记）
/// - 播放中换源（跨源搜索 + 续播位置保留）+ 查找其他季
/// - 自动连播 / 跳片头 / 下集预缓冲（90% 预热）
/// - 双击全屏（桌面）/ 音量控制 / 错误覆盖层 / 倍速写回全局设置
class PlayerPage extends ConsumerStatefulWidget {
  final DramaDetail detail;
  final int startIndex;

  const PlayerPage({super.key, required this.detail, this.startIndex = 0});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  late final _player = Player();
  late final _controller = VideoController(_player);
  late final _db = AppDatabase();

  late DramaDetail _detail;
  late int _currentIndex;
  Timer? _progressTimer;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<String>? _errorSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _playerError;
  bool _switching = false;

  // 自动连播防重入
  bool _autoNextFired = false;
  // 下集预缓冲 Player（90% 时预热）
  Player? _prebuffer;
  bool _prebuffered = false;

  // 已看集（历史里出现过的 episodeId）
  Set<String> _watchedIds = {};

  // 换源搜索缓存
  List<_SiteGroup> _sourceGroups = [];
  List<Drama> _otherSeasons = [];
  bool _sourceSearching = false;
  String _sourceQuery = '';

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    _detail = widget.detail;
    _currentIndex = widget.startIndex.clamp(0, _detail.episodes.length - 1);
    _positionSub = _player.stream.position.listen((d) {
      _position = d;
      _maybeAutoNext();
      _maybePrebuffer();
    });
    _durationSub = _player.stream.duration.listen((d) {
      _duration = d;
      _maybeSkipIntro();
    });
    _errorSub = _player.stream.error.listen((msg) {
      if (msg.isNotEmpty && mounted) setState(() => _playerError = msg);
    });
    _loadWatched();
    _loadEpisode(_currentIndex);
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());

    // 初始倍速 = 全局默认倍速
    final settings = ref.read(settingsProvider);
    if (settings.defaultRate != 1.0) {
      _player.setRate(settings.defaultRate);
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _errorSub?.cancel();
    _saveProgress();
    _player.dispose();
    _prebuffer?.dispose();
    _db.close();
    super.dispose();
  }

  Future<void> _loadWatched() async {
    final hists = await _db.allHistories();
    if (!mounted) return;
    setState(() {
      _watchedIds = hists
          .where((h) => h.dramaId == _detail.drama.id)
          .map((h) => h.episodeId)
          .toSet();
    });
  }

  static const _ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15';

  Map<String, String> _headersFor(String url) => url.contains('.m3u8')
      ? {
          'User-Agent': _ua,
          'Referer': '${Uri.parse(url).scheme}://${Uri.parse(url).host}/',
        }
      : {};

  Future<void> _loadEpisode(int index, {Duration? resumeAt}) async {
    if (index < 0 || index >= _detail.episodes.length) return;
    if (index != _currentIndex) await _saveProgress();
    setState(() {
      _currentIndex = index;
      _playerError = null;
      _autoNextFired = false;
      _prebuffered = false;
    });
    final ep = _detail.episodes[index];
    final url = ep.playURL;
    if (url == null || url.isEmpty) {
      setState(() => _playerError = '该集播放地址为空');
      return;
    }

    // 续播位置：显式传入（换源保留）> 历史记录
    Duration? seekTo = resumeAt;
    if (seekTo == null) {
      final history = await _db.progressOf(_detail.drama.id, ep.id);
      if (history != null && history.position > 5) {
        seekTo = Duration(seconds: history.position.toInt());
      }
    }

    await _player.open(Media(url, httpHeaders: _headersFor(url)));
    if (seekTo != null) await _player.seek(seekTo);
    await _player.play();
  }

  Future<void> _saveProgress() async {
    if (_position.inSeconds < 5 || _duration.inSeconds <= 0) return;
    if (_position.inSeconds >= _duration.inSeconds - 2) return; // 播完不存
    final ep = _detail.episodes[_currentIndex];
    await _db.saveProgress(
      dramaId: _detail.drama.id,
      episodeId: ep.id,
      title: _detail.drama.title,
      episodeTitle: ep.title,
      coverURL: _detail.drama.coverURL,
      position: _position.inSeconds.toDouble(),
      duration: _duration.inSeconds.toDouble(),
    );
  }

  // MARK: - 自动连播 / 跳片头 / 预缓冲

  void _maybeAutoNext() {
    if (_autoNextFired || _duration.inSeconds <= 0) return;
    if (_position.inMilliseconds < _duration.inMilliseconds - 800) return;
    _autoNextFired = true;
    final settings = ref.read(settingsProvider);
    if (settings.autoPlayNext && _currentIndex < _detail.episodes.length - 1) {
      _loadEpisode(_currentIndex + 1);
    }
  }

  void _maybeSkipIntro() {
    final skip = ref.read(settingsProvider).introSkipSeconds;
    if (skip <= 0 || _duration.inSeconds < 60) return;
    if (_position.inSeconds > 0 && _position.inSeconds < skip) {
      _player.seek(Duration(seconds: skip));
    }
  }

  void _maybePrebuffer() {
    if (_prebuffered || _duration.inSeconds <= 0) return;
    if (_position.inSeconds < _duration.inSeconds * 0.9) return;
    if (_currentIndex >= _detail.episodes.length - 1) return;
    _prebuffered = true;
    final nextURL = _detail.episodes[_currentIndex + 1].playURL;
    if (nextURL == null || nextURL.isEmpty) return;
    // 静默预热下一集（加载但不播放，建立连接 + 分片缓存）
    () async {
      await _prebuffer?.dispose();
      final p = Player();
      _prebuffer = p;
      await p.setVolume(0);
      await p.open(Media(nextURL, httpHeaders: _headersFor(nextURL)), play: false);
    }();
  }

  // MARK: - 换源 / 其他季

  Future<void> _openSourceSheet() async {
    if (_sourceGroups.isEmpty && _otherSeasons.isEmpty && !_sourceSearching) {
      _searchSources();
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SourceSheet(
        groups: _sourceGroups,
        otherSeasons: _otherSeasons,
        searching: _sourceSearching,
        query: _sourceQuery,
        currentId: _detail.drama.id,
        onSelect: (d) {
          Navigator.pop(ctx);
          _switchSource(d, episodeIndex: _currentIndex, resumeAt: _position);
        },
        onSeasonSelect: (d) {
          Navigator.pop(ctx);
          _switchSource(d, episodeIndex: 0, resumeAt: null);
        },
        onRetry: _searchSources,
      ),
    );
  }

  void _searchSources() {
    setState(() {
      _sourceSearching = true;
      _sourceGroups.clear();
      _otherSeasons.clear();
    });
    _sourceQuery = DiscoverEngine.normalize(_detail.drama.title);
    ref.read(catalogRepositoryProvider).aggregateSearch(
          query: _sourceQuery,
          onSiteDone: (siteName, results) {
            if (!mounted) return;
            final same = results
                .where((r) => DiscoverEngine.normalize(r.title) == _sourceQuery)
                .toList();
            final diff = results
                .where((r) =>
                    DiscoverEngine.normalize(r.title) != _sourceQuery &&
                    (DiscoverEngine.normalize(r.title).contains(_sourceQuery) ||
                        _sourceQuery.contains(DiscoverEngine.normalize(r.title))))
                .toList();
            setState(() {
              if (same.isNotEmpty) _sourceGroups.add(_SiteGroup(siteName, same));
              for (final d in diff) {
                if (!_otherSeasons.any((s) => s.id == d.id)) _otherSeasons.add(d);
              }
            });
          },
          onAllDone: () {
            if (mounted) setState(() => _sourceSearching = false);
          },
        );
  }

  /// 换源：加载新源详情，定位到同 index 集，保留续播位置。
  Future<void> _switchSource(Drama drama,
      {required int episodeIndex, Duration? resumeAt}) async {
    final parts = drama.id.split('|');
    if (parts.first != 'tvbox' || parts.length < 3) return;
    setState(() => _switching = true);
    final detail = await ref
        .read(catalogRepositoryProvider)
        .detail(siteKey: parts[1], vodId: parts.sublist(2).join('|'));
    if (!mounted) return;
    if (detail == null || detail.episodes.isEmpty) {
      setState(() {
        _switching = false;
        _playerError = '换源失败：新源无可用集数';
      });
      return;
    }
    setState(() {
      _detail = detail;
      _watchedIds = {};
      _sourceGroups = [];
      _otherSeasons = [];
      _switching = false;
    });
    await _loadWatched();
    final idx = episodeIndex.clamp(0, detail.episodes.length - 1);
    await _loadEpisode(idx, resumeAt: resumeAt);
  }

  // MARK: - 全屏（桌面）

  bool _fullscreen = false;

  Future<void> _toggleFullscreen() async {
    if (!mounted) return;
    setState(() => _fullscreen = !_fullscreen);
    if (!kIsWeb && _isDesktop) {
      try {
        await windowManager.setFullScreen(_fullscreen);
      } catch (_) {}
    } else if (!kIsWeb) {
      // 移动端：沉浸式
      if (_fullscreen) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
  }

  // MARK: - UI

  @override
  Widget build(BuildContext context) {
    final ep = _detail.episodes[_currentIndex];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _fullscreen
          ? null
          : AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text('${_detail.drama.title} · ${ep.title}'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.grid_view_outlined),
                  tooltip: '选集',
                  onPressed: _openEpisodesSheet,
                ),
                IconButton(
                  icon: const Icon(Icons.swap_horiz),
                  tooltip: '换源',
                  onPressed: _openSourceSheet,
                ),
              ],
            ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                GestureDetector(
                  onDoubleTap: _toggleFullscreen,
                  child: Video(controller: _controller),
                ),
                // 加载 / 换源中
                if (_switching)
                  const ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Brand.pinkDark),
                          SizedBox(height: Spacing.md),
                          Text('正在切换源…', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                // 错误覆盖层
                if (_playerError != null && !_switching)
                  _ErrorOverlay(
                    message: _playerError!,
                    episodeTitle: ep.title,
                    onRetry: () => _loadEpisode(_currentIndex),
                    onSwitchSource: _openSourceSheet,
                    onNextEpisode: _currentIndex < _detail.episodes.length - 1
                        ? () => _loadEpisode(_currentIndex + 1)
                        : null,
                  ),
              ],
            ),
          ),
          // 进度条 + 控制条
          _buildControls(ep),
        ],
      ),
    );
  }

  Widget _buildControls(Episode ep) {
    return SafeArea(
      child: Container(
        color: Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度条
            StreamBuilder<Duration>(
              stream: _player.stream.position,
              builder: (context, posSnap) => StreamBuilder<Duration>(
                stream: _player.stream.duration,
                builder: (context, durSnap) {
                  final pos = posSnap.data ?? _position;
                  final dur = durSnap.data ?? _duration;
                  return Row(
                    children: [
                      Text(_fmt(pos),
                          style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape:
                                const RoundSliderThumbShape(enabledThumbRadius: 6),
                          ),
                          child: Slider(
                            value: dur.inSeconds > 0
                                ? (pos.inSeconds / dur.inSeconds).clamp(0.0, 1.0)
                                : 0,
                            onChanged: (v) => _player.seek(
                                Duration(seconds: (v * dur.inSeconds).toInt())),
                          ),
                        ),
                      ),
                      Text('-${_fmt(dur - pos)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  );
                },
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: Colors.white),
                  onPressed: _currentIndex > 0
                      ? () => _loadEpisode(_currentIndex - 1)
                      : null,
                ),
                StreamBuilder<bool>(
                  stream: _player.stream.playing,
                  builder: (context, snap) => IconButton(
                    icon: Icon(snap.data == true ? Icons.pause : Icons.play_arrow,
                        color: Colors.white, size: 32),
                    onPressed: () => _player.playOrPause(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white),
                  onPressed: _currentIndex < _detail.episodes.length - 1
                      ? () => _loadEpisode(_currentIndex + 1)
                      : null,
                ),
                const Spacer(),
                // 音量
                StreamBuilder<double>(
                  stream: _player.stream.volume,
                  builder: (context, snap) => PopupMenuButton<double>(
                    initialValue: snap.data ?? 100,
                    onSelected: (v) => _player.setVolume(v),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 0.0, child: Text('静音')),
                      const PopupMenuItem(value: 50.0, child: Text('50%')),
                      const PopupMenuItem(value: 100.0, child: Text('100%')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                      child: Icon(
                        (snap.data ?? 100) == 0
                            ? Icons.volume_off
                            : (snap.data ?? 100) < 50
                                ? Icons.volume_down
                                : Icons.volume_up,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                // 倍速（写回全局设置）
                StreamBuilder<double>(
                  stream: _player.stream.rate,
                  builder: (context, snap) => PopupMenuButton<double>(
                    initialValue: snap.data ?? 1.0,
                    onSelected: (rate) {
                      _player.setRate(rate);
                      ref.read(settingsProvider.notifier).setDefaultRate(rate);
                    },
                    itemBuilder: (_) => [
                      for (final r in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0])
                        PopupMenuItem(value: r, child: Text('${r}x')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                      child: Text('${snap.data ?? 1.0}x',
                          style: const TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  ),
                ),
                // 全屏
                IconButton(
                  icon: Icon(
                    _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: Colors.white,
                  ),
                  onPressed: _toggleFullscreen,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - 选集面板（底部抽屉）

  Future<void> _openEpisodesSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EpisodesSheet(
        detail: _detail,
        currentIndex: _currentIndex,
        watchedIds: _watchedIds,
        onPlay: (i) {
          Navigator.pop(ctx);
          _loadEpisode(i);
        },
      ),
    );
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}

/// window_manager 全屏封装已内联（桌面端 guard 后调用）。

class _SiteGroup {
  final String siteName;
  final List<Drama> results;
  _SiteGroup(this.siteName, this.results);
}

/// 错误覆盖层（重试 / 换源 / 下集）。
class _ErrorOverlay extends StatelessWidget {
  final String message;
  final String episodeTitle;
  final VoidCallback onRetry;
  final VoidCallback onSwitchSource;
  final VoidCallback? onNextEpisode;

  const _ErrorOverlay({
    required this.message,
    required this.episodeTitle,
    required this.onRetry,
    required this.onSwitchSource,
    this.onNextEpisode,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 44),
            const SizedBox(height: Spacing.md),
            Text('「$episodeTitle」播放失败',
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            const SizedBox(height: Spacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
                const SizedBox(width: Spacing.sm),
                OutlinedButton.icon(
                  onPressed: onSwitchSource,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('换源'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                ),
                if (onNextEpisode != null) ...[
                  const SizedBox(width: Spacing.sm),
                  OutlinedButton.icon(
                    onPressed: onNextEpisode,
                    icon: const Icon(Icons.skip_next),
                    label: const Text('下集'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 选集底部面板（胶囊网格 + 当前定位 + 已看标记）。
class _EpisodesSheet extends StatelessWidget {
  final DramaDetail detail;
  final int currentIndex;
  final Set<String> watchedIds;
  final void Function(int) onPlay;

  const _EpisodesSheet({
    required this.detail,
    required this.currentIndex,
    required this.watchedIds,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final eps = detail.episodes;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: Brand.background(Theme.of(ctx).brightness),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Row(
                children: [
                  Text('选集（${eps.length} 集）',
                      style: Theme.of(ctx).textTheme.titleMedium),
                  const Spacer(),
                  Text('已看 ${watchedIds.length} 集',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.lg),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 110,
                  mainAxisSpacing: Spacing.sm,
                  crossAxisSpacing: Spacing.sm,
                  childAspectRatio: 2.6,
                ),
                itemCount: eps.length,
                itemBuilder: (ctx, i) {
                  final isCurrent = i == currentIndex;
                  final isWatched = watchedIds.contains(eps[i].id);
                  return OutlinedButton(
                    onPressed: () => onPlay(i),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: isCurrent
                          ? Brand.accent(Theme.of(ctx).brightness)
                          : null,
                      foregroundColor: isCurrent
                          ? Colors.white
                          : Brand.accent(Theme.of(ctx).brightness),
                      side: BorderSide(
                        color: isCurrent
                            ? Brand.accent(Theme.of(ctx).brightness)
                            : Brand.separator(Theme.of(ctx).brightness),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            eps[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (isWatched && !isCurrent) ...[
                          const SizedBox(width: 3),
                          const Icon(Icons.check, size: 12),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 换源底部面板（同源分组 chips + 其他季）。
class _SourceSheet extends StatelessWidget {
  final List<_SiteGroup> groups;
  final List<Drama> otherSeasons;
  final bool searching;
  final String query;
  final String currentId;
  final void Function(Drama) onSelect;
  final void Function(Drama) onSeasonSelect;
  final VoidCallback onRetry;

  const _SourceSheet({
    required this.groups,
    required this.otherSeasons,
    required this.searching,
    required this.query,
    required this.currentId,
    required this.onSelect,
    required this.onSeasonSelect,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Brand.accent(Theme.of(context).brightness);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: Brand.background(Theme.of(ctx).brightness),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            Row(
              children: [
                Text('换源播放', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(width: Spacing.sm),
                if (searching)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                const Spacer(),
                if (!searching && groups.isEmpty && otherSeasons.isEmpty)
                  TextButton(onPressed: onRetry, child: const Text('重新搜索')),
              ],
            ),
            Text('「$query」在各源的可播版本，切换后保留当前进度',
                style: TextStyle(
                    fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: Spacing.lg),
            for (final g in groups) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: Text(g.siteName,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accent)),
              ),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  for (final r in g.results)
                    ActionChip(
                      label: Text(
                        r.title,
                        style: TextStyle(
                          fontSize: 12,
                          color: r.id == currentId ? accent : null,
                        ),
                      ),
                      onPressed: () => onSelect(r),
                    ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
            ],
            if (otherSeasons.isNotEmpty) ...[
              Text('其他季 / 关联剧',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accent)),
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  for (final s in otherSeasons)
                    ActionChip(
                      avatar: const Icon(Icons.playlist_play, size: 16),
                      label: Text(s.title, style: const TextStyle(fontSize: 12)),
                      onPressed: () => onSeasonSelect(s),
                    ),
                ],
              ),
            ],
            if (!searching && groups.isEmpty && otherSeasons.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
                child: Center(
                  child: Text('未在其他源找到该剧',
                      style: TextStyle(
                          fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
