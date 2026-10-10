import Foundation

// MARK: - 全平台统一媒体服务器协议（新架构地基）
// 对标 Cinetry：把 10+ 种异构服务器收敛成一个协议，上层 UI/搜索/播放只面对它。
// 全平台约束：只依赖 Foundation，async/throws，不 import SwiftUI/AppKit。

/// 统一媒体服务器协议。所有数据源（Jellyfin/Emby/WebDAV/AList/Subsonic/
/// audiobookshelf/IPTV/TVBox/红果）都实现它。
public protocol MediaServerProtocol: Sendable {
    /// 服务器配置（含 key/kind/地址/凭据）。
    var config: MediaServerConfig { get }

    // MARK: 探测
    /// 连接测试 + 能力探测（对标 Cinetry 实时连接状态检查）。
    /// 返回在线状态/延迟/版本/转码/搜索/进度上报能力/鉴权状态。
    func probe() async -> ServerCapability

    // MARK: 媒体库
    /// 拉取媒体库列表（电影库/剧集库/音乐库/直播...）。
    func libraries() async throws -> [MediaLibrary]

    /// 拉某个库的内容（分页，对标「不扫库只拉当前页」）。
    func items(library: String, page: Int, limit: Int) async throws -> MediaPage

    // MARK: 详情
    /// 详情（含剧集列表、音轨、字幕、nfo 元数据）。
    func detail(item: String) async throws -> MediaDetail

    // MARK: 播放
    /// 播放地址解析（直链 / 转码HLS / 需网关代理）。
    /// quality 为 nil 时按服务器默认（通常原画/自动）。
    func playback(item: String, quality: Quality?) async throws -> PlaybackSource

    // MARK: 搜索
    /// 本服务器内搜索（跨服务器聚合由 Registry 并发调各源实现）。
    func search(query: String, filter: SearchFilter) async throws -> [MediaItem]

    // MARK: 进度上报
    /// 播放进度上报（对标 Emby /emby/Sessions/Playing、Subsonic /rest/scrobble）。
    /// 不支持的服务器空实现即可，由 Registry 决定是否同时本地持久化。
    func reportProgress(item: String, position: TimeInterval, state: PlayState) async

    // MARK: - 可选能力（协议扩展给默认实现，适配器按需覆写）

    /// 继续观看（该服务器最近的播放进度条目）。默认空。
    func continueWatching(limit: Int) async throws -> [MediaItem]

    /// 最新入库（该服务器各库按时间最新）。默认空。
    func recentlyAdded(limit: Int) async throws -> [MediaItem]

    /// 弹幕拉取（按播放条目+时间轴）。默认空，仅支持的源覆写。
    func danmaku(item: String) async throws -> [DanmakuEntry]

    /// 离线缓存地址（可下载的直链）。默认不支持抛错。
    func downloadURL(item: String) async throws -> URL

    /// 家长控制/内容分级过滤。默认不过滤。
    func isAllowed(item: MediaItem, pin: String?) async -> Bool
}

// MARK: - 默认实现（可选能力）
public extension MediaServerProtocol {
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func recentlyAdded(limit: Int) async throws -> [MediaItem] { [] }
    func danmaku(item: String) async throws -> [DanmakuEntry] { [] }
    func downloadURL(item: String) async throws -> URL { throw MediaServerError.unsupported }
    func isAllowed(item: MediaItem, pin: String?) async -> Bool { true }
}

/// 弹幕条目。
public struct DanmakuEntry: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var time: TimeInterval   // 出现时间轴（秒）
    public var text: String
    public var color: String?       // #RRGGBB
    public var mode: Int            // 0滚动 1顶部 2底部（对齐 danMuArea）

    public init(id: String, time: TimeInterval, text: String, color: String? = nil, mode: Int = 0) {
        self.id = id; self.time = time; self.text = text; self.color = color; self.mode = mode
    }
}

/// 统一错误。
public enum MediaServerError: Error, Sendable {
    case unsupported
    case notFound
    case unauthorized
    case network(String)
    case parse(String)
    case transcodingUnavailable
}
