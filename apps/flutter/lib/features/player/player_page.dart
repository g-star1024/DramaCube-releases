import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/db/database.dart';
import '../../core/models/models.dart';

/// 播放器页（media_kit libmpv 内核，对齐 macOS 版 mpv 体验）。
///
/// 自动保存播放进度到 drift，再次打开同一集时续播。
class PlayerPage extends StatefulWidget {
  final DramaDetail detail;
  final int startIndex;

  const PlayerPage({super.key, required this.detail, this.startIndex = 0});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final _player = Player();
  late final _controller = VideoController(_player);
  late final _db = AppDatabase();
  late int _currentIndex;
  Timer? _progressTimer;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.startIndex.clamp(0, widget.detail.episodes.length - 1);
    _positionSub = _player.stream.position.listen((d) => _position = d);
    _durationSub = _player.stream.duration.listen((d) => _duration = d);
    _loadEpisode(_currentIndex);
    // 每 5 秒保存一次进度
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _saveProgress(); // 退出前最后存一次
    _player.dispose();
    _db.close();
    super.dispose();
  }

  Future<void> _loadEpisode(int index) async {
    if (index < 0 || index >= widget.detail.episodes.length) return;
    // 切集前保存当前进度
    if (index != _currentIndex) await _saveProgress();
    setState(() => _currentIndex = index);
    final ep = widget.detail.episodes[index];
    final url = ep.playURL;
    if (url == null || url.isEmpty) return;

    // 查续播位置
    final history = await _db.progressOf(widget.detail.drama.id, ep.id);
    final seekTo = history != null && history.position > 5
        ? Duration(seconds: history.position.toInt())
        : null;

    // m3u8 直连（libmpv 内置 FFmpeg，不走网关代理——对齐 macOS 版 mpv 直连方案）
    await _player.open(Media(url, httpHeaders: {
      if (url.contains('.m3u8')) ...{
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15',
        'Referer': '${Uri.parse(url).scheme}://${Uri.parse(url).host}/',
      },
    }));
    if (seekTo != null) {
      await _player.seek(seekTo);
    }
    await _player.play();
  }

  Future<void> _saveProgress() async {
    if (_position.inSeconds < 5) return; // 开头不存
    final ep = widget.detail.episodes[_currentIndex];
    await _db.saveProgress(
      dramaId: widget.detail.drama.id,
      episodeId: ep.id,
      title: widget.detail.drama.title,
      episodeTitle: ep.title,
      coverURL: widget.detail.drama.coverURL,
      position: _position.inSeconds.toDouble(),
      duration: _duration.inSeconds.toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ep = widget.detail.episodes[_currentIndex];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${widget.detail.drama.title} 第${ep.index}集'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Video(controller: _controller),
          ),
          // 进度条
          StreamBuilder<Duration>(
            stream: _player.stream.position,
            builder: (context, posSnap) => StreamBuilder<Duration>(
              stream: _player.stream.duration,
              builder: (context, durSnap) {
                final pos = posSnap.data ?? Duration.zero;
                final dur = durSnap.data ?? Duration.zero;
                return SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: dur.inSeconds > 0 ? pos.inSeconds / dur.inSeconds : 0,
                    onChanged: (v) => _player.seek(Duration(seconds: (v * dur.inSeconds).toInt())),
                  ),
                );
              },
            ),
          ),
          // 控制条
          SafeArea(
            child: Container(
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous, color: Colors.white),
                    onPressed: _currentIndex > 0 ? () => _loadEpisode(_currentIndex - 1) : null,
                  ),
                  StreamBuilder<bool>(
                    stream: _player.stream.playing,
                    builder: (context, snap) => IconButton(
                      icon: Icon(snap.data == true ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 32),
                      onPressed: () => _player.playOrPause(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, color: Colors.white),
                    onPressed: _currentIndex < widget.detail.episodes.length - 1
                        ? () => _loadEpisode(_currentIndex + 1)
                        : null,
                  ),
                  const Spacer(),
                  // 倍速
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
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('${snap.data ?? 1.0}x',
                            style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('第${ep.index}集 / 共${widget.detail.episodes.length}集',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
