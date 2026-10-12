import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/models/models.dart';
import '../../core/widgets/health_badge.dart';
import 'nas_cover_generator.dart';
import 'nas_manager.dart';

/// NAS 资源库页：库选择 + 目录导航 + 视频播放（对齐 macOS 版 NASBrowseView）。
class NASPage extends ConsumerStatefulWidget {
  const NASPage({super.key});

  @override
  ConsumerState<NASPage> createState() => _NASPageState();
}

class _NASPageState extends ConsumerState<NASPage> {
  NASLibrary? _currentLib;
  String _currentPath = '';
  List<NASEntry> _entries = [];
  bool _loading = false;
  String? _error;
  /// 懒渲染：首屏只渲染前 30 个视频卡片，滚近底部追加（对齐 Swift visibleCount/pageSize）。
  int _visibleCount = 30;
  static const _pageSize = 30;
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _browse(NASLibrary lib, String path) async {
    setState(() {
      _currentLib = lib;
      _currentPath = path;
      _loading = true;
      _error = null;
      _visibleCount = _pageSize;
    });
    try {
      final entries = await ref.read(nasManagerProvider.notifier).listEntries(lib, path);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = [];
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _navigateTo(NASEntry entry) {
    final newPath = _currentPath.isEmpty ? entry.name : '$_currentPath/${entry.name}';
    if (entry.isDir) {
      _browse(_currentLib!, newPath);
    } else if (NASManager.isVideo(entry.name)) {
      _playVideo(newPath, entry.name);
    }
  }

  void _playVideo(String path, String title) {
    final lib = _currentLib!;
    final nas = ref.read(nasManagerProvider.notifier);
    final url = nas.fileURL(lib, path);
    final headers = nas.playHeaders(lib);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _NASPlayerPage(title: title, url: url, headers: headers),
    ));
  }

  void _goUp() {
    if (_currentPath.isEmpty) {
      setState(() => _currentLib = null);
      return;
    }
    final parts = _currentPath.split('/');
    parts.removeLast();
    _browse(_currentLib!, parts.join('/'));
  }

  @override
  Widget build(BuildContext context) {
    final nas = ref.watch(nasManagerProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentLib == null
            ? '资源库'
            : _currentPath.isEmpty
                ? _currentLib!.name
                : _currentPath.split('/').last),
        leading: _currentLib != null
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goUp)
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: '切换资源库',
            onPressed: _showLibrarySheet,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '资源库管理',
            onPressed: () => _showLibraryManager(context),
          ),
        ],
      ),
      body: _buildBody(nas),
    );
  }

  Widget _buildBody(NASState nas) {
    // 库选择
    if (_currentLib == null) {
      if (nas.libraries.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.dns_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('暂无资源库', style: TextStyle(color: Colors.grey, fontSize: 16)),
              const SizedBox(height: 8),
              const Text('添加 WebDAV 或本机挂载目录', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _showLibraryManager(context),
                icon: const Icon(Icons.add),
                label: const Text('添加资源库'),
              ),
            ],
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final lib in nas.enabledLibraries)
            Card(
              child: ListTile(
                leading: Icon(lib.type == 'webdav' ? Icons.cloud_outlined : Icons.folder_outlined),
                title: Text(lib.name),
                subtitle: Text(lib.baseURL, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _browse(lib, ''),
              ),
            ),
        ],
      );
    }

    // 目录浏览
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('加载失败', style: TextStyle(color: Colors.grey[700], fontSize: 16)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error!, style: const TextStyle(color: Colors.grey, fontSize: 12),
                  textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => _browse(_currentLib!, _currentPath), child: const Text('重试')),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(child: Text('空目录', style: TextStyle(color: Colors.grey)));
    }
    // 目录在前（紧凑列表），视频在后（图文卡片网格，对齐 Swift NASBrowseView）。
    final dirs = _entries.where((e) => e.isDir).toList();
    final videos = _entries.where((e) => !e.isDir && NASManager.isVideo(e.name)).toList();
    final visible = videos.take(_visibleCount).toList();
    final lib = _currentLib!;

    return CustomScrollView(
      controller: _scrollCtrl,
      slivers: [
        if (_currentPath.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(_currentPath, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ),
          ),
        // 目录区：紧凑列表（点击进入子目录）。
        if (dirs.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Card(
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.folder, color: Colors.amber),
                    title: Text(dirs[i].name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _navigateTo(dirs[i]),
                  ),
                ),
                childCount: dirs.length,
              ),
            ),
          ),
        // 视频区：自适应网格图文卡片（2:3 封面 + 标题，对齐 Swift NASCard）。
        if (visible.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.52, // 2:3 封面 + 标题行的整体高宽比
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _NASVideoCard(
                  entry: visible[i],
                  lib: lib,
                  parentPath: _currentPath,
                  onTap: () => _navigateTo(visible[i]),
                ),
                childCount: visible.length,
              ),
            ),
          ),
        // 懒加载哨兵：滚近底部追加渲染（对齐 Swift loadMore）。
        SliverToBoxAdapter(
          child: _visibleCount < videos.length
              ? const Padding(
                  padding: EdgeInsets.only(bottom: 24),
                  child: Center(child: Text('加载更多…', style: TextStyle(fontSize: 12, color: Colors.grey))),
                )
              : videos.length > _pageSize
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Center(
                        child: Text('共 ${videos.length} 个视频',
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ),
                    )
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    // 滚近底部（或内容不足一屏）时追加渲染下一批，对齐 Swift 几何监听语义。
    _scrollCtrl.addListener(() {
      if (!_scrollCtrl.hasClients) return;
      final pos = _scrollCtrl.position;
      if (pos.pixels >= pos.maxScrollExtent - 400 || pos.maxScrollExtent <= 400) {
        final total = _entries.where((e) => !e.isDir && NASManager.isVideo(e.name)).length;
        if (_visibleCount < total && mounted) {
          setState(() => _visibleCount = (_visibleCount + _pageSize).clamp(0, total));
        }
      }
    });
  }

  void _showLibraryManager(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _LibraryManagerDialog(),
    );
  }

  /// 右上角资源库切换弹层（连通性徽标 + 一键测试）。
  void _showLibrarySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _LibrarySwitchSheet(),
    );
  }
}

