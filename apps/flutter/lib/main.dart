import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'core/gateway/gateway_server.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // media_kit 初始化（libmpv 播放器内核）
  MediaKit.ensureInitialized();

  // Windows/Linux 窗口管理初始化
  if (Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
  }

  // 启动本地网关（TVBox 解析 / m3u8 代理 / WebDAV）
  final gateway = GatewayServer(port: 8787);
  await gateway.start();

  runApp(const ProviderScope(child: DramaCubeApp()));
}
