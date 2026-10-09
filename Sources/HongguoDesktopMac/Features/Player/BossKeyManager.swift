import AppKit

/// 老板键：全局快捷键（默认 Cmd+Shift+H）隐藏 / 显示所有窗口并暂停 / 恢复播放。
///
/// 隐藏时广播 `.hongguoBossKeyHide`（播放器暂停），恢复时广播 `.hongguoBossKeyShow`。
@MainActor
final class BossKeyManager {
    static let shared = BossKeyManager()
    private var monitor: Any?
    private var hidden = false

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.command, .shift]),
               event.charactersIgnoringModifiers?.lowercased() == "h" {
                Task { @MainActor in self?.toggle() }
                return nil
            }
            return event
        }
    }

    func toggle() {
        if !hidden {
            NotificationCenter.default.post(name: .hongguoBossKeyHide, object: nil)
            for w in NSApp.windows where w.isVisible && w.level != .floating && w.level != .statusBar {
                w.orderOut(nil)
            }
            hidden = true
        } else {
            for w in NSApp.windows where !w.isVisible {
                if w.isMiniaturized { w.deminiaturize(nil) } else { w.orderFront(nil) }
            }
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .hongguoBossKeyShow, object: nil)
            hidden = false
        }
    }
}

extension Notification.Name {
    static let hongguoBossKeyHide = Notification.Name("hongguoBossKeyHide")
    static let hongguoBossKeyShow = Notification.Name("hongguoBossKeyShow")
}
