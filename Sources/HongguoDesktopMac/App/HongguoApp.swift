import SwiftUI
import SwiftData

/// 应用根。注意：作为 SPM 库不携带 @main；
/// 在 Xcode 新建的 macOS App Target 中用一个单行 @main 入口引用 `HongguoApp().body` 即可。
public struct HongguoApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            CatalogView()
                .frame(minWidth: 900, minHeight: 600)
                .modelContainer(PersistenceController.shared.container)
        }
        .windowResizability(.contentSize)

        // 设置窗口（macOS 13+ Settings scene）
        Settings {
            SettingsView()
        }
    }
}
