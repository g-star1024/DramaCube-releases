import Foundation
import SwiftData

/// 本地数据仓储：收藏 / 历史（含播放进度）。
///
/// 所有方法在主线程执行（SwiftData mainContext 非线程安全），
/// 返回普通结构体给 UI 层使用。
@MainActor
public final class Repository {
    public static let shared = Repository()

    private var context: ModelContext { PersistenceController.shared.context }

    private init() {}

    // MARK: - 收藏

    public func favorites() -> [FavoriteItem] {
        let desc = SortDescriptor(\FavoriteItem.addedAt, order: .reverse)
        let fd = FetchDescriptor<FavoriteItem>(sortBy: [desc])
        return (try? context.fetch(fd)) ?? []
    }

    public func isFavorite(dramaId: String) -> Bool {
        let pd = FetchDescriptor<FavoriteItem>(predicate: #Predicate { $0.dramaId == dramaId })
        return (try? context.fetch(pd))?.first != nil
    }

    public func toggleFavorite(dramaId: String, title: String, coverURL: String?) {
        let pd = FetchDescriptor<FavoriteItem>(predicate: #Predicate { $0.dramaId == dramaId })
        if let existing = (try? context.fetch(pd))?.first {
            context.delete(existing)
        } else {
            context.insert(FavoriteItem(dramaId: dramaId, title: title, coverURL: coverURL))
        }
        try? context.save()
    }

    public func removeFavorite(dramaId: String) {
        let pd = FetchDescriptor<FavoriteItem>(predicate: #Predicate { $0.dramaId == dramaId })
        if let existing = (try? context.fetch(pd))?.first {
            context.delete(existing)
            try? context.save()
        }
    }

    /// 批量删除收藏。
    public func removeFavorites(dramaIds: Set<String>) {
        guard !dramaIds.isEmpty else { return }
        let all = (try? context.fetch(FetchDescriptor<FavoriteItem>())) ?? []
        for i in all where dramaIds.contains(i.dramaId) { context.delete(i) }
        try? context.save()
    }

    // MARK: - 历史 / 进度

    public func history() -> [HistoryItem] {
        let desc = SortDescriptor(\HistoryItem.updatedAt, order: .reverse)
        let fd = FetchDescriptor<HistoryItem>(sortBy: [desc])
        return (try? context.fetch(fd)) ?? []
    }

    /// 写入 / 更新一条播放进度（按 dramaId+episodeId 去重）。
    public func saveProgress(dramaId: String, episodeId: String, title: String,
                             episodeTitle: String, coverURL: String?,
                             position: Double, duration: Double) {
        let key = "\(dramaId):\(episodeId)"
        let pd = FetchDescriptor<HistoryItem>(predicate: #Predicate { $0.key == key })
        let item: HistoryItem
        if let existing = (try? context.fetch(pd))?.first {
            item = existing
        } else {
            item = HistoryItem(dramaId: dramaId, episodeId: episodeId, title: title, episodeTitle: episodeTitle)
            context.insert(item)
        }
        item.coverURL = coverURL
        item.position = position
        item.duration = duration
        item.updatedAt = .init()
        try? context.save()
    }

    public func clearHistory() {
        let all = (try? context.fetch(FetchDescriptor<HistoryItem>())) ?? []
        for i in all { context.delete(i) }
        try? context.save()
    }

    /// 删除单条历史。
    public func removeHistory(_ item: HistoryItem) {
        context.delete(item)
        try? context.save()
    }

    /// 批量删除历史（按 key）。
    public func removeHistories(keys: Set<String>) {
        guard !keys.isEmpty else { return }
        let all = (try? context.fetch(FetchDescriptor<HistoryItem>())) ?? []
        for i in all where keys.contains(i.key) { context.delete(i) }
        try? context.save()
    }

    /// 读取单条播放进度（续播用）。
    public func progress(dramaId: String, episodeId: String) -> HistoryItem? {
        let key = "\(dramaId):\(episodeId)"
        let pd = FetchDescriptor<HistoryItem>(predicate: #Predicate { $0.key == key })
        return (try? context.fetch(pd))?.first
    }
}
