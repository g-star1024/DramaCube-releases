import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import 'tv_pages.dart';
import 'tv_scaffold.dart';

/// TV 路由 —— 常驻侧栏壳 + 详情/播放全屏页。
final tvRouter = GoRouter(
  initialLocation: '/tv',
  routes: [
    ShellRoute(
      builder: (context, state, child) => _TvShell(child: child),
      routes: [
        GoRoute(path: '/tv', builder: (context, state) => const TvHomePage()),
        GoRoute(path: '/tv/search', builder: (context, state) => const TvSearchPage()),
        GoRoute(path: '/tv/live', builder: (context, state) => const TvLivePage()),
        GoRoute(path: '/tv/mine', builder: (context, state) => const TvMinePage()),
      ],
    ),
    GoRoute(
      path: '/tv/detail',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final drama = extra?['drama'] as Drama?;
        if (drama == null) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
                child: Text('参数错误',
                    style: TextStyle(color: Colors.white))),
          );
        }
        return TvDetailPage(drama: drama);
      },
    ),
    GoRoute(
      path: '/tv/player',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final detail = extra?['detail'] as DramaDetail?;
        final startIndex = extra?['startIndex'] as int? ?? 0;
        if (detail == null) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
                child: Text('参数错误',
                    style: TextStyle(color: Colors.white))),
          );
        }
        return tvPlayerRouteBuilder(detail, startIndex);
      },
    ),
  ],
);

const _tvNavItems = [
  TvNavItem(Icons.home_rounded, '首页', '/tv'),
  TvNavItem(Icons.search_rounded, '搜索', '/tv/search'),
  TvNavItem(Icons.live_tv_rounded, '直播', '/tv/live'),
  TvNavItem(Icons.person_rounded, '我的', '/tv/mine'),
];

/// TV 导航壳（侧栏 + 内容）。
class _TvShell extends StatelessWidget {
  final Widget child;
  const _TvShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index =
        _tvNavItems.indexWhere((i) => location.startsWith(i.path)).clamp(0, 3);
    return TvScaffold(
      items: _tvNavItems,
      currentIndex: index,
      onSelect: (i) => context.go(_tvNavItems[i].path),
      child: child,
    );
  }
}
