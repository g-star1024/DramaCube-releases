import Foundation

/// 浏览筛选芯片（用于发现/探索的分类选择）。
public struct BrowseChip: Identifiable, Hashable {
    public let id: String
    public let title: String
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// 发现页分类（2026-10 站点改版后的真实路由）。
public enum BrowseCategory: String, CaseIterable, Identifiable {
    case recommend, real, comic, ai
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .recommend: return "推荐"
        case .real: return "真人剧"
        case .comic: return "漫剧"
        case .ai: return "AI剧"
        }
    }
    /// 对应站点相对路径。
    public var path: String {
        switch self {
        case .recommend: return "/"
        case .real: return "/category/real-drama"
        case .comic: return "/category/comic-drama"
        case .ai: return "/category/ai-drama"
        }
    }
}

/// 排行榜子榜单（站点真实路由，支持 ?page= 分页）。
public enum RankTab: String, CaseIterable, Identifiable {
    case hot, real, comic, ai
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .hot: return "热播榜"
        case .real: return "真人剧榜"
        case .comic: return "漫剧榜"
        case .ai: return "AI剧榜"
        }
    }
    public var path: String {
        switch self {
        case .hot: return "/rank/hot-drama"
        case .real: return "/rank/hot-real-drama"
        case .comic: return "/rank/hot-comic-drama"
        case .ai: return "/rank/hot-ai-drama"
        }
    }
}

/// 探索页全量类目（分类页带筛选与分页）。
public enum ExploreTab: String, CaseIterable, Identifiable {
    case short, real, comic, ai
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .short: return "短剧"
        case .real: return "真人剧"
        case .comic: return "漫剧"
        case .ai: return "AI剧"
        }
    }
    public var path: String {
        switch self {
        case .short: return "/category?tab=1&sort_type=1"
        case .real: return "/category/real-drama"
        case .comic: return "/category/comic-drama"
        case .ai: return "/category/ai-drama"
        }
    }
}
