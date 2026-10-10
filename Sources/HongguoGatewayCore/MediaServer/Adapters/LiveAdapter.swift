import Foundation
import HongguoCore

// MARK: - IPTV 直播适配器（包现有 LiveEngine 为协议实现）
// 直播按「分组=库、频道=条目」建模。

public struct LiveAdapter: MediaServerProtocol {
    public let config: MediaServerConfig

    public init(source: LiveEngine.SourceInfo) {
        config = MediaServerConfig(
            id: "iptv|\(source.id)",
            kind: .iptv,
            name: source.name,
            baseURL: source.url,
            enabled: source.enabled,
            extra: ["sourceId": source.id]
        )
    }

    public func probe() async -> ServerCapability {
        let sid = config.extra["sourceId"] ?? ""
        let t0 = Date()
        let count = await LiveEngine.shared.testSource(id: sid)
        let ok = count > 0
        return ServerCapability(
            online: ok, latencyMs: Int(Date().timeIntervalSince(t0) * 1000),
            canSearch: true, canReportProgress: false,
            message: ok ? nil : "直播源不可用或无频道"
        )
    }

    public func libraries() async throws -> [MediaLibrary] {
        let channels = await LiveEngine.shared.channels()
        // 按分组聚合为库
        let groups = Dictionary(grouping: channels, by: { $0.group })
        return groups.keys.sorted().map {
            MediaLibrary(id: $0, sourceKey: config.id, title: $0,
                         kind: .live, count: groups[$0]?.count)
        }
    }

    public func items(library: String, page: Int, limit: Int) async throws -> MediaPage {
        let channels = await LiveEngine.shared.channels().filter { $0.group == library }
        let items = channels.map { Self.toItem($0, sourceKey: config.id) }
        return MediaPage(items: items, page: page, hasMore: false, total: items.count)
    }

    public func detail(item: String) async throws -> MediaDetail {
        guard let ch = await channel(for: item) else { throw MediaServerError.notFound }
        return MediaDetail(item: Self.toItem(ch, sourceKey: config.id))
    }

    public func playback(item: String, quality: Quality?) async throws -> PlaybackSource {
        guard let ch = await channel(for: item), let url = URL(string: ch.url) else {
            throw MediaServerError.notFound
        }
        // 直播 m3u8 经本网关代理（统一 UA + 重写分片）
        let delivery: PlaybackSource.Delivery = ch.url.contains(".m3u8") ? .proxied : .direct
        let finalURL: URL
        if delivery == .proxied, let base = GatewayBase.url {
            var comp = URLComponents(url: base.appendingPathComponent("/api/live/stream"), resolvingAgainstBaseURL: false)!
            comp.queryItems = [URLQueryItem(name: "url", value: ch.url)]
            finalURL = comp.url ?? url
        } else {
            finalURL = url
        }
        return PlaybackSource(delivery: delivery, url: finalURL)
    }

    public func search(query: String, filter: SearchFilter) async throws -> [MediaItem] {
        let q = query.lowercased()
        return await LiveEngine.shared.channels()
            .filter { $0.name.lowercased().contains(q) }
            .map { Self.toItem($0, sourceKey: config.id) }
    }

    public func reportProgress(item: String, position: TimeInterval, state: PlayState) async {}

    private func channel(for id: String) async -> LiveEngine.Channel? {
        await LiveEngine.shared.channels().first { $0.id == id }
    }

    static func toItem(_ c: LiveEngine.Channel, sourceKey: String) -> MediaItem {
        MediaItem(id: c.id, sourceKey: sourceKey, kind: .live,
                  title: c.name, subTitle: c.group, poster: c.logo,
                  extra: ["group": c.group, "url": c.url])
    }
}
