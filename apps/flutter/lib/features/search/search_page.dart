import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_system.dart';
import '../../core/models/models.dart';
import '../../core/widgets/poster_card.dart';
import '../catalog/catalog_repository.dart';

/// 聚合搜索页 —— 并发检索全部启用源，流式呈现（对齐 macOS 版）。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SiteGroup {
  final String siteName;
  final List<Drama> results;
  _SiteGroup(this.siteName, this.results);
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _ctrl = TextEditingController();
  bool _searching = false;
  bool _allDone = false;
  String? _playingId; // 正在拉取详情准备播放的结果 id
  final List<_SiteGroup> _groups = [];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _run(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _allDone = false;
      _groups.clear();
    });
    ref.read(catalogRepositoryProvider).aggregateSearch(
          query: q,
          onSiteDone: (siteName, results) {
            if (!mounted) return;
            setState(() => _groups.add(_SiteGroup(siteName, results)));
          },
          onAllDone: () {
            if (mounted) setState(() { _searching = false; _allDone = true; });
          },
        );
  }

  /// 点击搜索结果直接播放第一集（不再经详情页跳转）；长按才进详情。
  Future<void> _play(Drama drama) async {
    final parts = drama.id.split('|');
    if (parts.length != 3) return;
    setState(() => _playingId = drama.id);
    final detail = await ref
        .read(catalogRepositoryProvider)
        .detail(siteKey: parts[1], vodId: parts[2]);
    if (!mounted) return;
    setState(() => _playingId = null);
    if (detail == null || detail.episodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('该结果暂无可播放资源，长按可查看详情'),
      ));
      return;
    }
    context.push('/player', extra: {'detail': detail, 'startIndex': 0});
  }

  void _openDetail(Drama drama) {
    context.push('/detail', extra: {'drama': drama});
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: Spacing.lg),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: _run,
            decoration: InputDecoration(
              hintText: '搜索剧名，跨源并发检索…',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.md),
                borderSide: BorderSide.none,
              ),
              filled: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ),
      body: _groups.isEmpty && !_searching
          ? Center(
              child: Text(
                '输入剧名开始搜索\n点击直接播放 · 长按查看详情',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: subtitle),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(Spacing.lg),
              itemCount: _groups.length + (_searching ? 1 : 0) +
                  (_allDone && _groups.isEmpty ? 1 : 0),
              itemBuilder: (context, i) {
                if (i < _groups.length) {
                  final group = _groups[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              group.siteName,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Brand.accent(Theme.of(context).brightness),
                              ),
                            ),
                            const SizedBox(width: Spacing.sm),
                            Text('${group.results.length} 条',
                                style: TextStyle(fontSize: 12, color: subtitle)),
                          ],
                        ),
                        const SizedBox(height: Spacing.md),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 140,
                            mainAxisSpacing: Spacing.md,
                            crossAxisSpacing: Spacing.md,
                            childAspectRatio: 0.55,
                          ),
                          itemCount: group.results.length,
          itemBuilder: (context, j) {
            final drama = group.results[j];
            final playing = _playingId == drama.id;
            return Stack(
              children: [
                PosterCard(
                  drama: drama,
                  onTap: () => _play(drama),
                  onLongPress: () => _openDetail(drama),
                ),
                if (playing)
                  Positioned.fill(
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(Radii.md),
                      ),
                      child: const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            );
          },
                        ),
                      ],
                    ),
                  );
                }
                // 末尾状态行
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
                  child: Center(
                    child: _searching
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: Spacing.sm),
                              Text('正在检索其余源…',
                                  style: TextStyle(fontSize: 12, color: subtitle)),
                            ],
                          )
                        : Text('全部源检索完毕，未找到结果',
                            style: TextStyle(fontSize: 12, color: subtitle)),
                  ),
                );
              },
            ),
    );
  }
}
