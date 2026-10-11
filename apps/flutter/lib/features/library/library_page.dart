import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/database.dart';
import '../catalog/catalog_repository.dart';

/// 收藏 / 历史页（drift 持久化，对齐 macOS 版 LibraryView）。
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  late final AppDatabase _db;
  List<Favorite> _favorites = [];
  List<History> _histories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _db = AppDatabase();
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _db.close();
    super.dispose();
  }

  Future<void> _load() async {
    final favs = await _db.allFavorites();
    final hists = await _db.allHistories();
    if (!mounted) return;
    setState(() {
      _favorites = favs;
      _histories = hists;
      _loading = false;
    });
  }

  Future<void> _removeFavorite(String dramaId) async {
    await _db.removeFavorite(dramaId);
    await _load();
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('确定要清空所有播放历史吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok == true) {
      await _db.clearHistory();
      await _load();
    }
  }

  Future<void> _openDrama(String dramaId) async {
    final parts = dramaId.split('|');
    if (parts.length != 3) return;
    final repo = ref.read(catalogRepositoryProvider);
    final detail = await repo.detail(siteKey: parts[1], vodId: parts[2]);
    if (detail == null || !mounted) return;
    context.push('/player', extra: {'detail': detail, 'startIndex': 0});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [Tab(text: '收藏'), Tab(text: '历史')],
        ),
        actions: [
          if (_tabCtrl.index == 1 && _histories.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空历史',
              onPressed: _clearHistory,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildFavorites(),
                _buildHistories(),
              ],
            ),
    );
  }

  Widget _buildFavorites() {
    if (_favorites.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('暂无收藏', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _favorites.length,
      itemBuilder: (context, i) {
        final f = _favorites[i];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openDrama(f.dramaId),
            onLongPress: () => _removeFavorite(f.dramaId),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: f.coverURL != null
                      ? Image.network(
                          f.coverURL!,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Center(child: Icon(Icons.movie, size: 48, color: Colors.grey)),
                        )
                      : const Center(child: Icon(Icons.movie, size: 48, color: Colors.grey)),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    f.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistories() {
    if (_histories.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('暂无播放历史', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _histories.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final h = _histories[i];
        final progress = h.duration > 0 ? (h.position / h.duration).clamp(0.0, 1.0) : 0.0;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openDrama(h.dramaId),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 60,
                      height: 84,
                      child: h.coverURL != null
                          ? Image.network(h.coverURL!, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.movie, color: Colors.grey))
                          : const Icon(Icons.movie, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text(h.episodeTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: progress, minHeight: 3),
                        const SizedBox(height: 4),
                        Text(
                          '${_fmt(h.position)} / ${_fmt(h.duration)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _fmt(double seconds) {
    final s = seconds.toInt();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}
