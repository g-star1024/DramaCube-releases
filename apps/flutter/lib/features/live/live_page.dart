import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/models/models.dart';
import 'live_manager.dart';

/// 电视直播页：左侧分组频道列表 + 右侧播放器（对齐 macOS 版 LiveView）。
class LivePage extends ConsumerStatefulWidget {
  const LivePage({super.key});

  @override
  ConsumerState<LivePage> createState() => _LivePageState();
}

class _LivePageState extends ConsumerState<LivePage> {
  LiveChannel? _currentChannel;

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveManagerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('电视直播'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '直播源管理',
            onPressed: () => _showSourceManager(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新频道',
            onPressed: () => ref.read(liveManagerProvider.notifier).refresh(),
          ),
        ],
      ),
      body: live.sources.isEmpty
          ? _emptyState(
              icon: Icons.tv_off_outlined,
              text: '暂无直播源',
              hint: '点击右上角设置添加 m3u / txt 直播源',
              action: FilledButton.icon(
                onPressed: () => _showSourceManager(context),
                icon: const Icon(Icons.add),
                label: const Text('添加直播源'),
              ),
            )
          : live.isLoading && live.channels.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : live.channels.isEmpty
                  ? _emptyState(
                      icon: Icons.tv_outlined,
                      text: '暂无频道',
                      hint: live.error ?? '直播源已添加但未解析到频道，试试刷新',
                    )
                  : Row(
                      children: [
                        // 频道列表
                        SizedBox(
                          width: 280,
                          child: _ChannelList(
                            grouped: live.grouped,
                            currentChannel: _currentChannel,
                            onSelect: (ch) => setState(() => _currentChannel = ch),
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        // 播放器
                        Expanded(
                          child: _currentChannel == null
                              ? _emptyState(
                                  icon: Icons.play_circle_outline,
                                  text: '选择频道开始播放',
                                )
                              : _LivePlayer(key: ValueKey(_currentChannel!.id), channel: _currentChannel!),
                        ),
                      ],
                    ),
    );
  }

  Widget _emptyState({required IconData icon, required String text, String? hint, Widget? action}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(text, style: const TextStyle(color: Colors.grey, fontSize: 16)),
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(hint, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
          if (action != null) ...[
            const SizedBox(height: 24),
            action,
          ],
        ],
      ),
    );
  }

  void _showSourceManager(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SourceManagerSheet(),
    );
  }
}

/// 频道列表（分组折叠）。
class _ChannelList extends StatelessWidget {
  final Map<String, List<LiveChannel>> grouped;
  final LiveChannel? currentChannel;
  final ValueChanged<LiveChannel> onSelect;

  const _ChannelList({required this.grouped, required this.currentChannel, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final groups = grouped.keys.toList();
    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, i) {
        final group = groups[i];
        final channels = grouped[group]!;
        return ExpansionTile(
          title: Text('$group（${channels.length}）', style: const TextStyle(fontSize: 14)),
          initiallyExpanded: i == 0,
          children: [
            for (final ch in channels)
              ListTile(
                dense: true,
                leading: ch.logo != null
                    ? Image.network(ch.logo!, width: 32, height: 32, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.tv, size: 24))
                    : const Icon(Icons.tv, size: 24),
                title: Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                selected: currentChannel?.id == ch.id,
                selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
                onTap: () => onSelect(ch),
              ),
          ],
        );
      },
    );
  }
}

/// 直播播放器（media_kit）。
class _LivePlayer extends StatefulWidget {
  final LiveChannel channel;
  const _LivePlayer({super.key, required this.channel});

  @override
  State<_LivePlayer> createState() => _LivePlayerState();
}

class _LivePlayerState extends State<_LivePlayer> {
  late final _player = Player();
  late final _controller = VideoController(_player);

  @override
  void initState() {
    super.initState();
    _player.open(Media(widget.channel.url, httpHeaders: {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15',
    }));
    _player.play();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: Video(controller: _controller)),
        Container(
          color: Colors.black87,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.channel.name,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              StreamBuilder<bool>(
                stream: _player.stream.playing,
                builder: (context, snap) => IconButton(
                  icon: Icon(snap.data == true ? Icons.pause : Icons.play_arrow, color: Colors.white),
                  onPressed: () => _player.playOrPause(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 直播源管理底部弹窗。
class _SourceManagerSheet extends ConsumerStatefulWidget {
  const _SourceManagerSheet();

  @override
  ConsumerState<_SourceManagerSheet> createState() => _SourceManagerSheetState();
}

class _SourceManagerSheetState extends ConsumerState<_SourceManagerSheet> {
  final _urlCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() => _adding = true);
    await ref.read(liveManagerProvider.notifier).addSource(
          url,
          name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        );
    if (!mounted) return;
    setState(() => _adding = false);
    _urlCtrl.clear();
    _nameCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveManagerProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('直播源管理', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: '名称（可选）',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlCtrl,
                    decoration: InputDecoration(
                      labelText: '直播源地址（m3u / txt）',
                      hintText: 'https://…/iptv.m3u',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _adding ? null : _add,
                  child: _adding
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('添加'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final source in live.sources)
                    ListTile(
                      leading: const Icon(Icons.rss_feed),
                      title: Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(source.url, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: source.enabled,
                            onChanged: (v) => ref.read(liveManagerProvider.notifier).setEnabled(source.id, v),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => ref.read(liveManagerProvider.notifier).removeSource(source.id),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
