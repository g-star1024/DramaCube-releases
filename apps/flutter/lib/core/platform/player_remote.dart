import 'package:flutter/services.dart';

/// macOS 菜单栏遥控桥（对齐 Swift 版 MenuBarController 的 Notification 遥控）。
///
/// Native（StatusBarController）通过 `dramacube/remote` MethodChannel 反向调用
/// Dart 侧的播放控制：togglePlay / next / prev。当前活跃播放器页注册回调，
/// dispose 时注销。无播放器时调用静默忽略。
class PlayerRemoteBridge {
  PlayerRemoteBridge._();
  static const _channel = MethodChannel('dramacube/remote');

  static void Function()? onTogglePlay;
  static void Function()? onNext;
  static void Function()? onPrev;

  static bool _initialized = false;

  /// 在 main() 早期调用一次，挂 Native→Dart 调用监听。
  static void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'togglePlay':
          onTogglePlay?.call();
          break;
        case 'next':
          onNext?.call();
          break;
        case 'prev':
          onPrev?.call();
          break;
      }
      return null;
    });
  }

  /// 播放器页注册遥控回调（进入播放页时）。
  static void attach({
    required void Function() togglePlay,
    required void Function() next,
    required void Function() prev,
  }) {
    onTogglePlay = togglePlay;
    onNext = next;
    onPrev = prev;
  }

  /// 播放器页注销（离开播放页时）。
  static void detach() {
    onTogglePlay = null;
    onNext = null;
    onPrev = null;
  }
}
