import Foundation

// MARK: - 全平台统一媒体模型
// 约束（全平台方案）：只依赖 Foundation，全部 Codable + Sendable，
// 不 import SwiftUI/AppKit —— 同一套模型可原样编译到 iOS，或平移到 KMP/Rust。

/// 媒体服务器类型。
public enum MediaServerKind: String, Codable, Sendable, CaseIterable {
    case jellyfin, emby, webdav, mount, alist, openlist
    case subsonic, navidrome, audiobookshelf
    case tvbox, iptv, hongguo
}

/// 媒体大类（视频/音乐/听书/直播/短剧）。
public enum MediaKind: String, Codable, Sendable {
    case movie, series, episode, music, album, artist, audiobook, live, shortDrama, photo, unknown
}

/// 画质偏好。
public enum Quality: String, Codable, Sendable {
    case auto, original, p1080, p720, p480, audioOnly
}

/// 单条媒体（列表/搜索/继续观看都用它）。
public struct MediaItem: Codable, Sendable, Identifiable, Hashable {
    public var id: String                 // 服务器内唯一 id（已含来源前缀，见 sourceKey）
    public var sourceKey: String          // 来源服务器 key（聚合时区分来源）
    public var kind: MediaKind
    public var title: String
    public var subTitle: String?          // 副标题/演员/专辑等
    public var poster: String?            // 封面 URL（可能需经 image-proxy）
    public var backdrop: String?          // 背景大图
    public var year: String?
    public var rate: String?              // 评分
    public var duration: TimeInterval?    // 秒
    public var extra: [String: String]    // 服务器特有扩展（如 path、容器 id）

    public init(id: String, sourceKey: String, kind: MediaKind, title: String,
                subTitle: String? = nil, poster: String? = nil, backdrop: String? = nil,
                year: String? = nil, rate: String? = nil, duration: TimeInterval? = nil,
                extra: [String: String] = [:]) {
        self.id = id; self.sourceKey = sourceKey; self.kind = kind; self.title = title
        self.subTitle = subTitle; self.poster = poster; self.backdrop = backdrop
        self.year = year; self.rate = rate; self.duration = duration; self.extra = extra
    }
}

/// 媒体库（一个服务器可有多个库：电影库/剧集库/音乐库/直播...）。
public struct MediaLibrary: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var sourceKey: String
    public var title: String
    public var kind: MediaKind
    public var count: Int?
    public var icon: String?

    public init(id: String, sourceKey: String, title: String, kind: MediaKind,
                count: Int? = nil, icon: String? = nil) {
        self.id = id; self.sourceKey = sourceKey; self.title = title
        self.kind = kind; self.count = count; self.icon = icon
    }
}

/// 分页结果（对标 Cinetry「不扫库只拉当前页」）。
public struct MediaPage: Codable, Sendable {
    public var items: [MediaItem]
    public var page: Int
    public var hasMore: Bool
    public var total: Int?

    public init(items: [MediaItem], page: Int, hasMore: Bool, total: Int? = nil) {
        self.items = items; self.page = page; self.hasMore = hasMore; self.total = total
    }
}

/// 字幕轨。
public struct SubtitleTrack: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var language: String?
    public var format: String?           // srt/ass/vtt
    public var url: String?              // 外挂字幕地址（nil=内嵌）
    public var isEmbedded: Bool

    public init(id: String, title: String, language: String? = nil, format: String? = nil,
                url: String? = nil, isEmbedded: Bool = false) {
        self.id = id; self.title = title; self.language = language
        self.format = format; self.url = url; self.isEmbedded = isEmbedded
    }
}

/// 音轨。
public struct AudioTrack: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var language: String?
    public var channels: Int?

    public init(id: String, title: String, language: String? = nil, channels: Int? = nil) {
        self.id = id; self.title = title; self.language = language; self.channels = channels
    }
}

/// 详情（含剧集列表、音轨字幕、nfo 元数据）。
public struct MediaDetail: Codable, Sendable {
    public var item: MediaItem
    public var overview: String?
    public var episodes: [MediaItem]     // 剧集/章节/曲目
    public var subtitles: [SubtitleTrack]
    public var audioTracks: [AudioTrack]
    public var actors: [String]
    public var directors: [String]
    public var genres: [String]
    public var extra: [String: String]

