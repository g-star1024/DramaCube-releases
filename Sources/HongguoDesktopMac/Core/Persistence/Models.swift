import Foundation
import SwiftData

/// 收藏条目。
@Model
public final class FavoriteItem {
    @Attribute(.unique) public var dramaId: String
    public var title: String
    public var coverURL: String?
    public var addedAt: Date

    public init(dramaId: String, title: String, coverURL: String? = nil, addedAt: Date = .init()) {
        self.dramaId = dramaId
        self.title = title
        self.coverURL = coverURL
        self.addedAt = addedAt
    }
}

/// 历史 / 播放进度条目（看过哪些 + 每集看到哪）。
@Model
public final class HistoryItem {
    /// 剧集唯一键：dramaId + ":" + episodeId。
    @Attribute(.unique) public var key: String
    public var dramaId: String
    public var episodeId: String
    public var title: String
    public var episodeTitle: String
    public var coverURL: String?
    /// 播放位置（秒）。
    public var position: Double
    /// 总时长（秒，0 表示未知）。
    public var duration: Double
    public var updatedAt: Date

    public init(dramaId: String, episodeId: String, title: String, episodeTitle: String,
                coverURL: String? = nil, position: Double = 0, duration: Double = 0,
                updatedAt: Date = .init()) {
        self.key = "\(dramaId):\(episodeId)"
        self.dramaId = dramaId
        self.episodeId = episodeId
        self.title = title
        self.episodeTitle = episodeTitle
        self.coverURL = coverURL
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
    }
}
