import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/catalog/catalog_page.dart';
import '../features/live/live_page.dart';
import '../features/nas/nas_page.dart';
import '../features/library/library_page.dart';
import '../features/settings/settings_page.dart';
import '../features/player/player_page.dart';
import '../features/discover/discover_page.dart';
import '../features/detail/detail_page.dart';
import '../features/search/search_page.dart';
import '../features/downloads/downloads_page.dart';
import '../core/models/models.dart';
import 'motion.dart';

/// 页面转场 —— 淡入 + 上滑 12%（v3 统一转场）。
CustomTransitionPage<void> _fadeSlidePage(Widget child, GoRouterState state) =>
    CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: Motion.durSlow,
      reverseTransitionDuration: Motion.durMed,
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Motion.curveEmphasized,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.12),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );

/// 应用路由（宽屏侧栏 / 窄屏底部导航 + 播放器全屏页）。
final appRouter = GoRouter(
  initialLocation: '/discover',
  routes: [
    // 导航壳（发现/视频源/直播/资源库/我的/设置）
    ShellRoute(
      builder: (context, state, child) => HomeShell(child: child),
      routes: [
        GoRoute(
          path: '/discover',
          pageBuilder: (context, state) =>
              _fadeSlidePage(const DiscoverPage(), state),
        ),
        GoRoute(
          path: '/catalog',
          pageBuilder: (context, state) =>
              _fadeSlidePage(const CatalogPage(), state),
        ),
        GoRoute(
          path: '/live',
          pageBuilder: (context, state) =>
              _fadeSlidePage(const LivePage(), state),
        ),
        GoRoute(
          path: '/nas',
          pageBuilder: (context, state) =>
              _fadeSlidePage(const NASPage(), state),
        ),
        GoRoute(
          path: '/library',
          pageBuilder: (context, state) =>
              _fadeSlidePage(const LibraryPage(), state),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) =>
              _fadeSlidePage(const SettingsPage(), state),
        ),
        GoRoute(
          path: '/detail',
          pageBuilder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            final drama = extra?['drama'] as Drama?;
            if (drama == null) {
              return _fadeSlidePage(
                const Scaffold(body: Center(child: Text('参数错误'))),
                state,
              );
            }
            return _fadeSlidePage(DetailPage(drama: drama), state);
          },
        ),
        GoRoute(
          path: '/search',
          pageBuilder: (context, state) =>
              _fadeSlidePage(const SearchPage(), state),
        ),
        GoRoute(
          path: '/downloads',
          pageBuilder: (context, state) =>
              _fadeSlidePage(const DownloadsPage(), state),
        ),
      ],
    ),
    // 播放器（全屏，无导航壳）
    GoRoute(
      path: '/player',
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final detail = extra?['detail'] as DramaDetail?;
        final startIndex = extra?['startIndex'] as int? ?? 0;
        if (detail == null) {
          return _fadeSlidePage(
            const Scaffold(body: Center(child: Text('参数错误'))),
            state,
          );
        }
        return _fadeSlidePage(
          PlayerPage(detail: detail, startIndex: startIndex),
          state,
        );
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
  _NavItem('/discover', Icons.explore_outlined, Icons.explore, '发现'),
  _NavItem('/catalog', Icons.movie_outlined, Icons.movie, '视频源'),
  _NavItem('/live', Icons.tv_outlined, Icons.tv, '直播'),
  _NavItem('/nas', Icons.dns_outlined, Icons.dns, '资源库'),
  _NavItem('/library', Icons.person_outline, Icons.person, '我的'),
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