    public init(item: MediaItem, overview: String? = nil, episodes: [MediaItem] = [],
                subtitles: [SubtitleTrack] = [], audioTracks: [AudioTrack] = [],
                actors: [String] = [], directors: [String] = [], genres: [String] = [],
                extra: [String: String] = [:]) {
        self.item = item; self.overview = overview; self.episodes = episodes
        self.subtitles = subtitles; self.audioTracks = audioTracks
        self.actors = actors; self.directors = directors; self.genres = genres
        self.extra = extra
    }
}

/// 播放来源：直链 / 服务端转码 HLS / 需本网关代理。
public struct PlaybackSource: Codable, Sendable {
    public enum Delivery: String, Codable, Sendable { case direct, transcodeHLS, proxied }
    public var delivery: Delivery
    public var url: URL
    public var headers: [String: String] // 播放所需请求头（Referer/UA/Cookie）
    public var subtitles: [SubtitleTrack]
    public var audioTracks: [AudioTrack]
    public var startPosition: TimeInterval? // 续看起点（秒）
    public var drm: String?                 // 预留 DRM 标识

    public init(delivery: Delivery, url: URL, headers: [String: String] = [:],
                subtitles: [SubtitleTrack] = [], audioTracks: [AudioTrack] = [],
                startPosition: TimeInterval? = nil, drm: String? = nil) {
        self.delivery = delivery; self.url = url; self.headers = headers
        self.subtitles = subtitles; self.audioTracks = audioTracks
        self.startPosition = startPosition; self.drm = drm
    }
}

/// 服务器能力（probe 探测返回，UI 据此显示可用特性）。
public struct ServerCapability: Codable, Sendable {
    public var online: Bool
    public var latencyMs: Int
    public var serverVersion: String?
    public var canTranscode: Bool
    public var canSearch: Bool
    public var canReportProgress: Bool
    public var needsAuth: Bool
    public var authenticated: Bool
    public var message: String?           // 错误/提示

    public init(online: Bool, latencyMs: Int = 0, serverVersion: String? = nil,
                canTranscode: Bool = false, canSearch: Bool = true,
                canReportProgress: Bool = false, needsAuth: Bool = false,
                authenticated: Bool = true, message: String? = nil) {
        self.online = online; self.latencyMs = latencyMs; self.serverVersion = serverVersion
        self.canTranscode = canTranscode; self.canSearch = canSearch
        self.canReportProgress = canReportProgress; self.needsAuth = needsAuth
        self.authenticated = authenticated; self.message = message
    }
}

/// 搜索过滤。
public struct SearchFilter: Codable, Sendable {
    public var kinds: [MediaKind]?
    public var year: String?
    public var actor: String?
    public var director: String?

    public init(kinds: [MediaKind]? = nil, year: String? = nil,
                actor: String? = nil, director: String? = nil) {
        self.kinds = kinds; self.year = year; self.actor = actor; self.director = director
    }
}

/// 播放状态（进度上报用）。
public enum PlayState: String, Codable, Sendable { case playing, paused, stopped, finished }

/// 服务器配置（持久化，添加服务器时填）。
public struct MediaServerConfig: Codable, Sendable, Identifiable, Hashable {
    public var id: String                 // key
    public var kind: MediaServerKind
    public var name: String
    public var baseURL: String
    public var username: String?
    public var password: String?          // 存钥匙串，模型里仅内存用
    public var token: String?
    public var enabled: Bool
    public var extra: [String: String]

    public init(id: String, kind: MediaServerKind, name: String, baseURL: String,
                username: String? = nil, password: String? = nil, token: String? = nil,
                enabled: Bool = true, extra: [String: String] = [:]) {
        self.id = id; self.kind = kind; self.name = name; self.baseURL = baseURL
        self.username = username; self.password = password; self.token = token
        self.enabled = enabled; self.extra = extra
    }
}
