import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/catalog/catalog_page.dart';
import '../features/live/live_page.dart';
import '../features/nas/nas_page.dart';
import '../features/library/library_page.dart';
import '../features/settings/settings_page.dart';
import '../features/player/player_page.dart';
import '../core/models/models.dart';

/// 应用路由（宽屏侧栏 / 窄屏底部导航 + 播放器全屏页）。
final appRouter = GoRouter(
  initialLocation: '/catalog',
  routes: [
    // 导航壳（视频源/直播/资源库/收藏/设置）
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
    // 播放器（全屏，无导航壳）
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

/// 导航项定义（壳与 Rail/底栏共用）。
class _NavItem {
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavItem(this.path, this.icon, this.selectedIcon, this.label);
}

const _navItems = [
  _NavItem('/catalog', Icons.movie_outlined, Icons.movie, '视频源'),
  _NavItem('/live', Icons.tv_outlined, Icons.tv, '电视直播'),
  _NavItem('/nas', Icons.dns_outlined, Icons.dns, '资源库'),
  _NavItem('/library', Icons.favorite_outline, Icons.favorite, '收藏'),
  _NavItem('/settings', Icons.settings_outlined, Icons.settings, '设置'),
];

/// 自适应导航壳 —— 宽屏（≥900）左侧 NavigationRail，窄屏底部导航。
class HomeShell extends StatelessWidget {
  final Widget child;
  const HomeShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _navItems.indexWhere((i) => location.startsWith(i.path));
    final currentIndex = index == -1 ? 0 : index;
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: currentIndex,
              onDestinationSelected: (i) => context.go(_navItems[i].path),
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 8),
                child: Column(
                  children: [
                    Text('剧立方', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              destinations: [
                for (final item in _navItems)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: Text(item.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) => context.go(_navItems[i].path),
        destinations: [
          for (final item in _navItems)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}
