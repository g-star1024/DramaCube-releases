import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'tv_focus.dart';
import 'tv_theme.dart';

/// TV 播放器 OSD —— 大按钮 + 焦点 scrubber + 长按 OK 2x。
///
/// - scrubber 焦点模型：聚焦时 ←/→ 快进退（默认步长 10s）
/// - 播放键双击（OK 连按）= 2 倍速
/// - 自动隐藏 5s（遥控无操作）
class TvPlayerOsd extends StatefulWidget {
  final Player player;
  final VideoController controller;
  final String title;
  final String episodeTitle;
  final int currentEpisode;
  final int episodeCount;
  final VoidCallback onBack;
  final VoidCallback onEpisodes;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const TvPlayerOsd({
    super.key,
    required this.player,
    required this.controller,
    required this.title,
    required this.episodeTitle,
    required this.currentEpisode,
    required this.episodeCount,
    required this.onBack,
    required this.onEpisodes,
    this.onPrev,
    this.onNext,
  });

  @override
  State<TvPlayerOsd> createState() => _TvPlayerOsdState();
}

class _TvPlayerOsdState extends State<TvPlayerOsd> {
  bool _scrubberFocused = false;

  String _fmt(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  void _seekBy(int seconds) {
    final pos = widget.player.state.position;
    final dur = widget.player.state.duration;
    final target = pos + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (dur.inSeconds > 0 && target > dur ? dur : target);
    widget.player.seek(clamped);
  }

  void _setRate(double r) => widget.player.setRate(r);

  void _togglePlay() => widget.player.playOrPause();

  @override
  Widget build(BuildContext context) {
    final pos = widget.player.state.position;
    final dur = widget.player.state.duration;
    final progress = dur.inSeconds > 0
        ? (pos.inSeconds / dur.inSeconds).clamp(0.0, 1.0)
        : 0.0;

    return IgnorePointer(
      ignoring: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 顶部信息条
          Positioned(
            top: TvSafeArea.top / 3,
            left: TvSafeArea.left,
            right: TvSafeArea.right,
            child: Row(
              children: [
                Text(
                  '${widget.title} · ${widget.episodeTitle}',
                  style: const TextStyle(
                      color: TvColors.onSurface, fontSize: TvText.body),
                ),
                const Spacer(),
                Text(
                  '第 ${widget.currentEpisode + 1}/${widget.episodeCount} 集',
                  style: const TextStyle(
                      color: TvColors.muted, fontSize: TvText.caption),
                ),
              ],
            ),
          ),
          // 底部控制区（scrubber + 大按钮）
          Positioned(
            left: TvSafeArea.left,
            right: TvSafeArea.right,
            bottom: TvSafeArea.bottom / 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 时间行
                Row(
                  children: [
                    Text(_fmt(pos),
                        style: const TextStyle(
                            color: TvColors.onSurface,
                            fontSize: TvText.caption)),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        // 焦点 scrubber：聚焦后 ←/→ 快进退
                        child: TvFocusable(
                          onFocusChange: (v) =>
                              setState(() => _scrubberFocused = v),
                          onPressed: () {},
                            child: Focus(
                              canRequestFocus: true,
                              onKeyEvent: (node, event) {
                                if (event is KeyDownEvent &&
                                    event.logicalKey ==
                                        LogicalKeyboardKey.arrowLeft) {
                                  _seekBy(-10);
                                  return KeyEventResult.handled;
                                }
                                if (event is KeyDownEvent &&
                                    event.logicalKey ==
                                        LogicalKeyboardKey.arrowRight) {
                                  _seekBy(10);
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: _scrubberFocused ? 6 : 4,
                                activeTrackColor: TvColors.focus,
                                inactiveTrackColor:
                                    TvColors.onSurface.withValues(alpha: 0.3),
                                thumbColor: TvColors.focus,
                                overlayColor: TvColors.focusGlow,
                              ),
                              child: Slider(
                                value: progress,
                                onChanged: (v) => widget.player.seek(Duration(
                                    seconds: (v * dur.inSeconds).toInt())),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(_fmt(dur - pos),
                        style: const TextStyle(
                            color: TvColors.onSurface,
                            fontSize: TvText.caption)),
                  ],
                ),
                const SizedBox(height: 12),
                // 大按钮行
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _OsdButton(
                      icon: Icons.skip_previous,
                      enabled: widget.onPrev != null,
                      onPressed: widget.onPrev,
                    ),
                    const SizedBox(width: 24),
                    StreamBuilder<bool>(
                      stream: widget.player.stream.playing,
                      builder: (context, snap) => _OsdButton(
                        icon: snap.data == true
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        large: true,
                        // 双击 OK = 2x
                        onDoubleTap: () => _setRate(
                            widget.player.state.rate == 2.0 ? 1.0 : 2.0),
                        onPressed: _togglePlay,
                      ),
                    ),
                    const SizedBox(width: 24),
                    _OsdButton(
                      icon: Icons.skip_next,
                      enabled: widget.onNext != null,
                      onPressed: widget.onNext,
                    ),
                    const SizedBox(width: 24),
                    _OsdButton(
                      icon: Icons.grid_view_rounded,
                      onPressed: widget.onEpisodes,
                    ),
                    const SizedBox(width: 24),
                    _OsdButton(
                      icon: Icons.arrow_back,
                      onPressed: widget.onBack,
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

/// OSD 大按钮（焦点可达 + 辉光 + 双击支持）。
class _OsdButton extends StatefulWidget {
  final IconData icon;
  final bool large;
  final bool enabled;
  final VoidCallback? onPressed;
  final VoidCallback? onDoubleTap;

  const _OsdButton({
    required this.icon,
    this.large = false,
    this.enabled = true,
    this.onPressed,
    this.onDoubleTap,
  });

  @override
  State<_OsdButton> createState() => _OsdButtonState();
}

class _OsdButtonState extends State<_OsdButton> {
  @override
  Widget build(BuildContext context) {
    final size = widget.large ? 76.0 : 56.0;
    return Opacity(
      opacity: widget.enabled ? 1 : 0.4,
      child: TvFocusable(
        onPressed: widget.enabled ? widget.onPressed : null,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: TvColors.surfaceHi,
            shape: BoxShape.circle,
          ),
          child: Icon(widget.icon, color: TvColors.onSurface, size: size * 0.5),
        ),
      ),
    );
  }
}
