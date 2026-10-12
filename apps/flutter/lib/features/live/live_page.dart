import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/models/models.dart';
import '../../core/widgets/health_badge.dart';
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
    final isWide = MediaQuery.of(context).size.width >= 720;
    return Scaffold(
      appBar: AppBar(
        title: const Text('电视直播'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: '切换直播源',
            onPressed: _showSourceSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新频道',
            onPressed: () => ref.read(liveManagerProvider.notifier).refresh(),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '直播源管理',
            onPressed: () => _showSourceManager(context),
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
                  : isWide
                      ? _buildWideLayout(live)
                      : _buildNarrowLayout(live),
    );
  }

  /// 宽屏（桌面/平板）：左右分栏。
  Widget _buildWideLayout(LiveState live) {
    return Row(
      children: [
        SizedBox(
          width: 280,
          child: _ChannelList(
            grouped: live.grouped,
            currentChannel: _currentChannel,
            onSelect: (ch) => setState(() => _currentChannel = ch),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _currentChannel == null
              ? _emptyState(icon: Icons.play_circle_outline, text: '选择频道开始播放')
              : _LivePlayer(key: ValueKey(_currentChannel!.id), channel: _currentChannel!),
        ),
      ],
    );
  }

  /// 窄屏（手机）：频道列表全屏，点频道进全屏播放页。
  Widget _buildNarrowLayout(LiveState live) {
    return _ChannelList(
      grouped: live.grouped,
      currentChannel: null,
      onSelect: (ch) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _LivePlayerFullPage(channel: ch),
        ));
      },
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
    showDialog(
      context: context,
      builder: (_) => const _SourceManagerDialog(),
    );
  }

  /// 右上角直播源切换弹层（延迟排序 + 失效标记 + 一键测试）。
  void _showSourceSheet() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
          child: _LiveSourceSheet(
            onSelected: () => setState(() => _currentChannel = null),
          ),
        ),
      ),
    );
  }
}

/// 直播源切换弹层。
class _LiveSourceSheet extends ConsumerStatefulWidget {
  final VoidCallback onSelected;
  const _LiveSourceSheet({required this.onSelected});

  @override
  ConsumerState<_LiveSourceSheet> createState() => _LiveSourceSheetState();
}

class _LiveSourceSheetState extends ConsumerState<_LiveSourceSheet> {
  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveManagerProvider);
    final sorted = live.sortedEnabledSources;
    return SafeArea(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 520),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('切换直播源', style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: () => ref.read(liveManagerProvider.notifier).testAllSources(),
                  icon: const Icon(Icons.speed, size: 18),
                  label: const Text('一键测试'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (sorted.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('暂无可用直播源', style: TextStyle(color: Colors.grey))),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: Icon(
                        live.currentSourceId.isEmpty
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: live.currentSourceId.isEmpty
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      title: const Text('全部源'),
                      subtitle: Text('合并 ${live.channels.length} 个频道',
                          style: const TextStyle(fontSize: 11)),
                      onTap: () {
                        ref.read(liveManagerProvider.notifier).setCurrentSource('');
                        widget.onSelected();
                        Navigator.pop(context);
                      },
                    ),
                    for (final source in sorted)
                      ListTile(
                        leading: Icon(
                          live.currentSourceId == source.id
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: live.currentSourceId == source.id
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                        ),
                        title: Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(source.url, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11)),
                        trailing: HealthBadge(
                          tested: live.health[source.id] != null,
                          ok: live.health[source.id]?.ok ?? false,
                          latencyMs: live.health[source.id]?.latencyMs,
                        ),
                        onTap: () {
                          ref.read(liveManagerProvider.notifier).setCurrentSource(source.id);
                          widget.onSelected();
                          Navigator.pop(context);
                        },
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '一键测试会拉取各源订阅地址计时，失效源自动禁用；直播内容按所选源展示。',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
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

/// 直播播放器（media_kit，嵌入宽屏布局）。
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

/// 直播全屏播放页（窄屏手机用，带返回按钮）。
class _LivePlayerFullPage extends StatefulWidget {
  final LiveChannel channel;
  const _LivePlayerFullPage({required this.channel});

  @override
  State<_LivePlayerFullPage> createState() => _LivePlayerFullPageState();
}

class _LivePlayerFullPageState extends State<_LivePlayerFullPage> {
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.channel.name),
      ),
      body: Column(
        children: [
          Expanded(child: Video(controller: _controller)),
          SafeArea(
            child: Container(
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  StreamBuilder<bool>(
                    stream: _player.stream.playing,
                    builder: (context, snap) => IconButton(
                      icon: Icon(snap.data == true ? Icons.pause : Icons.play_arrow,
                          color: Colors.white, size: 32),
                      onPressed: () => _player.playOrPause(),
                    ),
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

/// 直播源管理居中对话框（新增表单 + 已有源列表，行内编辑/开关/删除）。
class _SourceManagerDialog extends ConsumerStatefulWidget {
  const _SourceManagerDialog();

  @override
  ConsumerState<_SourceManagerDialog> createState() => _SourceManagerDialogState();
}

class _SourceManagerDialogState extends ConsumerState<_SourceManagerDialog> {
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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('直播源管理', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                ],
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: '编辑',
                            onPressed: () => _editSource(source),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            tooltip: '删除',
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

  /// 编辑弹窗：字段预填，保存走 updateSource。
  void _editSource(LiveSource source) {
    showDialog(
      context: context,
      builder: (_) => _SourceEditDialog(source: source),
    );
  }
}

/// 直播源编辑对话框（与新增同款表单，字段预填，保存更新）。
class _SourceEditDialog extends ConsumerStatefulWidget {
  final LiveSource source;
  const _SourceEditDialog({required this.source});

  @override
  ConsumerState<_SourceEditDialog> createState() => _SourceEditDialogState();
}

class _SourceEditDialogState extends ConsumerState<_SourceEditDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _uaCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.source.name);
    _urlCtrl = TextEditingController(text: widget.source.url);
    _uaCtrl = TextEditingController(text: widget.source.userAgent ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _uaCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _urlCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (url.isEmpty) return;
    await ref.read(liveManagerProvider.notifier).updateSource(
          widget.source.id,
          name: name.isEmpty ? url : name,
          url: url,
          userAgent: _uaCtrl.text.trim().isEmpty ? null : _uaCtrl.text.trim(),
        );
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('直播源已更新')));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('编辑直播源'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: '名称',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _urlCtrl,
                decoration: InputDecoration(
                  labelText: '直播源地址（m3u / txt）',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _uaCtrl,
                decoration: InputDecoration(
                  labelText: 'User-Agent（可选）',
                  hintText: '部分源要求指定 UA 才能拉取',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
