import Foundation

/// 全局配置。网关随 App 启动（见 GatewayLauncher），前端只连本机回环地址。
public enum AppConfig {
    /// 本地网关基址（Hummingbird 监听 127.0.0.1:8787）。
    public static let gatewayBaseURL = "http://127.0.0.1:8787"
    /// 客户端版本。
    public static let appVersion = "1.0.0-mac"
    /// 最低系统版本。
    public static let minMacOS = "13.0"
    /// 品牌主色（红果粉）。
    public static let brandHex = "#FF2D55"
}