/// 资源库切换弹层。
class _LibrarySwitchSheet extends ConsumerWidget {
  const _LibrarySwitchSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nas = ref.watch(nasManagerProvider);
    final libs = nas.enabledLibraries;
    return SafeArea(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 480),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('切换资源库', style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: () => ref.read(nasManagerProvider.notifier).testAllLibraries(),
                  icon: const Icon(Icons.speed, size: 18),
                  label: const Text('一键测试'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (libs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('暂无可用资源库', style: TextStyle(color: Colors.grey))),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final lib in libs)
                      ListTile(
                        leading: Icon(
                          nas.currentLibraryId == lib.id
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: nas.currentLibraryId == lib.id
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                        ),
                        title: Text(lib.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          lib.baseURL,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              lib.type == 'webdav' ? Icons.cloud_outlined : Icons.folder_outlined,
                              size: 16,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            HealthBadge(
                              tested: nas.health[lib.id] != null,
                              ok: nas.health[lib.id]?.ok ?? false,
                              latencyMs: nas.health[lib.id]?.latencyMs,
                            ),
                          ],
                        ),
                        onTap: () async {
                          await ref.read(nasManagerProvider.notifier).setCurrentLibrary(lib.id);
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          final page = context.findAncestorStateOfType<_NASPageState>();
                          page?._browse(lib, '');
                        },
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '一键测试会对 WebDAV 发 PROPFIND / 对本机目录查存在性并计时，仅标记不影响启用状态。',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

/// 资源库管理居中对话框（新增表单 + 已有库列表，行内编辑/开关/删除）。
class _LibraryManagerDialog extends ConsumerStatefulWidget {
  const _LibraryManagerDialog();

  @override
  ConsumerState<_LibraryManagerDialog> createState() => _LibraryManagerDialogState();
}

class _LibraryManagerDialogState extends ConsumerState<_LibraryManagerDialog> {
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String _type = 'webdav';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _nameCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    if (name.isEmpty || url.isEmpty) return;
    await ref.read(nasManagerProvider.notifier).addLibrary(
          name: name,
          type: _type,
          baseURL: url,
          username: _userCtrl.text.trim().isEmpty ? null : _userCtrl.text.trim(),
          password: _passCtrl.text.isEmpty ? null : _passCtrl.text,
        );
    if (!mounted) return;
    _nameCtrl.clear();
    _urlCtrl.clear();
    _userCtrl.clear();
    _passCtrl.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('资源库已添加')));
  }

  @override
  Widget build(BuildContext context) {
    final nas = ref.watch(nasManagerProvider);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('资源库管理', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 类型选择
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'webdav', label: Text('WebDAV'), icon: Icon(Icons.cloud)),
                ButtonSegment(value: 'mount', label: Text('本机目录'), icon: Icon(Icons.folder)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: '名称',
                hintText: '群晖电影库',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtrl,
              decoration: InputDecoration(
                labelText: _type == 'webdav' ? 'WebDAV 地址' : '目录路径',
                hintText: _type == 'webdav' ? 'https://nas:5006/movie' : '/Volumes/nas/movie',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (_type == 'webdav') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _userCtrl,
                      decoration: InputDecoration(
                        labelText: '账号（可选）',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: '密码（可选）',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('添加')),
            ),
            const SizedBox(height: 16),
            const Divider(),
            // 已有库列表
            for (final lib in nas.libraries)
              ListTile(
                leading: Icon(lib.type == 'webdav' ? Icons.cloud_outlined : Icons.folder_outlined),
                title: Text(lib.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(lib.baseURL, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: lib.enabled,
                      onChanged: (v) => ref.read(nasManagerProvider.notifier).setEnabled(lib.id, v),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: '编辑',
                      onPressed: () => _editLibrary(lib),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: '删除',
                      onPressed: () => ref.read(nasManagerProvider.notifier).removeLibrary(lib.id),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 编辑弹窗：字段预填，保存走 updateLibrary。
  void _editLibrary(NASLibrary lib) {
    showDialog(
      context: context,
      builder: (_) => _LibraryEditDialog(lib: lib),
    );
  }
}

/// 资源库编辑对话框（与新增同款表单，字段预填，保存更新）。
class _LibraryEditDialog extends ConsumerStatefulWidget {
  final NASLibrary lib;
  const _LibraryEditDialog({required this.lib});

  @override
  ConsumerState<_LibraryEditDialog> createState() => _LibraryEditDialogState();
}

class _LibraryEditDialogState extends ConsumerState<_LibraryEditDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late String _type;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.lib.name);
    _urlCtrl = TextEditingController(text: widget.lib.baseURL);
    _userCtrl = TextEditingController(text: widget.lib.username ?? '');
    _passCtrl = TextEditingController(text: widget.lib.password ?? '');
    _type = widget.lib.type;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    if (name.isEmpty || url.isEmpty) return;
    await ref.read(nasManagerProvider.notifier).updateLibrary(
          widget.lib.id,
          name: name,
          type: _type,
          baseURL: url,
          username: _userCtrl.text.trim().isEmpty ? null : _userCtrl.text.trim(),
          password: _passCtrl.text.isEmpty ? null : _passCtrl.text,
        );
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('资源库已更新')));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('编辑资源库'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'webdav', label: Text('WebDAV'), icon: Icon(Icons.cloud)),
                  ButtonSegment(value: 'mount', label: Text('本机目录'), icon: Icon(Icons.folder)),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 12),
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
                  labelText: _type == 'webdav' ? 'WebDAV 地址' : '目录路径',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              if (_type == 'webdav') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _userCtrl,
                        decoration: InputDecoration(
                          labelText: '账号（可选）',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _passCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: '密码（可选）',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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

/// NAS 视频卡片（对齐 Swift NASCard）：2:3 竖版封面 + 标题，首帧封面懒加载。
/// 无封面时暖沙渐变底 + 播放图标占位；点击直接播放。
class _NASVideoCard extends ConsumerStatefulWidget {
  final NASEntry entry;
  final NASLibrary lib;
  /// 当前浏览目录（相对库根，'' = 根目录）。用于还原完整文件路径取封面。
  final String parentPath;
  final VoidCallback onTap;

  const _NASVideoCard({
    required this.entry,
    required this.lib,
    required this.parentPath,
    required this.onTap,
  });

  @override
  ConsumerState<_NASVideoCard> createState() => _NASVideoCardState();
}

class _NASVideoCardState extends ConsumerState<_NASVideoCard> {
  File? _cover;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  Future<void> _loadCover() async {
    final nas = ref.read(nasManagerProvider.notifier);
    final path = widget.parentPath.isEmpty ? widget.entry.name : '${widget.parentPath}/${widget.entry.name}';
    final playURL = nas.fileURL(widget.lib, path);
    final headers = nas.playHeaders(widget.lib);
    final file = await NASCoverGenerator.shared.cover(playURL, headers: headers);
    if (!mounted) return;
    setState(() => _cover = file);
  }

  /// 去掉扩展名的展示标题（对齐 Swift drama.title 风格）。
  String get _title {
    final n = widget.entry.name;
    final dot = n.lastIndexOf('.');
    return dot > 0 ? n.substring(0, dot) : n;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 2:3 竖版封面区
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 暖沙渐变占位底（对齐 Swift Brand.placeholder → secondaryBackground）。
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cs.surfaceContainerHighest, cs.surfaceContainer],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  if (_cover != null)
                    Image.file(_cover!, fit: BoxFit.cover)
                  else
                    Center(
                      child: Icon(Icons.play_circle_fill,
                          size: 40, color: cs.primary.withValues(alpha: 0.55)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// NAS 视频播放页。
class _NASPlayerPage extends StatefulWidget {
  final String title;
  final String url;
  final Map<String, String> headers;

  const _NASPlayerPage({required this.title, required this.url, required this.headers});

  @override
  State<_NASPlayerPage> createState() => _NASPlayerPageState();
}

class _NASPlayerPageState extends State<_NASPlayerPage> {
  late final _player = Player();
  late final _controller = VideoController(_player);

  @override
  void initState() {
    super.initState();
    _player.open(Media(widget.url, httpHeaders: widget.headers));
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
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
