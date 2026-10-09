import AppKit
import SwiftUI

/// 菜单栏托盘控制器（顶部状态栏图标 + 快捷控制 + 关闭最小化 + Dock 隐藏）。
///
///  - 托盘菜单：显示主窗口 / 播放·暂停 / 上一集·下一集 / 全屏 / 显示播放窗口 / 隐藏 Dock / 退出
///  - 「关闭时最小化到菜单栏」开（默认）：点主窗口红 × 不退出，仅隐藏窗口；
///    真正退出走托盘菜单或 ⌘Q。
///  - 「隐藏 Dock 图标」切换 NSApplication.activationPolicy（accessory/regular）。
@MainActor
final class MenuBarController: NSObject, NSWindowDelegate {
    static let shared = MenuBarController()
    private override init() { super.init() }

    private var statusItem: NSStatusItem?
    private var observedMainWindow: NSWindow?
    private var hideDock = false
    private var closeToTray = true

    // MARK: - 启动

    func start() {
        hideDock = UserDefaults.standard.bool(forKey: "ui.hideDockIcon")
        closeToTray = UserDefaults.standard.object(forKey: "ui.closeToTray") == nil
            ? true : UserDefaults.standard.bool(forKey: "ui.closeToTray")
        installStatusItem()
        applyDockPolicy()
        observeMainWindow()
        AppLog.log(.app, "菜单栏托盘已启动（hideDock=\(hideDock) closeToTray=\(closeToTray)）")
    }

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = item.button {
            // 优先用 app 图标缩略；失败回退 SF Symbol
            let img = NSApp.applicationIconImage.copy() as? NSImage
            img?.size = NSSize(width: 18, height: 18)
            btn.image = img ?? NSImage(systemSymbolName: "play.square.stack", accessibilityDescription: "剧立方")
            btn.image?.isTemplate = false
        }
        item.menu = buildMenu()
        statusItem = item
    }

    // MARK: - 菜单

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let showMain = NSMenuItem(title: "显示主窗口", action: #selector(onShowMain), keyEquivalent: "")
        showMain.target = self
        menu.addItem(showMain)

        menu.addItem(.separator())

        let playPause = NSMenuItem(title: "播放 / 暂停", action: #selector(onTogglePlay), keyEquivalent: " ")
        playPause.target = self
        menu.addItem(playPause)

        let next = NSMenuItem(title: "下一集", action: #selector(onNext), keyEquivalent: "")
        next.target = self
        menu.addItem(next)

        let prev = NSMenuItem(title: "上一集", action: #selector(onPrev), keyEquivalent: "")
        prev.target = self
        menu.addItem(prev)

        let showPlayer = NSMenuItem(title: "显示播放窗口", action: #selector(onShowPlayer), keyEquivalent: "")
        showPlayer.target = self
        menu.addItem(showPlayer)

        menu.addItem(.separator())

        let hideDockItem = NSMenuItem(title: "隐藏 Dock 图标", action: #selector(onToggleDock), keyEquivalent: "")
        hideDockItem.target = self
        hideDockItem.state = hideDock ? .on : .off
        menu.addItem(hideDockItem)

        let closeToTrayItem = NSMenuItem(title: "关闭时最小化到菜单栏", action: #selector(onToggleCloseToTray), keyEquivalent: "")
        closeToTrayItem.target = self
        closeToTrayItem.state = closeToTray ? .on : .off
        menu.addItem(closeToTrayItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出剧立方", action: #selector(onQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func refreshMenuChecks() {
        guard let menu = statusItem?.menu else { return }
        for item in menu.items {
            if item.action == #selector(onToggleDock) { item.state = hideDock ? .on : .off }
            if item.action == #selector(onToggleCloseToTray) { item.state = closeToTray ? .on : .off }
        }
    }

    // MARK: - 主窗口关闭 → 托盘

    /// 挂到主窗口 delegate：红 × 拦截，转隐藏（保留 ⌘Q 真退出）。
    private func observeMainWindow() {
        // 主窗口此时可能还没创建，延迟挂载；后续窗口变化在 onShowMain 时补挂。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.attachToMainWindow()
        }
    }

    private func attachToMainWindow() {
        guard let w = mainWindow() else { return }
        guard observedMainWindow !== w else { return }
        observedMainWindow = w
        w.delegate = self
    }

    private func mainWindow() -> NSWindow? {
        // 排除播放器窗口（由 PlayerWindowManager 管）与设置/关于等辅助窗口
        NSApp.windows.first { win in
            win.isVisible && win.title != "" && win.level == .normal
                && win.frame.width >= 900 // 主窗口最小宽 1024
        } ?? NSApp.mainWindow
    }

    // NSWindowDelegate
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard closeToTray, sender === observedMainWindow else { return true }
        sender.orderOut(nil)
        AppLog.log(.app, "主窗口关闭 → 已最小化到菜单栏托盘")
        return false
    }

    // MARK: - 菜单动作

    @objc private func onShowMain() {
        attachToMainWindow()
        if let w = mainWindow() {
            w.makeKeyAndOrderFront(nil)
            w.deminiaturize(nil)
        } else {
            // 窗口被销毁场景：重新触发 SwiftUI WindowGroup 创建（发 openWindow）
            NSApp.unhide(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func onTogglePlay() {
        NotificationCenter.default.post(name: .hongguoRemoteToggle, object: nil)
    }
    @objc private func onNext() {
        NotificationCenter.default.post(name: .hongguoRemoteNext, object: nil)
    }
    @objc private func onPrev() {
        NotificationCenter.default.post(name: .hongguoRemotePrev, object: nil)
    }
    @objc private func onShowPlayer() {
        // 激活播放器窗口（若存在）
        if let w = NSApp.windows.first(where: { $0.title.contains("·") || $0.frame.width == 960 }) {
            w.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func onToggleDock() {
        hideDock.toggle()
        UserDefaults.standard.set(hideDock, forKey: "ui.hideDockIcon")
        applyDockPolicy()
        refreshMenuChecks()
        AppLog.log(.app, "Dock 图标：\(hideDock ? "已隐藏（仅菜单栏）" : "已恢复")")
    }

    @objc private func onToggleCloseToTray() {
        closeToTray.toggle()
        UserDefaults.standard.set(closeToTray, forKey: "ui.closeToTray")
        refreshMenuChecks()
    }

    @objc private func onQuit() {
        // 真退出（绕过 windowShouldClose 拦截）
        NSApp.terminate(nil)
    }

    // MARK: - Dock

    private func applyDockPolicy() {
        NSApp.setActivationPolicy(hideDock ? .accessory : .regular)
        if !hideDock { NSApp.activate(ignoringOtherApps: true) }
    }
}
