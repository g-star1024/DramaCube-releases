import Foundation
import HongguoCore

// MARK: - 红果短剧内置适配器（M4）
// 把红果短剧站包装成内置 MediaServer，纳入统一抽象层：
// 参与聚合搜索/聚合首页/服务器一键切换，与 TVBox/NAS/IPTV/Emby 等并列。
// 库 = 红果各榜单/类目（热门/最新/分类），条目 = 短剧。

public struct HongguoAdapter: MediaServerProtocol {
    public let config: MediaServerConfig

    public init() {
        config = MediaServerConfig(
            id: "hongguo|builtin",
            kind: .hongguo,
            name: "红果短剧",
            baseURL: "https://hongguoduanju.com",
            enabled: true
        )
    }

    // MARK: 探测
    public func probe() async -> ServerCapability {
        let t0 = Date()
        do {
            _ = try await HongguoClient.shared.catalog(path: "/rank/hot-drama", page: 1)
            return ServerCapability(
                online: true, latencyMs: Int(Date().timeIntervalSince(t0) * 1000),
                canTranscode: false, canSearch: true, canReportProgress: false
            )
        } catch {
            return ServerCapability(online: false, message: "红果站不可达：\(error.localizedDescription)")
        }
    }

    // MARK: 库（红果榜单/类目）
    public func libraries() async throws -> [MediaLibrary] {
        [
            MediaLibrary(id: "hot", sourceKey: config.id, title: "热门榜", kind: .shortDrama, icon: "flame"),
            MediaLibrary(id: "new", sourceKey: config.id, title: "最新短剧", kind: .shortDrama, icon: "sparkles"),
            MediaLibrary(id: "real", sourceKey: config.id, title: "真人短剧", kind: .shortDrama, icon: "person.2"),
            MediaLibrary(id: "comic", sourceKey: config.id, title: "漫剧", kind: .shortDrama, icon: "book"),
            MediaLibrary(id: "ai", sourceKey: config.id, title: "AI 短剧", kind: .shortDrama, icon: "cpu")
        ]
    }

    public func items(library: String, page: Int, limit: Int) async throws -> MediaPage {
        let path = Self.catalogPath(for: library)
        let dramas = try await HongguoClient.shared.catalog(path: path, page: page)
        let items = dramas.map { Self.toItem($0, sourceKey: config.id) }
        // 红果列表无显式分页总数，按返回条数估算 hasMore
        return MediaPage(items: items, page: page, hasMore: dramas.count >= 10, total: nil)
    }

    // MARK: 详情
    public func detail(item: String) async throws -> MediaDetail {
        let d = try await HongguoClient.shared.fetchDetail(id: item)
        let episodes = d.episodes.map { ep in
            MediaItem(id: "\(item)#\(ep.id)", sourceKey: config.id, kind: .episode,
                      title: ep.title, subTitle: "第 \(ep.index) 集",
                      duration: ep.duration.map(TimeInterval.init),
                      extra: ["seriesId": item, "vid": ep.id, "index": String(ep.index)])
        }
        return MediaDetail(
            item: Self.toItem(d.drama, sourceKey: config.id),
            overview: d.drama.description,
            episodes: episodes,
            genres: d.drama.tags
        )
    }

    // MARK: 播放（经本网关 Range 透传代理，剥离 Referer 防 403）
    public func playback(item: String, quality: Quality?) async throws -> PlaybackSource {
        // item 形如 "seriesId#vid"
        let parts = item.split(separator: "#")
        guard parts.count == 2, let base = GatewayBase.url else {
            throw MediaServerError.notFound
        }
        let sid = String(parts[0]), vid = String(parts[1])
        let proxied = base.appendingPathComponent("api/stream/\(sid)/\(vid)")
        return PlaybackSource(delivery: .proxied, url: proxied)
    }

    // MARK: 搜索
    public func search(query: String, filter: SearchFilter) async throws -> [MediaItem] {
        let dramas = try await HongguoClient.shared.search(query: query)
        return dramas
            .filter { !HongguoClient.isActorCard($0) }
            .map { Self.toItem($0, sourceKey: config.id) }
    }

    public func reportProgress(item: String, position: TimeInterval, state: PlayState) async {}

    // MARK: 最新入库（用「最新短剧」库充当）
    public func recentlyAdded(limit: Int) async throws -> [MediaItem] {
        let dramas = try await HongguoClient.shared.catalog(path: "/rank/hot-drama", page: 1)
        return dramas.prefix(limit).map { Self.toItem($0, sourceKey: config.id) }
    }

    // MARK: - 工具

    /// 库 id → 红果 catalog 路径。
    static func catalogPath(for library: String) -> String {
        switch library {
        case "hot": return "/rank/hot-drama"
        case "new": return "/rank/new-drama"
        case "real": return "/category/real-drama"
        case "comic": return "/category/comic-drama"
        case "ai": return "/category/ai-drama"
        default: return "/rank/hot-drama"
        }
    }

    static func toItem(_ d: Drama, sourceKey: String) -> MediaItem {
        MediaItem(
            id: d.id, sourceKey: sourceKey, kind: .shortDrama,
            title: d.title, subTitle: d.updateStatus ?? d.category,
            poster: d.coverURL,
            extra: [
                "episodeCount": d.episodeCount.map(String.init) ?? "",
                "tags": d.tags.joined(separator: ",")
            ]
        )
    }
}
