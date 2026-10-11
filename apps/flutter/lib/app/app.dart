import 'package:flutter/material.dart';

import 'theme.dart';
import 'router.dart';

/// 剧立方 DramaCube 应用入口。
class DramaCubeApp extends StatelessWidget {
  const DramaCubeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '剧立方 DramaCube',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
