import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// 顶部菜单栏常驻小图标（剧立方），点击弹出 打开/显隐/退出 菜单。
  private var statusBar: StatusBarController?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    statusBar = StatusBarController()
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
