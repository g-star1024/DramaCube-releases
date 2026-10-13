import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/design_system.dart';
import '../../app/motion.dart';
import '../../app/settings_provider.dart';
import '../../core/db/database.dart';
import '../../core/models/models.dart';
import '../../core/platform/app_log.dart';
import '../../core/platform/player_remote.dart';
import '../../core/widgets/glass_panel.dart';
import '../catalog/catalog_repository.dart';
import '../discover/discover_engine.dart';
import '../tv/tv_player_osd.dart';

/// 播放器页（media_kit libmpv 内核，U3 功能对齐 macOS 版 mpv）。
///
/// S2 三端分化（v2.5）：
/// - 桌面：毛玻璃 OSD（自动隐藏 3s）+ 全套快捷键 + 暂停 3s 氛围模式（虚化当前帧）
/// - 移动：双击快进退（左 -10s / 右 +10s / 中全屏）+ 边缘滑（左亮度 / 右音量）
/// - 共通：选集/换源面板、自动连播、跳片头、下集预缓冲、倍速写回设置
class PlayerPage extends ConsumerStatefulWidget {
  final DramaDetail detail;
  final int startIndex;

  const PlayerPage({super.key, required this.detail, this.startIndex = 0});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  late final _player = Player(
    configuration: PlayerConfiguration(
      bufferSize: switch (ref.read(settingsProvider).bufferStrategy) {
        BufferStrategy.low => 8 * 1024 * 1024,
        BufferStrategy.medium => 32 * 1024 * 1024,
        BufferStrategy.high => 128 * 1024 * 1024,
      },
    ),
  );
  late final _controller = VideoController(_player);
  late final _db = AppDatabase();

  late DramaDetail _detail;
  late int _currentIndex;
  Timer? _progressTimer;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _playingSub;
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

  // ---- S2：OSD / 氛围模式 / 手势反馈 ----

  /// OSD 可见性（tap / 鼠标移动唤起，播放中 3s 自动隐藏）。
  bool _osdVisible = true;
  Timer? _osdHideTimer;

  /// 暂停氛围模式（暂停 3s 后虚化当前帧）。
  bool _ambience = false;
  Timer? _ambienceTimer;

  /// 双击快进反馈（'-10s' / '+10s'）。
  String? _seekFeedback;
  Timer? _seekFeedbackTimer;

  /// 边缘滑音量指示（0..100）。
  double? _volumeIndicator;
  double _volumeDragStart = 100;
  double _volumeDragValue = 100;

  /// 边缘滑亮度指示（0.05..1）。
  double? _brightnessIndicator;
  double _brightnessDragStart = 1;
  double _brightnessDragValue = 1;

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get _isMobile => !kIsWeb && !_isDesktop;

