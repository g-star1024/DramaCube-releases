import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'core/gateway/gateway_server.dart';
import 'core/platform/app_log.dart';
import 'core/platform/player_remote.dart';
import 'core/platform/tv_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 运行日志初始化（早期，便于记录启动链路）
  await AppLog.init();
  AppLog.app('main 启动，平台 ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');

  // media_kit 初始化（libmpv 播放器内核）
  MediaKit.ensureInitialized();
  AppLog.app('MediaKit 初始化完成');

  // macOS 菜单栏遥控桥（Native→Dart 播放控制）
  PlayerRemoteBridge.init();

  // TV 模式检测（Android TV = leanback 特性）
  if (Platform.isAndroid) {
    const channel = MethodChannel('dramacube/platform');
    try {
      final isTV = await channel.invokeMethod<bool>('isTV') ?? false;
      TVMode.init(isTV: isTV);
    } catch (_) {
      TVMode.init(isTV: false);
    }
  }

  // Windows/Linux 窗口管理初始化
  if (Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
  }

  // 启动本地网关（TVBox 解析 / m3u8 代理 / WebDAV）
  // 端口被占时自动降级（如与 Swift 版剧立方同跑，8787 会冲突）；
  // 任何失败都不允许阻塞 runApp —— 否则窗口黑屏（v2.4.0 根因）。
  for (final p in const [8787, 8788, 8789, 8790, 8791]) {
    final g = GatewayServer(port: p);
    try {
      await g.start();
      globalGateway = g;
      AppLog.app('网关绑定成功 port=$p');
      break;
    } catch (e) {
      AppLog.app('网关绑定失败 port=$p err=$e');
      try {
        await g.stop();
      } catch (_) {}
    }
  }
  if (globalGateway == null) {
    AppLog.error('网关绑定全部失败（8787-8791），检查端口占用');
  }

  runApp(const ProviderScope(child: DramaCubeApp()));
}

/// 全局网关引用（防止被回收；UI 当前直连 Dio，网关为辅助通道）。
GatewayServer? globalGateway;
