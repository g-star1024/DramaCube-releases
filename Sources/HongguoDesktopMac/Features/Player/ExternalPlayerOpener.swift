import Foundation
import AppKit

/// 外部播放器选项。
public enum ExternalPlayerApp: String, CaseIterable, Identifiable {
    case iina, vlc, mpv, systemDefault
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .iina: return "IINA"
        case .vlc: return "VLC"
        case .mpv: return "mpv"
        case .systemDefault: return "系统默认播放器"
        }
    }
    /// App bundle id（用于检测是否安装）。
    var bundleID: String? {
        switch self {
        case .iina: return "com.colliderli.iina"
        case .vlc: return "org.videolan.vlc"
        case .mpv: return "io.mpv"
        case .systemDefault: return nil
        }
    }
    /// URL scheme（备用唤起方式）。
    var schemeHandler: ((URL) -> URL?)? {
        switch self {
        case .iina: return { URL(string: "iina://weblink?url=\($0.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.absoluteString)") }
        case .vlc: return { URL(string: "vlc://\($0.absoluteString)") }
        default: return nil
        }
    }
}

/// 用外部播放器打开视频地址。
public enum ExternalPlayerOpener {

    /// 检测某播放器是否已安装。
    public static func isInstalled(_ app: ExternalPlayerApp) -> Bool {
        guard let bid = app.bundleID else { return true }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) != nil
    }

    /// 已安装的外部播放器列表（供菜单动态展示）。
    public static var installedApps: [ExternalPlayerApp] {
        ExternalPlayerApp.allCases.filter { isInstalled($0) }
    }

    /// 打开：优先按 bundle id 以指定 App 打开 URL，失败退回 scheme，再退回系统默认。
    public static func open(url: URL, app: ExternalPlayerApp) {
        switch app {
        case .systemDefault:
            NSWorkspace.shared.open(url)
            return
        default:
            break
        }
        // 1) 按 bundle id 定位 App，以该 App 打开 URL
        if let bid = app.bundleID,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { _, err in
                if err != nil, let schemeURL = app.schemeHandler?(url) {
                    NSWorkspace.shared.open(schemeURL)
                }
            }
            return
        }
        // 2) scheme 唤起
        if let schemeURL = app.schemeHandler?(url) {
            NSWorkspace.shared.open(schemeURL)
            return
        }
        // 3) 退回系统默认
        NSWorkspace.shared.open(url)
    }
}
