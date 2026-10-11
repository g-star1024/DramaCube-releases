import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/catalog/catalog_page.dart';
import '../features/live/live_page.dart';
import '../features/nas/nas_page.dart';
import '../features/library/library_page.dart';
import '../features/settings/settings_page.dart';
import '../features/player/player_page.dart';
import '../core/models/models.dart';

/// 应用路由（底部导航 + 播放器全屏页）。
final appRouter = GoRouter(
  initialLocation: '/catalog',
  routes: [
    // 底部导航壳（视频源/直播/资源库/收藏/设置）
    ShellRoute(
      builder: (context, state, child) => HomeShell(child: child),
      routes: [
        GoRoute(path: '/catalog', builder: (context, state) => const CatalogPage()),
        GoRoute(path: '/live', builder: (context, state) => const LivePage()),
        GoRoute(path: '/nas', builder: (context, state) => const NASPage()),
        GoRoute(path: '/library', builder: (context, state) => const LibraryPage()),
        GoRoute(path: '/settings', builder: (context, state) => const SettingsPage()),
      ],
    ),
    // 播放器（全屏，无底部导航）
    GoRoute(
      path: '/player',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final detail = extra?['detail'] as DramaDetail?;
        final startIndex = extra?['startIndex'] as int? ?? 0;
        if (detail == null) {
          return const Scaffold(body: Center(child: Text('参数错误')));
        }
        return PlayerPage(detail: detail, startIndex: startIndex);
      },
    ),
  ],
);

/// 底部导航壳。
class HomeShell extends StatelessWidget {
  final Widget child;
  const HomeShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = switch (location) {
      '/catalog' => 0,
      '/live' => 1,
      '/nas' => 2,
      '/library' => 3,
      '/settings' => 4,
      _ => 0,
    };
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          switch (i) {
            case 0: context.go('/catalog');
            case 1: context.go('/live');
            case 2: context.go('/nas');
            case 3: context.go('/library');
            case 4: context.go('/settings');
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.movie_outlined), selectedIcon: Icon(Icons.movie), label: '视频源'),
          NavigationDestination(icon: Icon(Icons.tv_outlined), selectedIcon: Icon(Icons.tv), label: '电视直播'),
          NavigationDestination(icon: Icon(Icons.dns_outlined), selectedIcon: Icon(Icons.dns), label: '资源库'),
          NavigationDestination(icon: Icon(Icons.favorite_outline), selectedIcon: Icon(Icons.favorite), label: '收藏'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
