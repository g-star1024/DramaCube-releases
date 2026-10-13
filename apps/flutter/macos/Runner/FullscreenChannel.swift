import Cocoa
import FlutterMacOS

/// 全屏切换通道（替代 window_manager.setFullScreen —— 插件 0.4.3 在 macOS 14
/// 直接 toggleFullScreen SIGILL 崩溃；此处先确保窗口在全屏空间已激活后再 toggle）。
class FullscreenChannel: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dramacube/fullscreen",
      binaryMessenger: registrar.messenger)
    let instance = FullscreenChannel()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "setFullScreen",
          let args = call.arguments as? [String: Any],
          let flag = args["isFullScreen"] as? Bool else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let window = NSApp.mainWindow ?? NSApp.windows.first else {
      result(FlutterError(code: "no_window", message: "main window not found", details: nil))
      return
    }
    DispatchQueue.main.async {
      // 窗口尚在布局/动画中时 toggleFullScreen 会在 AppKit 内部断言 SIGILL，
      // 激活到前台再 toggle 是 AppKit 文档要求的前置条件。
      if !window.isKeyWindow {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
      }
      let inFull = window.styleMask.contains(.fullScreen)
      if flag != inFull {
        window.toggleFullScreen(nil)
      }
      result(nil)
    }
  }
}
