import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// 顶部菜单栏常驻托盘（剧立方）：播放控制 / 显隐窗口 / 隐藏 Dock / 关闭最小化 / 退出。
  private var statusBar: StatusBarController?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = mainFlutterWindow?.contentViewController as! FlutterViewController
    let registrar = controller.registrar(forPlugin: "StatusBarController")
    statusBar = StatusBarController(registrar: registrar)
    FullscreenChannel.register(with: controller.registrar(forPlugin: "FullscreenChannel"))
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 「关闭时最小化到菜单栏」开（默认）：红 × 已被 StatusBarController 拦截为隐藏，
    // 窗口不会真正关闭，此回调不触发；只有用户关掉开关时窗口才真关闭 → 此时退出。
    let closeToTray = UserDefaults.standard.object(forKey: "ui.closeToTray") == nil
      ? true : UserDefaults.standard.bool(forKey: "ui.closeToTray")
    return !closeToTray
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
