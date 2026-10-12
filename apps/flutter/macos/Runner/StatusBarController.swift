import AppKit
import FlutterMacOS

/// macOS 菜单栏（顶部状态栏）托盘，对齐 Swift 版 MenuBarController 全功能。
///
///  - 托盘菜单：显示主窗口 / 播放·暂停(⌘Space) / 上一集·下一集 / 显示·隐藏窗口 /
///    隐藏 Dock 图标 / 关闭时最小化到菜单栏 / 退出。
///  - 「关闭时最小化到菜单栏」开（默认）：点主窗口红 × 不退出，仅隐藏窗口；
///    真正退出走托盘菜单或 ⌘Q。
///  - 播放控制经 `dramacube/remote` MethodChannel 反向调用 Dart 侧活跃播放器。
///  - 图标用 `MenuBarIcon` 资产 + template 渲染（深色菜单栏自动反白）。
final class StatusBarController: NSObject, NSWindowDelegate {
    private var statusItem: NSStatusItem
    /// MethodChannel：Native → Dart 反向调用播放控制。
    private let remoteChannel: FlutterMethodChannel
    /// 记录窗口是否被「隐藏窗口」动作隐藏（避免误判「从未显示」）。
    private var windowHidden = false
    private var hideDock = false
    private var closeToTray = true
    /// 主窗口引用（orderOut 隐藏后仍持有，用于恢复）。
    private weak var lastMainWindow: NSWindow?
    private var observedMainWindow: NSWindow?

    init(registrar: FlutterPluginRegistrar) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        remoteChannel = FlutterMethodChannel(name: "dramacube/remote", binaryMessenger: registrar.messenger)
        super.init()

        hideDock = UserDefaults.standard.bool(forKey: "ui.hideDockIcon")
        closeToTray = UserDefaults.standard.object(forKey: "ui.closeToTray") == nil
            ? true : UserDefaults.standard.bool(forKey: "ui.closeToTray")

        if let button = statusItem.button {
            let img = NSImage(named: "MenuBarIcon")
            img?.size = NSSize(width: 18, height: 18)
            img?.isTemplate = true  // 模板渲染：深色菜单栏自动反白
            button.image = img
            button.toolTip = "剧立方 DramaCube"
        }

        statusItem.menu = buildMenu()
        applyDockPolicy()
        // 主窗口可能尚未创建，延迟挂载关闭拦截。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.attachToMainWindow()
        }
    }

    // MARK: - 菜单

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makeItem("打开主窗口", action: #selector(showMainWindow), key: "o"))
        menu.addItem(.separator())
        menu.addItem(makeItem("播放 / 暂停", action: #selector(togglePlay), key: " "))
        menu.addItem(makeItem("下一集", action: #selector(nextEpisode), key: ""))
        menu.addItem(makeItem("上一集", action: #selector(prevEpisode), key: ""))
        menu.addItem(makeItem("显示 / 隐藏窗口", action: #selector(toggleWindow), key: "h"))
        menu.addItem(.separator())
        let dockItem = makeItem("隐藏 Dock 图标", action: #selector(toggleDock), key: "")
        dockItem.state = hideDock ? .on : .off
        menu.addItem(dockItem)
        let trayItem = makeItem("关闭时最小化到菜单栏", action: #selector(toggleCloseToTray), key: "")
        trayItem.state = closeToTray ? .on : .off
        menu.addItem(trayItem)
        menu.addItem(.separator())
        menu.addItem(makeItem("退出 剧立方", action: #selector(quitApp), key: "q"))
        return menu
    }

    private func makeItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func refreshMenuChecks() {
        guard let menu = statusItem.menu else { return }
        for item in menu.items {
            if item.action == #selector(toggleDock) { item.state = hideDock ? .on : .off }
            if item.action == #selector(toggleCloseToTray) { item.state = closeToTray ? .on : .off }
        }
    }

    // MARK: - 主窗口关闭 → 托盘（红 × 拦截）

    private func attachToMainWindow() {
        guard let w = mainWindow() else { return }
        guard observedMainWindow !== w else { return }
        observedMainWindow = w
        lastMainWindow = w
        w.delegate = self
    }

    /// 取主 Flutter 窗口（第一个可见/在列的 NSWindow）。
    private func mainWindow() -> NSWindow? {
        NSApplication.shared.windows.first { $0 is MainFlutterWindow }
            ?? NSApplication.shared.windows.first
    }

    // NSWindowDelegate：红 × 拦截转隐藏（保留 ⌘Q / 托盘退出真退出）。
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard closeToTray, sender === observedMainWindow else { return true }
        sender.orderOut(nil)
        windowHidden = true
        return false
    }

    // MARK: - 菜单动作

    @objc private func showMainWindow() {
        NSApplication.shared.unhide(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let win = mainWindow() ?? lastMainWindow {
            if win.isMiniaturized { win.deminiaturize(nil) }
            win.makeKeyAndOrderFront(nil)
            attachToMainWindow()
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

    @objc private func togglePlay() { remoteChannel.invokeMethod("togglePlay", arguments: nil) }
    @objc private func nextEpisode() { remoteChannel.invokeMethod("next", arguments: nil) }
    @objc private func prevEpisode() { remoteChannel.invokeMethod("prev", arguments: nil) }

    @objc private func toggleDock() {
        hideDock.toggle()
        UserDefaults.standard.set(hideDock, forKey: "ui.hideDockIcon")
        applyDockPolicy()
        refreshMenuChecks()
    }

    @objc private func toggleCloseToTray() {
        closeToTray.toggle()
        UserDefaults.standard.set(closeToTray, forKey: "ui.closeToTray")
        refreshMenuChecks()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Dock

    private func applyDockPolicy() {
        NSApplication.shared.setActivationPolicy(hideDock ? .accessory : .regular)
        if !hideDock { NSApplication.shared.activate(ignoringOtherApps: true) }
    }
}
