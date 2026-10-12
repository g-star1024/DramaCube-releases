import AppKit

/// macOS 菜单栏（顶部状态栏）图标：剧立方常驻小图标。
///
/// 图标用 `MenuBarIcon` 资产并启用 template 渲染，自动适配深/浅色菜单栏
/// （深色菜单栏下显示为白色，与用户截图中的系统白色小 icon 一致）。
/// 点击弹出菜单：打开主窗口 / 显示·隐藏窗口 / 退出。Dock 图标保留（配套模式）。
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    /// 记录窗口是否被「隐藏窗口」动作隐藏（避免误判「从未显示」）。
    private var windowHidden = false

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let img = NSImage(named: "MenuBarIcon")
            img?.size = NSSize(width: 18, height: 18)
            img?.isTemplate = true  // 模板渲染：深色菜单栏自动反白
            button.image = img
            button.toolTip = "剧立方 DramaCube"
        }

        let menu = NSMenu()
        menu.addItem(makeItem("打开主窗口", action: #selector(showMainWindow), key: "o"))
        menu.addItem(makeItem("显示 / 隐藏窗口", action: #selector(toggleWindow), key: "h"))
        menu.addItem(.separator())
        menu.addItem(makeItem("退出 剧立方", action: #selector(quitApp), key: "q"))
        statusItem.menu = menu
    }

    private func makeItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// 取主 Flutter 窗口（第一个可见/在列的 NSWindow）。
    private func mainWindow() -> NSWindow? {
        NSApplication.shared.windows.first { $0 is MainFlutterWindow }
            ?? NSApplication.shared.windows.first
    }

    @objc private func showMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let win = mainWindow() {
            if win.isMiniaturized { win.deminiaturize(nil) }
            win.makeKeyAndOrderFront(nil)
        }
        windowHidden = false
    }

    @objc private func toggleWindow() {
        guard let win = mainWindow() else { showMainWindow(); return }
        if win.isVisible && !windowHidden {
            win.orderOut(nil)
            windowHidden = true
        } else {
            showMainWindow()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
