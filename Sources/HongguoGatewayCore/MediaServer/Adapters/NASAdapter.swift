import Foundation
import HongguoCore

// MARK: - WebDAV/mount（NAS）适配器（包现有 NASEngine 为协议实现）

public struct NASAdapter: MediaServerProtocol {
    public let config: MediaServerConfig
    private let libraryId: String

    public init(library: NASEngine.Library) {
        libraryId = library.id
        config = MediaServerConfig(
            id: "nas|\(library.id)",
            kind: library.type == .webdav ? .webdav : .mount,
            name: library.name,
            baseURL: library.baseURL,
            username: library.username, password: library.password,
            enabled: library.enabled,
            extra: ["libraryId": library.id, "type": library.type.rawValue]
        )
    }

    public func probe() async -> ServerCapability {
        let r = await NASEngine.shared.test(id: libraryId)
        return ServerCapability(
            online: r.ok, latencyMs: r.latencyMs,
            canSearch: false, canReportProgress: false,
            message: r.ok ? nil : r.error
        )
    }

    public func libraries() async throws -> [MediaLibrary] {
        // NAS 把「根目录」当唯一库，逐层 browse
        [MediaLibrary(id: "/", sourceKey: config.id, title: config.name, kind: .series)]
    }

    public func items(library: String, page: Int, limit: Int) async throws -> MediaPage {
        let path = library.isEmpty ? "/" : library
        let dramas = try await NASEngine.shared.browse(id: libraryId, path: path)
        let items = dramas.map { Self.toItem($0, sourceKey: config.id, path: path) }
        return MediaPage(items: items, page: page, hasMore: false)
    }

    public func detail(item: String) async throws -> MediaDetail {
        // item 编码为目录路径（extra["path"]）
        let d = try await NASEngine.shared.detail(id: libraryId, dirPath: item)
        let episodes = d.episodes.map {
            MediaItem(id: $0.playURL ?? "\(item)/\($0.title)", sourceKey: config.id,
                      kind: .episode, title: $0.title,
                      duration: $0.duration.map(TimeInterval.init),
                      extra: ["path": $0.playURL ?? ""])
        }
        return MediaDetail(
            item: Self.toItem(d.drama, sourceKey: config.id, path: item),
            overview: d.drama.description,
            episodes: episodes
        )
    }

    public func playback(item: String, quality: Quality?) async throws -> PlaybackSource {
        // mount 直链；webdav 经本网关流代理（Basic 鉴权）
        if let url = try await NASEngine.shared.playURL(id: libraryId, path: item) {
            return PlaybackSource(delivery: .direct, url: url)
        }
        // webdav：走网关 /api/nas/stream（由网关 openStream 提供）
        guard let base = GatewayBase.url else { throw MediaServerError.network("no gateway") }
        var comp = URLComponents(url: base.appendingPathComponent("/api/nas/stream"), resolvingAgainstBaseURL: false)!
        comp.queryItems = [URLQueryItem(name: "id", value: libraryId),
                           URLQueryItem(name: "path", value: item)]
        guard let url = comp.url else { throw MediaServerError.parse("bad stream url") }
        return PlaybackSource(delivery: .proxied, url: url)
    }

    public func search(query: String, filter: SearchFilter) async throws -> [MediaItem] {
        // NAS 不做全文搜（逐层遍历代价高），返回空，聚合搜索时由其他源补齐
        []
    }

    public func reportProgress(item: String, position: TimeInterval, state: PlayState) async {}

    private static func toItem(_ d: Drama, sourceKey: String, path: String) -> MediaItem {
        MediaItem(
            id: d.shareURL ?? "\(path)/\(d.title)", sourceKey: sourceKey,
            kind: d.episodeCount == 1 ? .movie : .series,
            title: d.title, subTitle: d.updateStatus, poster: d.coverURL,
            extra: ["path": d.shareURL ?? path]
        )
    }
}

/// 网关 base（避免循环依赖，运行时取）。
enum GatewayBase {
    static var url: URL? {
        // 网关默认 8787，与应用内 AppSettings 对齐；适配器在网关进程内用 localhost。
        URL(string: "http://127.0.0.1:8787")
    }
}
