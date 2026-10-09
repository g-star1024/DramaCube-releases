import Foundation

/// 剧集（短剧）领域模型 —— 对应红果分享落地页解析出的结构。
public struct Drama: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let coverURL: String?
    public let description: String?
    public let episodeCount: Int?
    public let tags: [String]
    public let category: String?
    public let updateStatus: String?   // 如 "更新至 80 集" / "全集"
    public let shareURL: String?       // 原始 novelquickapp.com/s/<id>/ 落地页

    public init(id: String, title: String, coverURL: String? = nil, description: String? = nil,
                episodeCount: Int? = nil, tags: [String] = [], category: String? = nil,
                updateStatus: String? = nil, shareURL: String? = nil) {
        self.id = id
        self.title = title
        self.coverURL = coverURL
        self.description = description
        self.episodeCount = episodeCount
        self.tags = tags
        self.category = category
        self.updateStatus = updateStatus
        self.shareURL = shareURL
    }
}

/// 单集信息。
public struct Episode: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let index: Int
    public let title: String
    public let playURL: String?        // 直链（经网关剥离 Referer 后可播）
    public let duration: Int?          // 秒

    public init(id: String, index: Int, title: String, playURL: String? = nil, duration: Int? = nil) {
        self.id = id
        self.index = index
        self.title = title
        self.playURL = playURL
        self.duration = duration
    }
}

/// 详情页：剧集 + 分集列表。
public struct DramaDetail: Codable, Sendable {
    public let drama: Drama
    public let episodes: [Episode]
    public init(drama: Drama, episodes: [Episode]) {
        self.drama = drama
        self.episodes = episodes
    }
}

/// 列表查询返回。
public struct CatalogPage: Codable, Sendable {
    public let items: [Drama]
    public let page: Int
    public let hasMore: Bool
    public init(items: [Drama], page: Int, hasMore: Bool) {
        self.items = items
        self.page = page
        self.hasMore = hasMore
    }
}

/// 统一的网关对外响应壳（前端只认这个）。
public struct GatewayEnvelope<T: Codable & Sendable>: Codable, Sendable {
    public let ok: Bool
    public let data: T?
    public let error: String?
    public init(ok: Bool, data: T? = nil, error: String? = nil) {
        self.ok = ok
        self.data = data
        self.error = error
    }
}
