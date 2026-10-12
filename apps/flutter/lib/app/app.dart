import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design_system.dart';
import 'settings_provider.dart';
import 'theme.dart';
import 'router.dart';
import '../features/tv/tv_router.dart';
import '../features/tv/tv_theme.dart';

/// 剧立方 DramaCube 应用入口。
class DramaCubeApp extends ConsumerWidget {
  const DramaCubeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    // 配色方案一键切换：设置变更即换色板，主题层下次 build 整体生效。
    Brand.palette = AppPalettes.byId(settings.paletteId);
    return MaterialApp.router(
      title: '剧立方 DramaCube',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // TV 模式强制深色（Cinema Dark 影院主题）
      darkTheme: settings.tvMode ? tvTheme : AppTheme.darkTheme,
      themeMode: settings.tvMode ? ThemeMode.dark : settings.themeMode,
      // 界面缩放：全局文本缩放（不动布局 transform，避免 macOS 版失控 bug）
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(settings.cardScale),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      routerConfig: settings.tvMode ? tvRouter : appRouter,
    );
  }
}
