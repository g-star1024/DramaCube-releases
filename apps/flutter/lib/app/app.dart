import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_provider.dart';
import 'theme.dart';
import 'router.dart';

/// 剧立方 DramaCube 应用入口。
class DramaCubeApp extends ConsumerWidget {
  const DramaCubeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
      title: '剧立方 DramaCube',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.themeMode,
      // 界面缩放：全局文本缩放（不动布局 transform，避免 macOS 版失控 bug）
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(settings.cardScale),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      routerConfig: appRouter,
    );
  }
}
