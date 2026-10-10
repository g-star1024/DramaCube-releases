import Foundation
import Combine
import SwiftUI

/// 用户偏好配置（UserDefaults-backed，跨会话持久化）。
///
/// 设置面板读写此处；播放器、网关、列表读取此处。
/// 使用 `@Published` + 手动读写 UserDefaults（非 View 类型不支持 `@AppStorage`）。
@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - 网关
    /// 本地网关端口（默认 8787）。修改后需重启 App 生效。
    @Published public var gatewayPort: Int { didSet { defaults.set(gatewayPort, forKey: "gatewayPort") } }

    // MARK: - 播放偏好
    /// 默认倍速（0.5 ~ 3.0）。
    @Published public var defaultPlaybackRate: Double { didSet { defaults.set(defaultPlaybackRate, forKey: "defaultPlaybackRate") } }
    /// 自动连播下一集。
    @Published public var autoPlayNext: Bool { didSet { defaults.set(autoPlayNext, forKey: "autoPlayNext") } }
    /// 老板键：按下后隐藏/显示主窗口（默认 Cmd+Shift+H）。
    @Published public var bossKeyEnabled: Bool { didSet { defaults.set(bossKeyEnabled, forKey: "bossKeyEnabled") } }
    /// 起播前自动跳过片头（秒，0 表示不跳）。
    @Published public var introSkipSeconds: Double { didSet { defaults.set(introSkipSeconds, forKey: "introSkipSeconds") } }
    /// 缓冲策略（low/medium/high/ultra）→ AVPlayerItem.preferredForwardBufferDuration 秒数。
    @Published public var bufferStrategy: String { didSet { defaults.set(bufferStrategy, forKey: "bufferStrategy") } }
    /// 下集预缓冲：播放进度达 90% 时预创建下一集资源。
    @Published public var prefetchNextEpisode: Bool { didSet { defaults.set(prefetchNextEpisode, forKey: "prefetchNextEpisode") } }
    /// 默认外部播放器（"builtin"=内置 AVPlayer，或 iina/vlc/mpv/systemDefault）。
    /// 设置后选集播放时自动用该播放器打开，无需每次在播放界面手动切换。
    @Published public var defaultExternalPlayer: String { didSet { defaults.set(defaultExternalPlayer, forKey: "defaultExternalPlayer") } }

    /// 缓冲策略对应的前向缓冲秒数（参考 MoonTVPlus/HLS.js maxBufferLength）。
    public var forwardBufferSeconds: Double {
        switch bufferStrategy {
        case "low": return 15
        case "high": return 60
        case "ultra": return 120
        default: return 30  // medium（推荐）
        }
    }

    // MARK: - 浏览偏好
    /// 首页默认分区（discover/rank/new）。
    @Published public var homeSection: String { didSet { defaults.set(homeSection, forKey: "homeSection") } }
    /// 列表每页数量。
    @Published public var pageSize: Int { didSet { defaults.set(pageSize, forKey: "pageSize") } }
    /// 仅 Wi-Fi 下自动加载封面（省流量）。
    @Published public var loadCoversOnCellular: Bool { didSet { defaults.set(loadCoversOnCellular, forKey: "loadCoversOnCellular") } }

    private init() {
        let d = UserDefaults.standard
        gatewayPort = d.object(forKey: "gatewayPort") == nil ? 8787 : d.integer(forKey: "gatewayPort")
        defaultPlaybackRate = d.object(forKey: "defaultPlaybackRate") == nil ? 1.0 : d.double(forKey: "defaultPlaybackRate")
        autoPlayNext = d.object(forKey: "autoPlayNext") == nil ? true : d.bool(forKey: "autoPlayNext")
        bossKeyEnabled = d.object(forKey: "bossKeyEnabled") == nil ? true : d.bool(forKey: "bossKeyEnabled")
        introSkipSeconds = d.object(forKey: "introSkipSeconds") == nil ? 0 : d.double(forKey: "introSkipSeconds")
        bufferStrategy = d.string(forKey: "bufferStrategy") ?? "medium"
        prefetchNextEpisode = d.object(forKey: "prefetchNextEpisode") == nil ? true : d.bool(forKey: "prefetchNextEpisode")
        defaultExternalPlayer = d.string(forKey: "defaultExternalPlayer") ?? "builtin"
        homeSection = d.object(forKey: "homeSection") == nil ? "discover" : (d.string(forKey: "homeSection") ?? "discover")
        pageSize = d.object(forKey: "pageSize") == nil ? 24 : d.integer(forKey: "pageSize")
        loadCoversOnCellular = d.object(forKey: "loadCoversOnCellular") == nil ? true : d.bool(forKey: "loadCoversOnCellular")
    }
}
