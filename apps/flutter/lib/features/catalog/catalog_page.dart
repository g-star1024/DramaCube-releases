import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_system.dart';
import '../../core/db/database.dart';
import '../../core/models/models.dart';
import '../../core/platform/tv_mode.dart';
import '../../core/widgets/health_badge.dart';
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
  String _loadedSource = '';
  /// 频道分类（对齐 Swift TVBoxBrowseView）：最新 + 各 type_id 分类。
  List<Map<String, String>> _categories = [];
  String? _selectedTypeId; // null = 最新

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 默认展示延迟最低的源（用户手动切换后按设置展示）。
      ref.read(sourceManagerProvider.notifier).autoSelectFastest();
      _load(reset: true);
      _loadCategories();
    });
  }

  /// 拉当前源的频道分类（type_id → type_name）。源切换后随源重拉。
  Future<void> _loadCategories() async {
    final siteKey = ref.read(sourceManagerProvider).currentSource;
    if (siteKey.isEmpty) return;
    final cats = await ref.read(catalogRepositoryProvider).categories(siteKey: siteKey);
    if (!mounted) return;
    setState(() => _categories = cats);
  }

  /// 选中频道：切换 typeId 并重置加载。
  void _selectCategory(String? typeId) {
    if (_selectedTypeId == typeId) return;
    setState(() {
      _selectedTypeId = typeId;
      // 选中具体频道时清空搜索（频道与搜索互斥，对齐 Swift）。
      if (typeId != null) {
        _searchQuery = '';
        _searchCtrl.clear();
      }
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() => _maybeLoadMore();

  /// 续页评估：接近底部，或内容不满一屏时自动加载下一页。
  ///
  /// 大屏缺陷根因：`cardExtent` 固定 160px，宽屏下 GridView 列数可达 8-10 列，
  /// 首页 12 项仅两行填不满视口 → `maxScrollExtent ≈ 0` → 纯滚动监听永不触发
  /// → 分页不加载、`_hasMore` 为真使底部转圈永远转（小屏 2 列超高可滚动故正常）。
  /// 语义对齐 macOS 版 TVBoxBrowseView：ScrollBottomPreferenceKey 持续评估内容底部，
  /// 距视口不足阈值即续页，同样不满屏场景不会卡。
  void _maybeLoadMore() {
    if (!mounted || _isLoading || !_hasMore || _items.isEmpty) return;
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final nearBottom = pos.pixels >= pos.maxScrollExtent - 400;
    // 内容高度不足一屏（含滚动余量）时也要续页，直到填满视口或无更多。
    final underfilled = pos.maxScrollExtent <= 400;
    if (nearBottom || underfilled) _load(reset: false);
  }

  Future<void> _load({required bool reset}) async {
    if (_isLoading) return;
    final sm = ref.read(sourceManagerProvider);
    if (sm.currentSource.isEmpty) {
      // 尚未导入订阅 → 无可加载；已导入但当前源为空（旧版本空键 bug）→ 先自愈。
      if (sm.sites.isEmpty) return;
      ref.read(sourceManagerProvider.notifier).autoSelectFastest();
    }
    final siteKey = ref.read(sourceManagerProvider).currentSource;
    if (siteKey.isEmpty) return;
    _loadedSource = siteKey;
    setState(() => _isLoading = true);
    if (reset) {
      _page = 1;
      _hasMore = true;
    }
    final repo = ref.read(catalogRepositoryProvider);
    final fresh = _searchQuery.isNotEmpty
        ? await repo.search(siteKey: siteKey, query: _searchQuery)
        : await repo.list(siteKey: siteKey, page: _page, typeId: _selectedTypeId);
    setState(() {
      if (reset) {
        _items = fresh;
      } else {
        _items.addAll(fresh);
      }
      _page++;
      // 搜索为单页结果（仓库固定 pg=1，无分页语义）：不置 hasMore，
      // 否则滚动到底会把同一批搜索结果反复追加（重复卡片 + 无限增长）。
      _hasMore = _searchQuery.isEmpty && fresh.length >= 12;
      _isLoading = false;
    });
  }

  /// 频道分类 chip（选中态高亮）。
  Widget _catChip(String? typeId, String name) {
    final selected = _selectedTypeId == typeId;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(name, style: const TextStyle(fontSize: 13)),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => _selectCategory(typeId),
        backgroundColor: cs.surfaceContainerHighest,
        selectedColor: cs.primaryContainer,
        labelStyle: TextStyle(
          color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        side: BorderSide.none,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  /// 右上角源切换弹层（延迟排序 + 失效标记 + 一键测速）。
  void _showSourceSheet() {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
          child: const _SourceSwitchSheet(),
        ),
      ),
    );
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
    // 源异步加载 / 自动切换后按新源重新拉取。
    if (sm.currentSource.isNotEmpty && sm.currentSource != _loadedSource) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(sourceManagerProvider.notifier).autoSelectFastest();
        _selectedTypeId = null; // 切源重置频道
        _load(reset: true);
        _loadCategories();
      });
    }
    // 大屏不满屏时滚动监听不触发 → 每帧布局后评估补页（_maybeLoadMore 内有防抖守卫）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频源'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: '切换源',
            onPressed: _showSourceSheet,
          ),
        ],
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
          // 频道分类栏（对齐 Swift TVBoxBrowseView：最新 + 各 type_id 分类 chips）
          if (_categories.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                children: [
                  _catChip(null, '最新'),
                  for (final c in _categories)
                    _catChip(c['type_id'], c['type_name'] ?? ''),
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
                          maxCrossAxisExtent: TVMode.cardExtent(context),
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

/// 源切换弹层：按延迟排序 + 失效标记 + 一键测试连通性。
class _SourceSwitchSheet extends ConsumerWidget {
  const _SourceSwitchSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sm = ref.watch(sourceManagerProvider);
    final sorted = sm.sortedEnabledSites;
    return SafeArea(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 560),
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('切换视频源', style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: sm.testingAll
                      ? null
                      : () => ref.read(sourceManagerProvider.notifier).testAll(),
                  icon: sm.testingAll
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.speed, size: 18),
                  label: Text(sm.testingAll ? '测试中…' : '一键测试'),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            if (sorted.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.xl),
                child: Center(
                  child: Text('暂无可用源，请先在设置中心导入订阅',
                      style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final site in sorted)
                      ListTile(
                        leading: Icon(
                          sm.currentSource == site.key
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: sm.currentSource == site.key
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                        ),
                        title: Text(site.name),
                        subtitle: Text(
                          site.api,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: HealthBadge(
                          tested: sm.health[site.key] != null,
                          ok: sm.health[site.key]?.ok ?? false,
                          latencyMs: sm.health[site.key]?.latencyMs,
                        ),
                        onTap: () {
                          ref.read(sourceManagerProvider.notifier).setCurrentSource(site.key);
                          Navigator.pop(context);
                        },
                      ),
                  ],
                ),
              ),
            const SizedBox(height: Spacing.sm),
            Text(
              '默认展示延迟最低的源；手动切换后按你的设置展示。失效源可在设置中心重新启用。',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
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
    return TVFocusable(
      onSelect: widget.onTap,
      child: Card(
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
      ),
    );
  }
}
