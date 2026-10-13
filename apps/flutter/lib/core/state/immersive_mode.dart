import 'package:flutter/foundation.dart';

/// 播放沉浸态 —— 资源库/直播等从「导航壳内」推全屏播放页时置 true，
/// HomeShell 据此隐藏侧边导航/底部导航，播放器返回（dispose）后恢复。
///
/// 轻量方案：不改 go_router 结构（导航壳内的 MaterialPageRoute push 仍会渲染壳），
/// 只让壳在沉浸态时不渲染导航。
class ImmersiveMode {
  ImmersiveMode._();
  static final ValueNotifier<bool> active = ValueNotifier(false);
}
