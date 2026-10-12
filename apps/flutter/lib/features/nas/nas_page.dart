import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/models/models.dart';
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

  Future<void> _browse(NASLibrary lib, String path) async {
    setState(() {
      _currentLib = lib;
      _currentPath = path;
      _loading = true;
      _error = null;
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
    // 目录在前，视频在后
    final dirs = _entries.where((e) => e.isDir).toList();
    final videos = _entries.where((e) => !e.isDir && NASManager.isVideo(e.name)).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 面包屑
        if (_currentPath.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_currentPath, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ),
        for (final dir in dirs)
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder, color: Colors.amber),
              title: Text(dir.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _navigateTo(dir),
            ),
          ),
        for (final video in videos)
          Card(
            child: ListTile(
              leading: const Icon(Icons.play_circle_outline, color: Colors.blue),
              title: Text(video.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _navigateTo(video),
            ),
          ),
      ],
    );
  }

  void _showLibraryManager(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _LibraryManagerSheet(),
    );
  }
}

/// 资源库管理底部弹窗。
class _LibraryManagerSheet extends ConsumerStatefulWidget {
  const _LibraryManagerSheet();

  @override
  ConsumerState<_LibraryManagerSheet> createState() => _LibraryManagerSheetState();
}

class _LibraryManagerSheetState extends ConsumerState<_LibraryManagerSheet> {
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxHeight: 600),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text('资源库管理', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
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
                      icon: const Icon(Icons.delete_outline, size: 20),
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
