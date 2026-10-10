import Foundation
import HongguoCore

// MARK: - TVBox·CMS 适配器（包现有 TVBoxEngine 为协议实现）
// 一个 TVBox 订阅可含多个采集站点；每个 Site 注册为一个逻辑服务器。

public struct TVBoxAdapter: MediaServerProtocol {
    public let config: MediaServerConfig
    private let siteKey: String

    public init(site: TVBoxEngine.Site) {
        siteKey = site.key
        config = MediaServerConfig(
            id: "tvbox|\(site.key)",
            kind: .tvbox,
            name: site.name,
            baseURL: site.api,
            extra: ["siteKey": site.key]
        )
    }

    public func probe() async -> ServerCapability {
        guard let site = await Self.site(for: siteKey) else {
            return ServerCapability(online: false, message: "site not found")
        }
        let r = await TVBoxEngine.shared.test(site: site)
        return ServerCapability(
            online: r.ok, latencyMs: r.latencyMs,
            canSearch: true, canReportProgress: false,
            message: r.error
        )
    }

    public func libraries() async throws -> [MediaLibrary] {
        let cats = await TVBoxEngine.shared.categories(siteKey: siteKey)
        return cats.map {
            MediaLibrary(id: "\($0.typeId)", sourceKey: config.id,
                         title: $0.name, kind: .series)
        }
    }

    public func items(library: String, page: Int, limit: Int) async throws -> MediaPage {
        let typeId = Int(library)
        let dramas = try await TVBoxEngine.shared.latest(siteKey: siteKey, page: page, typeId: typeId)
        let items = dramas.map { Self.toItem($0, sourceKey: config.id) }
        return MediaPage(items: items, page: page, hasMore: !dramas.isEmpty)
    }

    public func detail(item: String) async throws -> MediaDetail {
        let d = try await TVBoxEngine.shared.detail(siteKey: siteKey, vodId: item)
        let episodes = d.episodes.map {
            MediaItem(id: "\(item)#ep\($0.index)", sourceKey: config.id, kind: .episode,
                      title: $0.title, subTitle: nil,
                      duration: $0.duration.map(TimeInterval.init),
                      extra: ["vodId": item, "episodeIndex": "\($0.index)"])
        }
        return MediaDetail(
            item: Self.toItem(d.drama, sourceKey: config.id),
            overview: d.drama.description,
            episodes: episodes,
            genres: d.drama.tags
        )
    }

    public func playback(item: String, quality: Quality?) async throws -> PlaybackSource {
        // item 形如 "vodId#ep3" 或纯 vodId（默认第 1 集）
        let (vodId, epIdx) = Self.parseEpisodeRef(item)
        let urlStr = try await TVBoxEngine.shared.resolvePlayURL(
            siteKey: siteKey, vodId: vodId, episodeIndex: epIdx)
        guard let url = URL(string: urlStr) else { throw MediaServerError.parse("bad play url") }
        // m3u8 走本网关代理（防盗链+重写分片），其余直链
        let delivery: PlaybackSource.Delivery = urlStr.contains(".m3u8") ? .proxied : .direct
        return PlaybackSource(delivery: delivery, url: url)
    }

    public func search(query: String, filter: SearchFilter) async throws -> [MediaItem] {
        let dramas = try await TVBoxEngine.shared.search(siteKey: siteKey, query: query)
        return dramas.map { Self.toItem($0, sourceKey: config.id) }
    }

    public func reportProgress(item: String, position: TimeInterval, state: PlayState) async {
        // TVBox 采集站无进度上报，本地由 ProgressStore 负责
    }

    // MARK: - 辅助

    private static func site(for key: String) async -> TVBoxEngine.Site? {
        await TVBoxEngine.shared.allSites().first { $0.key == key }
    }

    static func toItem(_ d: Drama, sourceKey: String) -> MediaItem {
        MediaItem(
            id: d.id, sourceKey: sourceKey,
            kind: d.episodeCount == 1 ? .movie : .series,
            title: d.title, subTitle: d.updateStatus,
            poster: d.coverURL, year: nil, rate: nil,
            extra: ["category": d.category ?? ""]
        )
    }

    static func parseEpisodeRef(_ ref: String) -> (vodId: String, episodeIndex: Int) {
        guard let hash = ref.firstIndex(of: "#") else { return (ref, 1) }
        let vodId = String(ref[..<hash])
        let tail = String(ref[ref.index(after: hash)...])   // "ep3"
        let idx = Int(tail.dropFirst(2)) ?? 1
        return (vodId, idx)
    }
}
