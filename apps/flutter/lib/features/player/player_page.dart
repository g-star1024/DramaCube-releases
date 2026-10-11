import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/models/models.dart';

/// 播放器页（media_kit libmpv 内核，对齐 macOS 版 mpv 体验）。
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
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.startIndex.clamp(0, widget.detail.episodes.length - 1);
    _loadEpisode(_currentIndex);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadEpisode(int index) async {
    if (index < 0 || index >= widget.detail.episodes.length) return;
    setState(() => _currentIndex = index);
    final ep = widget.detail.episodes[index];
    final url = ep.playURL;
    if (url == null || url.isEmpty) return;
    // m3u8 直连（libmpv 内置 FFmpeg，不走网关代理——对齐 macOS 版 mpv 直连方案）
    await _player.open(Media(url, httpHeaders: {
      if (url.contains('.m3u8')) ...{
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15',
        'Referer': '${Uri.parse(url).scheme}://${Uri.parse(url).host}/',
      },
    }));
    await _player.play();
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
          // 控制条（简化版，M1 后续补齐倍速/选集/弹幕等）
          Container(
            color: Colors.black87,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                Text('第${ep.index}集 / 共${widget.detail.episodes.length}集',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
