import Foundation
import SwiftUI
import HongguoCore

/// 集数懒回填器（v1.0.5）。
///
/// 背景：站点数据源集数天然残缺——
///  - 首页 `_ROUTER_DATA` 36 部中仅 27 部带 `episode_cnt`（顶部精选区块无此字段）；
///  - 排行榜 / 搜索页为 SSR DOM 卡片，页面里完全没有集数信息。
/// 导致列表卡片「有的显示集数、有的不显示」（2026-10-09 用户反馈）。
///
/// 方案（用户拍板）：对缺集数的条目用详情接口**低并发后台补全**，
/// 结果随缓存永久生效；顺带预热详情缓存（点开详情秒开）。
@MainActor
public final class CountBackfiller: ObservableObject {
    public static let shared = CountBackfiller()

    /// in-flight 去重：items 变化会反复触发回填，同一 id 并发期只抓一次。
    private var inFlight: Set<String> = []
    /// 失败过的 id（本会话内不再重试，避免坏数据反复打网络）。
    private var failedIds: Set<String> = []

    /// 并发上限：详情页是整页 SSR（约 350KB/次），两路并发对网关与带宽都温和。
    private let concurrency = 2

    private init() {}

    /// 回填 dramas 中缺集数者；每补到一个通过 `onCount(id, count)` 回调。
    /// - Parameter dramas: 候选列表（内部自动过滤已有集数 / 进行中 / 已失败项）。
    public func backfill(_ dramas: [Drama], onCount: @escaping (String, Int) -> Void) async {
        let missing = dramas.filter {
            $0.episodeCount == nil && !inFlight.contains($0.id) && !failedIds.contains($0.id)
        }
        guard !missing.isEmpty else { return }
        for d in missing { inFlight.insert(d.id) }
        defer { for d in missing { inFlight.remove(d.id) } }

        var iterator = missing.makeIterator()
        await withTaskGroup(of: (id: String, count: Int?).self) { group in
            for _ in 0..<concurrency {
                if let d = iterator.next() {
                    group.addTask { await Self.fetchCount(for: d) }
                }
            }
            while let (id, count) = await group.next() {
                if let count, count > 0 {
                    onCount(id, count)
                } else {
                    failedIds.insert(id)
                }
                if let d = iterator.next() {
                    group.addTask { await Self.fetchCount(for: d) }
                }
            }
        }
    }

    /// 单条抓取：详情本地缓存优先（与 DetailView 共用 "detail:<id>" 键，命中零网络）。
    private nonisolated static func fetchCount(for drama: Drama) async -> (id: String, count: Int?) {
        let key = "detail:\(drama.id)"
        if let cached = await DiskCache.shared.read(DramaDetail.self, key: key) {
            return (drama.id, cached.drama.episodeCount)
        }
        guard let detail = try? await CatalogService.shared.detail(id: drama.id) else {
            return (drama.id, nil)
        }
        await DiskCache.shared.write(detail, key: key)
        return (drama.id, detail.drama.episodeCount)
    }
}

extension Drama {
    /// 返回替换集数后的副本（Drama 字段全为 let，需整体重建）。
    public func withEpisodeCount(_ count: Int) -> Drama {
        Drama(id: id, title: title, coverURL: coverURL, description: description,
              episodeCount: count, tags: tags, category: category,
              updateStatus: updateStatus, shareURL: shareURL)
    }
}
