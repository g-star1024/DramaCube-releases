import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_system.dart';
import '../../core/db/database.dart';
import '../../core/models/models.dart';
import '../../core/widgets/cover_image.dart';
import '../catalog/catalog_repository.dart';

/// 收藏 / 历史页（drift 持久化，编辑模式多选删除，对齐 macOS 版）。
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

  // 编辑模式（多选删除）
  bool _editing = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging || mounted) {
        setState(() {
          _editing = false;
          _selected.clear();
        });
      }
    });
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
      // 清掉已不存在的选择
      _selected.removeWhere((k) =>
          !_favorites.any((f) => f.dramaId == k) && !_histories.any((h) => h.key == k));
    });
  }

  void _toggleEdit() {
    setState(() {
      _editing = !_editing;
      _selected.clear();
    });
  }

  void _toggleSelected(String key) {
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final isHistoryTab = _tabCtrl.index == 1;
    final count = _selected.length;
    if (count == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除所选（$count）'),
        content: const Text('确定删除选中的条目吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    if (isHistoryTab) {
      await _db.removeHistories(_selected.toList());
    } else {
      // 收藏的选择键是 dramaId
      await _db.removeFavorites(_selected.toList());
    }
    _toggleEdit();
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

  /// 打开条目：tvbox 直播；豆瓣条目走详情页（聚合搜可播版本）。
  Future<void> _openDrama(String dramaId) async {
    final parts = dramaId.split('|');
    if (parts.isEmpty) return;
    if (parts.first == 'douban') {
      // 从收藏/历史找回标题与封面
      String title = '';
      String? cover;
      for (final f in _favorites) {
        if (f.dramaId == dramaId) { title = f.title; cover = f.coverURL; }
      }
      for (final h in _histories) {
        if (h.dramaId == dramaId) { title = h.title; cover ??= h.coverURL; }
      }
      if (title.isEmpty) return;
      context.push('/detail', extra: {
        'drama': Drama(id: dramaId, title: title, coverURL: cover),
      });
      return;
    }
    if (parts.length != 3) return;
    final repo = ref.read(catalogRepositoryProvider);
    final detail = await repo.detail(siteKey: parts[1], vodId: parts[2]);
    if (detail == null || !mounted) return;
    context.push('/player', extra: {'detail': detail, 'startIndex': 0});
  }

  @override
  Widget build(BuildContext context) {
    final isHistoryTab = _tabCtrl.index == 1;
    final hasItems = isHistoryTab ? _histories.isNotEmpty : _favorites.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? '已选 ${_selected.length} 项' : '收藏'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [Tab(text: '收藏'), Tab(text: '历史')],
        ),
        actions: [
          if (hasItems && !_editing) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑',
              onPressed: _toggleEdit,
            ),
            if (isHistoryTab)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '清空历史',
                onPressed: _clearHistory,
              ),
          ],
          if (_editing) ...[
            IconButton(
              icon: Icon(
                _selected.length == (isHistoryTab ? _histories.length : _favorites.length)
                    ? Icons.deselect
                    : Icons.select_all,
              ),
              tooltip: '全选 / 取消',
              onPressed: () {
                setState(() {
                  if (_selected.length ==
                      (isHistoryTab ? _histories.length : _favorites.length)) {
                    _selected.clear();
                  } else {
                    _selected
                      ..clear()
                      ..addAll(isHistoryTab
                          ? _histories.map((h) => h.key)
                          : _favorites.map((f) => f.dramaId));
                  }
                });
              },
            ),
            TextButton(
              onPressed: _selected.isEmpty ? null : _deleteSelected,
              child: const Text('删除'),
            ),
          ],
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

  Widget _empty(IconData icon, String label) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64,
                color: Brand.placeholder(Theme.of(context).brightness).computeLuminance() > 0.5
                    ? Colors.black26 : Colors.white24),
            const SizedBox(height: Spacing.md),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );

  Widget _buildFavorites() {
    if (_favorites.isEmpty) return _empty(Icons.favorite_outline, '暂无收藏');
    return GridView.builder(
      padding: const EdgeInsets.all(Spacing.lg),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 0.62,
        crossAxisSpacing: Spacing.md,
        mainAxisSpacing: Spacing.md,
      ),
      itemCount: _favorites.length,
      itemBuilder: (context, i) {
        final f = _favorites[i];
        final selected = _selected.contains(f.dramaId);
        return _SelectableCard(
          selected: selected,
          editing: _editing,
          onToggle: () => _toggleSelected(f.dramaId),
          onTap: () {
            if (_editing) {
              _toggleSelected(f.dramaId);
            } else {
              _openDrama(f.dramaId);
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radius.md),
                  child: CoverImage(url: f.coverURL, title: f.title),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Text(
                  f.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistories() {
    if (_histories.isEmpty) return _empty(Icons.history, '暂无播放历史');
    return ListView.separated(
      padding: const EdgeInsets.all(Spacing.lg),
      itemCount: _histories.length,
      separatorBuilder: (_, __) => const SizedBox(height: Spacing.sm),
      itemBuilder: (context, i) {
        final h = _histories[i];
        final selected = _selected.contains(h.key);
        final progress = h.duration > 0 ? (h.position / h.duration).clamp(0.0, 1.0) : 0.0;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              if (_editing) {
                _toggleSelected(h.key);
              } else {
                _openDrama(h.dramaId);
              }
            },
            onLongPress: _editing ? null : () {
              setState(() {
                _editing = true;
                _selected.add(h.key);
              });
            },
            child: Container(
              color: selected ? Brand.accent(Theme.of(context).brightness).withValues(alpha: 0.08) : null,
              padding: const EdgeInsets.all(Spacing.md),
              child: Row(
                children: [
                  if (_editing)
                    Padding(
                      padding: const EdgeInsets.only(right: Spacing.md),
                      child: Icon(
                        selected ? Icons.check_circle : Icons.circle_outlined,
                        color: selected ? Brand.accent(Theme.of(context).brightness) : null,
                      ),
                    ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radius.sm),
                    child: SizedBox(
                      width: 60,
                      height: 84,
                      child: CoverImage(url: h.coverURL, title: h.title),
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(h.episodeTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        const SizedBox(height: Spacing.sm),
                        LinearProgressIndicator(value: progress, minHeight: 3),
                        const SizedBox(height: 4),
                        Text(
                          '${_fmt(h.position)} / ${_fmt(h.duration)}',
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
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

/// 可选中卡片（编辑模式勾选态）。
class _SelectableCard extends StatelessWidget {
  final bool selected;
  final bool editing;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  final Widget child;

  const _SelectableCard({
    required this.selected,
    required this.editing,
    required this.onToggle,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Brand.accent(Theme.of(context).brightness);
    return InkWell(
      onTap: onTap,
      onLongPress: editing ? null : () {
        if (!editing) onToggle();
      },
      borderRadius: BorderRadius.circular(Radius.md),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radius.md),
              border: selected ? Border.all(color: accent, width: 2) : null,
            ),
            padding: selected ? const EdgeInsets.all(2) : null,
            child: child,
          ),
          if (editing)
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: onToggle,
                child: Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? accent : Colors.white70,
                  shadows: const [Shadow(blurRadius: 4, color: Colors.black38)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
