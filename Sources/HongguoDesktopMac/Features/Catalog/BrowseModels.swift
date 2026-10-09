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

/// 发现页分类（站点路径为最佳努力猜测，解析失败优雅返回空）。
public enum BrowseCategory: String, CaseIterable, Identifiable {
    case recommend, hot, new, sweet, boss, suspense, costume, urban, revenge, mystery
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .recommend: return "推荐"
        case .hot: return "热播"
        case .new: return "最新"
        case .sweet: return "甜宠"
        case .boss: return "霸总"
        case .suspense: return "悬疑"
        case .costume: return "古装"
        case .urban: return "都市"
        case .revenge: return "逆袭"
        case .mystery: return "奇幻"
        }
    }
    /// 对应站点相对路径。
    public var path: String {
        switch self {
        case .recommend: return "/"
        case .hot: return "/hot"
        case .new: return "/latest"
        case .sweet: return "/sweet"
        case .boss: return "/boss"
        case .suspense: return "/suspense"
        case .costume: return "/costume"
        case .urban: return "/urban"
        case .revenge: return "/revenge"
        case .mystery: return "/mystery"
        }
    }
}

/// 排行榜子榜单。
public enum RankTab: String, CaseIterable, Identifiable {
    case hot, `new`, week, month, ending
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .hot: return "热门榜"
        case .new: return "最新榜"
        case .week: return "周榜"
        case .month: return "月榜"
        case .ending: return "收官榜"
        }
    }
    public var path: String {
        switch self {
        case .hot: return "/rank"
        case .new: return "/rank/new"
        case .week: return "/rank/week"
        case .month: return "/rank/month"
        case .ending: return "/rank/ending"
        }
    }
}
