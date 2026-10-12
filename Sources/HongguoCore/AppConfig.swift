import Foundation

/// 全局静态配置。运行时会变的偏好见 `AppSettings`（UserDefaults，位于 HongguoDesktopMac）。
public enum AppConfig {
    /// 本地网关基址（Hummingbird 监听 127.0.0.1）。
    ///
    /// 注意：必须读**运行时** `GatewayRuntime.currentBaseURL`，不能写死。
    /// 若默认 8787 被同机其他 App（如 Flutter 版 DramaCube）抢占，网关会自动
    /// 改用 8787+1… 的重试端口（见 GatewayServer.run），UI 必须跟随实际端口，
    /// 否则全部请求打到抢占者进程 → 响应壳不符 → 「isn't in the correct format」。
    public static var gatewayBaseURL: String { GatewayRuntime.currentBaseURL }
    /// 网关默认端口（独立可执行入口使用；App 内由 AppSettings.gatewayPort 控制）。
    public static let gatewayPort: Int = 8787
    /// 客户端版本（优先读 Info.plist 的 CFBundleShortVersionString，构建号一并展示）。
    public static let appVersion: String = {
        let d = Bundle.main.infoDictionary
        let ver = d?["CFBundleShortVersionString"] as? String
        let build = d?["CFBundleVersion"] as? String
        if let ver, !ver.isEmpty {
            return build.map { "\(ver) (\($0))" } ?? ver
        }
        return "1.0.2-mac"
    }()
    /// 最低系统版本（已与用户确认为 macOS 14）。
    public static let minMacOS = "14.0"
    /// 品牌主色（红果粉）。
    public static let brandHex = "#FF2D55"
}

/// 网关实际运行端口（进程内共享，跨模块可读）。
///
/// `GatewayServer.run` 绑定成功后写入实际端口；UI/各 Manager 的 baseURL 读取
/// 这里的值，保证端口冲突自动重试后请求仍指向本网关而非抢占者进程。
public enum GatewayRuntime {
    /// 线程安全读写实际端口（读多写一次，用锁即可）。
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _port: Int = AppConfig.gatewayPort

    /// 实际监听端口（未启动时为默认 8787）。
    public static var currentPort: Int {
        lock.lock(); defer { lock.unlock() }
        return _port
    }

    /// 实际网关基址。
    public static var currentBaseURL: String { "http://127.0.0.1:\(currentPort)" }

    /// 绑定成功后登记实际端口（仅网关侧调用）。
    public static func setPort(_ port: Int) {
        lock.lock(); _port = port; lock.unlock()
    }
}