  @override
  void initState() {
    super.initState();
    _detail = widget.detail;
    _currentIndex = widget.startIndex.clamp(0, _detail.episodes.length - 1);
    AppLog.player('进入播放页 title=${_detail.drama.title} start=$_currentIndex epCount=${_detail.episodes.length}');
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
      if (msg.isNotEmpty) {
        AppLog.player('播放错误 ep=$_currentIndex err=$msg');
        if (mounted) setState(() => _playerError = msg);
      }
    });
    // 播放状态 → OSD 隐藏策略 + 暂停氛围模式
    _playingSub = _player.stream.playing.listen((playing) {
      if (!mounted) return;
      _ambienceTimer?.cancel();
      if (playing) {
        if (_ambience) setState(() => _ambience = false);
        _pokeOsd();
      } else {
        setState(() => _osdVisible = true);
        _ambienceTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _ambience = true);
        });
      }
    });
    _loadWatched();
    AppLog.player('initState 完成，开始加载 ep=$_currentIndex');
    _loadEpisode(_currentIndex);
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());

    // macOS 菜单栏遥控（对齐 Swift MenuBarController：播放暂停/上下集）。
    PlayerRemoteBridge.attach(
      togglePlay: () => _player.playOrPause(),
      next: () {
        if (_currentIndex < _detail.episodes.length - 1) _loadEpisode(_currentIndex + 1);
      },
      prev: () {
        if (_currentIndex > 0) _loadEpisode(_currentIndex - 1);
      },
    );

    // 起播倍速 = 设置中心「默认倍速」（播放器内临时调节不回写设置，避免覆盖用户配置）。
    final settings = ref.read(settingsProvider);
    if (settings.defaultRate != 1.0) {
      _player.setRate(settings.defaultRate);
    }
  }

  @override
  void dispose() {
    AppLog.player('退出播放页 ep=$_currentIndex pos=${_position.inSeconds}s');
    _progressTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _errorSub?.cancel();
    _playingSub?.cancel();
    _osdHideTimer?.cancel();
    _ambienceTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    PlayerRemoteBridge.detach();
    _saveProgress();
    _player.dispose();
    _prebuffer?.dispose();
    _db.close();
    super.dispose();
  }

  // MARK: - OSD 显隐 / 氛围 / 反馈

  /// 唤起 OSD 并重置 3s 隐藏计时（暂停时常显）。
  void _pokeOsd() {
    if (!mounted) return;
    if (!_osdVisible) AppLog.player('唤起 OSD');
    setState(() {
      _osdVisible = true;
      _ambience = false;
    });
    _osdHideTimer?.cancel();
    _osdHideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      // 暂停中不隐藏（营造氛围模式前置态）
      if (_player.state.playing) setState(() => _osdVisible = false);
    });
  }

  void _toggleOsd() {
    AppLog.player('手势 onTap _toggleOsd visible=$_osdVisible');
    if (_osdVisible) {
      _osdHideTimer?.cancel();
      setState(() => _osdVisible = false);
    } else {
      _pokeOsd();
    }
  }

  void _showSeekFeedback(String text) {
    setState(() => _seekFeedback = text);
    _seekFeedbackTimer?.cancel();
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _seekFeedback = null);
    });
  }

  Future<void> _seekBy(int seconds) async {
    final target = _position + Duration(seconds: seconds);
    final clamped = target < Duration.zero ? Duration.zero : target;
    await _player.seek(clamped);
    _showSeekFeedback(seconds > 0 ? '+${seconds}s' : '${seconds}s');
  }

  Future<void> _setVolumeDelta(double delta) async {
    final v = (_player.state.volume + delta).clamp(0.0, 100.0);
    await _player.setVolume(v);
    _showSeekFeedback('音量 ${v.round()}%');
  }

  // MARK: - 快捷键（桌面）

  Map<SingleActivator, VoidCallback> get _shortcuts => {
        const SingleActivator(LogicalKeyboardKey.space): () => _player.playOrPause(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _seekBy(-10),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _seekBy(10),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _setVolumeDelta(10),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _setVolumeDelta(-10),
        const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
        if (_fullscreen)
          const SingleActivator(LogicalKeyboardKey.escape): _toggleFullscreen,
        ...{
          for (final (i, key) in const [
            (0, LogicalKeyboardKey.digit0),
            (1, LogicalKeyboardKey.digit1),
            (2, LogicalKeyboardKey.digit2),
            (3, LogicalKeyboardKey.digit3),
            (4, LogicalKeyboardKey.digit4),
            (5, LogicalKeyboardKey.digit5),
            (6, LogicalKeyboardKey.digit6),
            (7, LogicalKeyboardKey.digit7),
            (8, LogicalKeyboardKey.digit8),
            (9, LogicalKeyboardKey.digit9),
          ])
            SingleActivator(key): () => _seekToFraction(i / 10),
        },
        const SingleActivator(LogicalKeyboardKey.bracketLeft): () =>
            _stepRate(-0.25),
        const SingleActivator(LogicalKeyboardKey.bracketRight): () =>
            _stepRate(0.25),
      };

  void _seekToFraction(double f) {
    if (_duration.inSeconds <= 0) return;
    _player.seek(Duration(seconds: (f * _duration.inSeconds).toInt()));
  }

  /// 快捷键 [/] 步进倍速（仅当前会话生效，不回写设置中心默认倍速）。
  Future<void> _stepRate(double delta) async {
    final r = (_player.state.rate + delta).clamp(0.5, 3.0);
    await _player.setRate(r);
    _showSeekFeedback('${r.toStringAsFixed(2)}x');
  }

  // MARK: - 数据逻辑（U3 保持不变）

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
      AppLog.player('播放地址为空 ep=$index title=${ep.title}');
      setState(() => _playerError = '该集播放地址为空');
      return;
    }

    AppLog.player('加载 ep=$index title=${ep.title} url=${url.length > 80 ? '${url.substring(0, 80)}…' : url}');

    // 续播位置：显式传入（换源保留）> 历史记录
    Duration? seekTo = resumeAt;
    if (seekTo == null) {
      final history = await _db.progressOf(_detail.drama.id, ep.id);
      if (history != null && history.position > 5) {
        seekTo = Duration(seconds: history.position.toInt());
      }
    }

    try {
      await _player.open(Media(url, httpHeaders: _headersFor(url)));
      if (seekTo != null) await _player.seek(seekTo);
      await _player.play();
      AppLog.player('播放成功 ep=$index seek=${seekTo?.inSeconds ?? 0}s');
    } catch (e) {
      AppLog.player('播放失败 ep=$index err=$e');
      rethrow;
    }
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
    AppLog.player('点击换源按钮');
    // 换源搜索缓存：当前实例无结果时先试全局缓存（按标题 key，5 分钟 TTL）。
    if (_sourceGroups.isEmpty && _otherSeasons.isEmpty && !_sourceSearching) {
      final q = DiscoverEngine.normalize(_detail.drama.title);
      final cached = _SourceSearchCache.read(q);
      if (cached != null) {
        _sourceQuery = q;
        setState(() {
          _sourceGroups = List.of(cached.groups);
          _otherSeasons = List.of(cached.otherSeasons);
        });
        AppLog.player('换源搜索命中缓存 query=$q groups=${cached.groups.length}');
      } else {
        _searchSources();
      }
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
          child: _SourceSheet(
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
        ),
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
            if (mounted) {
              setState(() => _sourceSearching = false);
              // 搜索完成写入缓存（按规范化标题 key）。
              _SourceSearchCache.write(_sourceQuery, _sourceGroups, _otherSeasons);
            }
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
    if (!mounted) {
      _switching = false; // 防残留：未挂载时也复位，避免界面卡「正在切换源…」
      return;
    }
    if (detail == null || detail.episodes.isEmpty) {
      AppLog.player('换源失败：新源无可用集数 drama=${drama.title}');
      setState(() {
        _switching = false;
        _playerError = '换源失败：新源无可用集数';
      });
      return;
    }
    AppLog.player('换源成功：${drama.title} → ${detail.episodes.length} 集');
    setState(() {
      _detail = detail;
      _watchedIds = {};
      // 换源后清实例结果：下次打开换源面板走全局缓存（按新标题 key 读取）。
      _sourceGroups = [];
      _otherSeasons = [];
      _switching = false;
    });
    await _loadWatched();
    final idx = episodeIndex.clamp(0, detail.episodes.length - 1);
    await _loadEpisode(idx, resumeAt: resumeAt);
  }

  // MARK: - 全屏

  bool _fullscreen = false;

  Future<void> _toggleFullscreen() async {
    if (!mounted) return;
    setState(() => _fullscreen = !_fullscreen);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      // macOS 走原生通道（window_manager 0.4.3 toggleFullScreen 在 macOS 14 SIGILL 崩溃，
      // 崩溃栈 WindowManager.setFullScreen+304；原生通道先激活窗口再 toggle 规避）。
      try {
        await _fullscreenChannel
            .invokeMethod('setFullScreen', {'isFullScreen': _fullscreen});
      } catch (e) {
        AppLog.player('全屏切换失败 err=$e');
      }
    } else if (!kIsWeb && _isDesktop) {
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

  static const _fullscreenChannel = MethodChannel('dramacube/fullscreen');

  // MARK: - UI

  @override
  Widget build(BuildContext context) {
    final ep = _detail.episodes[_currentIndex];
    // 电视模式：TV 独立 OSD（焦点引擎 + 大按钮 + 长按 OK 2x）
    if (ref.watch(settingsProvider.select((s) => s.tvMode))) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Video(controller: _controller),
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
            if (_switching)
              ColoredBox(
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
              )
            else
              TvPlayerOsd(
                player: _player,
                controller: _controller,
                title: _detail.drama.title,
                episodeTitle: ep.title,
                currentEpisode: _currentIndex,
                episodeCount: _detail.episodes.length,
                onBack: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/tv');
                  }
                },
                onEpisodes: _openEpisodesSheet,
                onPrev: _currentIndex > 0
                    ? () => _loadEpisode(_currentIndex - 1)
                    : null,
                onNext: _currentIndex < _detail.episodes.length - 1
                    ? () => _loadEpisode(_currentIndex + 1)
                    : null,
              ),
          ],
        ),
      );
    }

    Widget body = Stack(
      fit: StackFit.expand,
      children: [
        // 视频层（氛围模式：虚化当前帧）
        if (_ambience)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Video(controller: _controller),
          )
        else
          Video(controller: _controller),
        // 氛围模式文案层
        if (_ambience)
          Container(
            color: Colors.black45,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _detail.drama.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  '暂停中 · ${ep.title}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        // 手势层（移动分区 / 桌面唤起）——必须在 OSD 之下，否则全屏透明手势层会吞掉按钮点击
        _buildGestureLayer(),
        // 顶部栏（返回 + 标题 + 选集/换源）
        _buildTopBar(ep),
        // 底部毛玻璃 OSD
        _buildBottomOsd(),
        // 加载 / 换源中
        if (_switching)
          ColoredBox(
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
        // 双击快进 / 音量 / 亮度反馈
        _buildFeedbackOverlay(),
      ],
    );

    // 桌面：快捷键（电视模式走焦点引擎，不挂全局快捷键）
    if (_isDesktop && !ref.read(settingsProvider).tvMode) {
      body = CallbackShortcuts(
        bindings: _shortcuts,
        child: Focus(autofocus: true, child: body),
      );
    }

    return Scaffold(backgroundColor: Colors.black, body: body);
  }

  /// 顶部栏（渐变衬底 + 返回 + 标题 + 选集/换源）。
  Widget _buildTopBar(Episode ep) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      // OSD 隐藏时不拦截手势（让单击穿透到手势层唤起）；可见时正常接收按钮点击
      child: IgnorePointer(
        ignoring: !_osdVisible,
        child: AnimatedSlide(
        offset: _osdVisible ? Offset.zero : const Offset(0, -1),
        duration: Motion.durMed,
        curve: Motion.curveEmphasized,
        child: AnimatedOpacity(
          opacity: _osdVisible ? 1 : 0,
          duration: Motion.durFast,
          child: Container(
            padding: EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top + 4,
              left: Spacing.md,
              right: Spacing.md,
              bottom: Spacing.sm,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () {
                    AppLog.player('点击返回按钮 canPop=${context.canPop()}');
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/discover');
                    }
                  },
                ),
                Expanded(
                  child: Text(
                    '${_detail.drama.title} · ${ep.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.grid_view_outlined, color: Colors.white),
                  tooltip: '选集',
                  onPressed: _openEpisodesSheet,
                ),
                IconButton(
                  icon: const Icon(Icons.swap_horiz, color: Colors.white),
                  tooltip: '换源',
                  onPressed: _openSourceSheet,
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  /// 底部毛玻璃 OSD（进度 + 控制按钮）。
  Widget _buildBottomOsd() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      // OSD 隐藏时不拦截手势；可见时正常接收进度条/按钮交互
      child: IgnorePointer(
        ignoring: !_osdVisible,
        child: AnimatedSlide(
        offset: _osdVisible ? Offset.zero : const Offset(0, 1),
        duration: Motion.durMed,
        curve: Motion.curveEmphasized,
        child: AnimatedOpacity(
          opacity: _osdVisible ? 1 : 0,
          duration: Motion.durFast,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
              child: GlassPanel(
                blur: 24,
                tint: const Color(0x59140E0B),
                borderRadius: BorderRadius.circular(Radii.lg),
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 6),
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
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 11)),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 2,
                                    thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 6),
                                    activeTrackColor: Brand.heroPink,
                                    thumbColor: Colors.white,
                                    inactiveTrackColor: Colors.white24,
                                  ),
                                  child: Slider(
                                    value: dur.inSeconds > 0
                                        ? (pos.inSeconds / dur.inSeconds)
                                            .clamp(0.0, 1.0)
                                        : 0,
                                    onChanged: (v) {
                                      _pokeOsd();
                                      _player.seek(Duration(
                                          seconds: (v * dur.inSeconds).toInt()));
                                    },
                                    onChangeStart: (_) => _osdHideTimer?.cancel(),
                                    onChangeEnd: (_) => _pokeOsd(),
                                  ),
                                ),
                              ),
                              Text('-${_fmt(dur - pos)}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 11)),
                            ],
                          );
                        },
                      ),
                    ),
                    // 控制行
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
                            icon: Icon(
                                snap.data == true ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                                size: 32),
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
                        // 音量（桌面滑杆弹层 / 移动菜单）
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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: Spacing.sm),
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
                        // 倍速（仅当前会话生效，不回写设置中心默认倍速）
                        StreamBuilder<double>(
                          stream: _player.stream.rate,
                          builder: (context, snap) => PopupMenuButton<double>(
                            initialValue: snap.data ?? 1.0,
                            onSelected: (rate) => _player.setRate(rate),
                            itemBuilder: (_) => [
                              for (final r in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0])
                                PopupMenuItem(value: r, child: Text('${r}x')),
                            ],
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: Spacing.sm),
                              child: Text('${snap.data ?? 1.0}x',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13)),
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
            ),
          ),
        ),
        ),
      ),
    );
  }

  /// 手势层 —— 移动端三分区（双击快进退 + 边缘滑），桌面端 hover 唤起。
  Widget _buildGestureLayer() {
    if (_isMobile) {
      return Positioned.fill(
        child: Row(
          children: [
            // 左区：双击 -10s；左边缘竖直拖 = 亮度
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggleOsd,
                onDoubleTap: () => _seekBy(-10),
                onVerticalDragStart: (d) => _startBrightnessDrag(d.localPosition.dy),
                onVerticalDragUpdate: (d) => _updateBrightnessDrag(d.localPosition.dy),
                onVerticalDragEnd: (_) => _endBrightnessDrag(),
                child: const SizedBox.expand(),
              ),
            ),
            // 中区：双击全屏
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggleOsd,
                onDoubleTap: _toggleFullscreen,
                child: const SizedBox.expand(),
              ),
            ),
            // 右区：双击 +10s；右边缘竖直拖 = 音量
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggleOsd,
                onDoubleTap: () => _seekBy(10),
                onVerticalDragStart: (d) =>
                    _startVolumeDrag(d.localPosition.dy),
                onVerticalDragUpdate: (d) => _updateVolumeDrag(d.localPosition.dy),
                onVerticalDragEnd: (_) => _endVolumeDrag(),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      );
    }

    // 桌面：鼠标移动/点击唤起 OSD
    return Positioned.fill(
      child: MouseRegion(
        onHover: (_) => _pokeOsd(),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _toggleOsd,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  // MARK: - 移动端边缘滑（左亮度 / 右音量）

  void _startBrightnessDrag(double startY) async {
    double current = 1;
    try {
      current = await ScreenBrightness().application;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _brightnessDragStart = startY;
      _brightnessDragValue = current;
      _brightnessIndicator = current;
    });
  }

  void _updateBrightnessDrag(double y) {
    final delta = (_brightnessDragStart - y) / 400; // 上滑增亮
    final v = (_brightnessDragValue + delta).clamp(0.05, 1.0);
    try {
      ScreenBrightness().setApplicationScreenBrightness(v);
    } catch (_) {}
    setState(() => _brightnessIndicator = v);
  }

  void _endBrightnessDrag() async {
    try {
      await ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {}
    if (mounted) setState(() => _brightnessIndicator = null);
  }

  void _startVolumeDrag(double startY) {
    setState(() {
      _volumeDragStart = startY;
      _volumeDragValue = _player.state.volume;
      _volumeIndicator = _player.state.volume;
    });
  }

  void _updateVolumeDrag(double y) async {
    final delta = (_volumeDragStart - y) / 3; // 上滑增音
    final v = (_volumeDragValue + delta).clamp(0.0, 100.0);
    await _player.setVolume(v);
    if (mounted) setState(() => _volumeIndicator = v);
  }

  void _endVolumeDrag() {
    if (mounted) setState(() => _volumeIndicator = null);
  }

  /// 中央反馈浮层（快进退 / 音量 / 亮度）。
  Widget _buildFeedbackOverlay() {
    final indicators = <Widget>[];

    if (_seekFeedback != null) {
      indicators.add(_FeedbackChip(
        icon: _seekFeedback!.startsWith('+')
            ? Icons.fast_forward_rounded
            : Icons.fast_rewind_rounded,
        label: _seekFeedback!,
      ));
    }
    if (_volumeIndicator != null) {
      indicators.add(_FeedbackChip(
        icon: _volumeIndicator! == 0
            ? Icons.volume_off_rounded
            : _volumeIndicator! < 50
                ? Icons.volume_down_rounded
                : Icons.volume_up_rounded,
        label: '音量 ${_volumeIndicator!.round()}%',
        progress: _volumeIndicator! / 100,
      ));
    }
    if (_brightnessIndicator != null) {
      indicators.add(_FeedbackChip(
        icon: _brightnessIndicator! < 0.3
            ? Icons.brightness_low_rounded
            : Icons.brightness_high_rounded,
        label: '亮度 ${(_brightnessIndicator! * 100).round()}%',
        progress: _brightnessIndicator!,
      ));
    }

    if (indicators.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: indicators.length == 1
            ? indicators.first
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: indicators,
              ),
      ),
    );
  }

  // MARK: - 选集面板（居中对话框）

  Future<void> _openEpisodesSheet() async {
    AppLog.player('点击选集按钮');
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
          child: _EpisodesSheet(
            detail: _detail,
            currentIndex: _currentIndex,
            watchedIds: _watchedIds,
            onPlay: (i) {
              Navigator.pop(ctx);
              _loadEpisode(i);
            },
          ),
        ),
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

