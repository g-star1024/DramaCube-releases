import Foundation

/// 全局静态配置。运行时会变的偏好见 `AppSettings`（UserDefaults，位于 HongguoDesktopMac）。
public enum AppConfig {
    /// 本地网关基址（Hummingbird 监听 127.0.0.1）。
    public static let gatewayBaseURL = "http://127.0.0.1:8787"
    /// 网关默认端口（独立可执行入口使用；App 内由 AppSettings.gatewayPort 控制）。
    public static let gatewayPort: Int = 8787
    /// 客户端版本。
    public static let appVersion = "1.0.0-mac"
    /// 最低系统版本（已与用户确认为 macOS 14）。
    public static let minMacOS = "14.0"
    /// 品牌主色（红果粉）。
    public static let brandHex = "#FF2D55"
}
