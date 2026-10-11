import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/database.dart';
import '../../core/models/models.dart';
import 'catalog_repository.dart';
import 'source_manager.dart';

/// 视频源浏览页：源 chips + 搜索 + 网格列表 + 滚动加载（对齐 macOS 版 TVBoxBrowseView）。
class CatalogPage extends ConsumerStatefulWidget {
  const CatalogPage({super.key});

  @override
  ConsumerState<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends ConsumerState<CatalogPage> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Drama> _items = [];
  int _page = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 400) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (_isLoading) return;
    final sm = ref.read(sourceManagerProvider);
    if (sm.currentSource.isEmpty) return;
    setState(() => _isLoading = true);
    if (reset) {
      _page = 1;
      _hasMore = true;
    }
    final repo = ref.read(catalogRepositoryProvider);
    final fresh = _searchQuery.isNotEmpty
        ? await repo.search(siteKey: sm.currentSource, query: _searchQuery)
        : await repo.list(siteKey: sm.currentSource, page: _page);
    setState(() {
      if (reset) {
        _items = fresh;
      } else {
        _items.addAll(fresh);
      }
      _page++;
      _hasMore = fresh.length >= 12;
      _isLoading = false;
    });
  }

  void _onSourceChanged(String key) {
    ref.read(sourceManagerProvider.notifier).setCurrentSource(key);
    _load(reset: true);
  }

  void _onSearch(String query) {
    setState(() => _searchQuery = query);
    _load(reset: true);
  }

  Future<void> _openDrama(Drama d) async {
    final repo = ref.read(catalogRepositoryProvider);
    final parts = d.id.split('|');
    if (parts.length != 3) return;
    final detail = await repo.detail(siteKey: parts[1], vodId: parts[2]);
    if (detail == null || !mounted) return;
    context.push('/player', extra: {'detail': detail, 'startIndex': 0});
  }

  @override
  Widget build(BuildContext context) {
    final sm = ref.watch(sourceManagerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频源'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '搜索影片…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearch('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onSubmitted: _onSearch,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // 源切换 chips
          if (sm.enabledSites.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  for (final site in sm.enabledSites)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(site.name),
                        selected: sm.currentSource == site.key,
                        onSelected: (_) => _onSourceChanged(site.key),
                      ),
                    ),
                ],
              ),
            ),
          // 网格列表
          Expanded(
            child: _items.isEmpty && _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.movie_outlined, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                              sm.sites.isEmpty ? '请先在设置中导入 TVBox 订阅' : '该源暂无内容',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: MediaQuery.of(context).size.width < 720 ? 120 : 160,
                          childAspectRatio: 0.65,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: _items.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == _items.length) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final d = _items[i];
                          return _DramaCard(drama: d, onTap: () => _openDrama(d));
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// 剧集卡片（封面 + 标题 + 集数 + 收藏按钮）。
class _DramaCard extends StatefulWidget {
  final Drama drama;
  final VoidCallback onTap;

  const _DramaCard({required this.drama, required this.onTap});

  @override
  State<_DramaCard> createState() => _DramaCardState();
}

class _DramaCardState extends State<_DramaCard> {
  late final AppDatabase _db;
  bool _isFav = false;

  @override
  void initState() {
    super.initState();
    _db = AppDatabase();
    _checkFav();
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }

  Future<void> _checkFav() async {
    final fav = await _db.isFavorite(widget.drama.id);
    if (mounted) setState(() => _isFav = fav);
  }

  Future<void> _toggleFav() async {
    await _db.toggleFavorite(widget.drama.id, widget.drama.title, widget.drama.coverURL);
    await _checkFav();
  }

  @override
  Widget build(BuildContext context) {
    final drama = widget.drama;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  drama.coverURL != null
                      ? Image.network(
                          drama.coverURL!,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.movie, size: 48, color: Colors.grey),
                          ),
                        )
                      : const Center(child: Icon(Icons.movie, size: 48, color: Colors.grey)),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _toggleFav,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            _isFav ? Icons.favorite : Icons.favorite_border,
                            size: 18,
                            color: _isFav ? const Color(0xFFE94560) : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drama.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  if (drama.remark != null)
                    Text(
                      drama.remark!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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