class _FeedbackChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final double? progress;

  const _FeedbackChip({required this.icon, required this.label, this.progress});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      blur: 18,
      tint: const Color(0x66140E0B),
      borderRadius: BorderRadius.circular(Radii.lg),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 30),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
          if (progress != null) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: 90,
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation(Brand.heroPink),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// window_manager 全屏封装已内联（桌面端 guard 后调用）。

class _SiteGroup {
  final String siteName;
  final List<Drama> results;
  _SiteGroup(this.siteName, this.results);
}

/// 换源搜索结果缓存（按规范化标题 key，TTL 5 分钟）。
/// 避免同部剧反复点「换源」时全量重搜——结果短时稳定，过期后自然重搜。
class _SourceSearchCache {
  final List<_SiteGroup> groups;
  final List<Drama> otherSeasons;
  final DateTime at;
  _SourceSearchCache(this.groups, this.otherSeasons) : at = DateTime.now();

  bool get fresh => DateTime.now().difference(at) < const Duration(minutes: 5);

  static final Map<String, _SourceSearchCache> _map = {};

  static _SourceSearchCache? read(String query) {
    final c = _map[query];
    if (c == null) return null;
    if (!c.fresh) {
      _map.remove(query);
      return null;
    }
    return c;
  }

  static void write(String query, List<_SiteGroup> groups, List<Drama> seasons) {
    // 防内存膨胀：最多保留 20 条，超量清最旧。
    if (_map.length >= 20) {
      final oldest = _map.entries.reduce((a, b) => a.value.at.isBefore(b.value.at) ? a : b);
      _map.remove(oldest.key);
    }
    _map[query] = _SourceSearchCache(List.of(groups), List.of(seasons));
  }
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
    return Container(
      decoration: BoxDecoration(
        color: Brand.background(Theme.of(context).brightness),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
            Row(
              children: [
                Text('换源播放', style: Theme.of(context).textTheme.titleMedium),
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
                    fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                          fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              ),
          ],
        ),
    );
  }
}
