import SwiftUI
import AppKit
import HongguoCore

/// mpv 内核播放器独立窗口管理器（M2 接线）。
/// 机制与 PlayerWindowManager 一致：独立 NSWindow（.fullScreen 掩码）、
/// 手动全屏（borderless 铺满 + 自动隐藏菜单栏）、竖版自适应、Esc 退全屏、关闭回调停播存进度。
@MainActor
final class MpvWindowManager {
    static let shared = MpvWindowManager()
    private var window: NSWindow?
    private let closeDelegate = WindowCloseDelegate()
    private var savedFrame: NSRect?
    private var savedStyleMask: NSWindow.StyleMask?
    private var escMonitor: Any?
    private var switchSourceObserver: NSObjectProtocol?

    func show(detail: DramaDetail, startIndex: Int) {
        close()
        // 跨内核切换互斥：关掉可能残留的 avplayer 窗口
        PlayerWindowManager.shared.close()
        AppLog.log(.player, "[mpv] 播放窗口创建《\(detail.drama.title)》")
        let root = MpvPlayerShellView(detail: detail, startIndex: startIndex) { [weak self] in
            self?.close()
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        w.title = detail.drama.title
        w.contentView = NSHostingView(rootView: root)
        w.center()
        w.isReleasedWhenClosed = false
        w.titlebarAppearsTransparent = false
        w.tabbingMode = .disallowed
        closeDelegate.onClose = {
            NotificationCenter.default.post(name: .hongguoPlayerWindowClosed, object: nil)
        }
        w.delegate = closeDelegate
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
        installEscMonitor()
        // 监听切源/切换其他季通知：用新 detail 重建窗口（MpvPlayerShellView 的 detail 是 let，只能重建）
        switchSourceObserver = NotificationCenter.default.addObserver(
            forName: .hongguoSwitchSource, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let newDetail = note.userInfo?["detail"] as? DramaDetail,
                  let idx = note.userInfo?["startIndex"] as? Int else { return }
            MainActor.assumeIsolated { self.show(detail: newDetail, startIndex: idx) }
        }
    }

    private func installEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.window?.isKeyWindow == true,
                  self?.isManuallyFullscreen == true else { return event }
            MainActor.assumeIsolated { self?.toggleFullscreen() }
            return nil
        }
    }

    private func removeEscMonitor() {
        if let m = escMonitor { NSEvent.removeMonitor(m) }
        escMonitor = nil
    }

    var hasWindow: Bool { window?.isVisible == true }
    var isManuallyFullscreen: Bool { savedFrame != nil }

    /// 竖版视频窗口自适应（同 PlayerWindowManager：9:16 收窄 450x844，横版 960x620）。
    func adaptToVideo(portrait: Bool) {
        guard let w = window, w.isVisible, savedFrame == nil else { return }
        let target: NSSize = portrait ? NSSize(width: 450, height: 844) : NSSize(width: 960, height: 620)
        if abs(w.frame.width - target.width) < 8 && abs(w.frame.height - target.height) < 8 { return }
        var f = w.frame
        f.size = target
        f.origin.x += (w.frame.width - target.width) / 2
        f.origin.y += (w.frame.height - target.height) / 2
        if let screen = w.screen {
            f.origin.x = max(screen.visibleFrame.minX, min(f.origin.x, screen.visibleFrame.maxX - target.width))
            f.origin.y = max(screen.visibleFrame.minY, min(f.origin.y, screen.visibleFrame.maxY - target.height))
        }
        w.setFrame(f, display: true, animate: true)
    }

    func toggleFullscreen() {
        guard let w = window, w.isVisible else { return }
        if savedFrame != nil {
            if let f = savedFrame {
                w.styleMask = savedStyleMask ?? [.titled, .closable, .miniaturizable, .resizable]
                w.titlebarAppearsTransparent = false
                w.setFrame(f, display: true, animate: true)
            }
            savedFrame = nil
            savedStyleMask = nil
            NSApp.presentationOptions.remove(.autoHideMenuBar)
        } else {
            savedFrame = w.frame
            savedStyleMask = w.styleMask
            w.styleMask = [.borderless, .resizable]
            w.titlebarAppearsTransparent = true
            if let screen = w.screen ?? NSScreen.main {
                w.setFrame(screen.frame, display: true, animate: true)
            }
            NSApp.presentationOptions.insert(.autoHideMenuBar)
            w.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        if savedFrame != nil {
            NSApp.presentationOptions.remove(.autoHideMenuBar)
            savedFrame = nil
            savedStyleMask = nil
        }
        removeEscMonitor()
        if let obs = switchSourceObserver {
            NotificationCenter.default.removeObserver(obs)
            switchSourceObserver = nil
        }
        window?.delegate = nil
        window?.close()
        window = nil
        AppLog.log(.player, "[mpv] 播放窗口已关闭")
    }
}
