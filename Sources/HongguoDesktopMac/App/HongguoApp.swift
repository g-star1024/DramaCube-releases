import SwiftUI
import SwiftData
import AppKit
import HongguoCore

/// 应用根。注意：作为 SPM 库不携带 @main；
/// 在 Xcode 新建的 macOS App Target 中用一个单行 @main 入口引用 `HongguoApp().body` 即可。
public struct HongguoApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            CatalogView()
                .frame(minWidth: 1024, minHeight: 640)
                .preferredColorScheme(AppSettings.shared.preferredColorScheme)
                .environment(\.uiFontScale, AppSettings.shared.uiFontScale)
                .modelContainer(PersistenceController.shared.container)
                .task {
                    AppLog.log(.app, "App 启动，版本 \(AppConfig.appVersion)，macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                    Watchdog.start()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    AppLog.log(.app, "App 即将退出")
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("播放") {
                Button("播放 / 暂停") {
                    NotificationCenter.default.post(name: .hongguoRemoteToggle, object: nil)
                }
                .keyboardShortcut(.space, modifiers: [])

                Divider()

                Button("下一集") {
                    NotificationCenter.default.post(name: .hongguoRemoteNext, object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Button("上一集") {
                    NotificationCenter.default.post(name: .hongguoRemotePrev, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Divider()

                Button("老板键（隐藏 / 显示）") {
                    BossKeyManager.shared.toggle()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }
            // 注：搜索框聚焦由 .searchable 原生提供（⌘F），无需自定义菜单项。
        }

        // 设置窗口（macOS 13+ Settings scene）
        Settings {
            SettingsView()
        }
    }
}
