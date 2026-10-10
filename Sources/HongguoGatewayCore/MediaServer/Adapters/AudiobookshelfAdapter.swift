import Foundation
import HongguoCore

// MARK: - audiobookshelf 适配器（M3，听书）
// API：/api/libraries、/api/libraries/{id}/items、/api/items/{id}、/api/me、/api/session。

public struct AudiobookshelfAdapter: MediaServerProtocol {
    public let config: MediaServerConfig

    public init(config: MediaServerConfig) { self.config = config }

    private var base: String { config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }

    private func request(_ path: String) -> URLRequest? {
        guard let url = URL(string: "\(base)\(path)") else { return nil }
        var req = URLRequest(url: url)
        if let t = config.token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        return req
    }

    // MARK: - 探测

    public func probe() async -> ServerCapability {
        let t0 = Date()
        guard let req = request("/api/me"),
              let (_, resp) = try? await DirectURLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else {
            return ServerCapability(online: false, message: "连接失败")
        }
        let ok = http.statusCode == 200
        return ServerCapability(online: ok, latencyMs: Int(Date().timeIntervalSince(t0) * 1000),
                                canSearch: true, canReportProgress: true,
                                needsAuth: http.statusCode == 401, authenticated: ok,
                                message: ok ? nil : "HTTP \(http.statusCode)")
    }

    // MARK: - 库

    public func libraries() async throws -> [MediaLibrary] {
        guard let req = request("/api/libraries"),
              let (data, _) = try? await DirectURLSession.shared.data(for: req) else { return [] }
        struct R: Codable {
            let libraries: [Lib]?
            struct Lib: Codable { let id, name: String? }
        }
        let libs = try JSONDecoder().decode(R.self, from: data).libraries ?? []
        return libs.compactMap { l -> MediaLibrary? in
            guard let id = l.id else { return nil }
            return MediaLibrary(id: id, sourceKey: config.id, title: l.name ?? "书库", kind: .audiobook)
        }
    }

    public func items(library: String, page: Int, limit: Int) async throws -> MediaPage {
        guard let req = request("/api/libraries/\(library)/items?limit=\(limit)&page=\(page)&sort=addedAt&desc=1"),
              let (data, _) = try? await DirectURLSession.shared.data(for: req) else {
            return MediaPage(items: [], page: page, hasMore: false)
        }
        struct R: Codable {
            let results: [Item]?
            let total: Int?
        }
        let r = try JSONDecoder().decode(R.self, from: data)
        let items = (r.results ?? []).map { toItem($0) }
        return MediaPage(items: items, page: page, hasMore: items.count == limit, total: r.total)
    }

    public func detail(item: String) async throws -> MediaDetail {
        guard let req = request("/api/items/\(item)?expanded=1"),
              let (data, _) = try? await DirectURLSession.shared.data(for: req) else {
            throw MediaServerError.notFound
        }
        let raw = try JSONDecoder().decode(Item.self, from: data)
        // 章节/音轨
        var episodes: [MediaItem] = []
        if let tracks = raw.media?.tracks {
            episodes = tracks.enumerated().map { idx, t in
                MediaItem(id: "\(item)#tr\(idx)", sourceKey: config.id, kind: .episode,
                          title: t.title ?? "第 \(idx + 1) 节",
                          duration: t.duration,
                          extra: ["itemId": item, "trackIndex": "\(idx)"])
            }
        }
        return MediaDetail(item: toItem(raw),
                           overview: raw.media?.metadata?.description,
                           episodes: episodes,
                           actors: raw.media?.metadata?.authorName.map { [$0] } ?? [])
    }

    public func playback(item: String, quality: Quality?) async throws -> PlaybackSource {
        // item 形如 "itemId#trN"（章节）或纯 itemId
        let (itemId, trackIdx) = Self.parseRef(item)
        // /api/items/{id}/file/{ino} 或 /api/items/{id}/play
        var path = "/api/items/\(itemId)/play"
        if let idx = trackIdx { path += "?trackIndex=\(idx)" }
        guard let url = URL(string: "\(base)\(path)") else { throw MediaServerError.notFound }
        let headers = config.token.map { ["Authorization": "Bearer \($0)"] } ?? [:]
        return PlaybackSource(delivery: .direct, url: url, headers: headers)
    }

    public func search(query: String, filter: SearchFilter) async throws -> [MediaItem] {
        guard let req = request("/api/libraries/\(config.extra["libraryId"] ?? "")/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"),
              let (data, _) = try? await DirectURLSession.shared.data(for: req) else { return [] }
        struct R: Codable {
            let book: [Item]?
        }
        let r = try? JSONDecoder().decode(R.self, from: data)
        return (r?.book ?? []).map { toItem($0) }
    }

    public func reportProgress(item: String, position: TimeInterval, state: PlayState) async {
        // /api/me/progress（audiobookshelf 进度同步）
        let (itemId, _) = Self.parseRef(item)
        guard var req = request("/api/me/progress") else { return }
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "libraryItemId": itemId,
            "currentTime": position,
            "isFinished": state == .finished,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await DirectURLSession.shared.data(for: req)
    }

    public func continueWatching(limit: Int) async throws -> [MediaItem] {
        // /api/me/items-in-progress
        guard let req = request("/api/me/items-in-progress?limit=\(limit)"),
              let (data, _) = try? await DirectURLSession.shared.data(for: req) else { return [] }
        struct R: Codable {
            let libraryItems: [Item]?
        }
        let r = try? JSONDecoder().decode(R.self, from: data)
        return (r?.libraryItems ?? []).map { toItem($0) }
    }

    // MARK: - 映射

    private static func parseRef(_ ref: String) -> (String, Int?) {
        guard let hash = ref.firstIndex(of: "#") else { return (ref, nil) }
        let id = String(ref[..<hash])
        let tail = String(ref[ref.index(after: hash)...])   // "tr3"
        return (id, Int(tail.dropFirst(2)))
    }

    private func toItem(_ i: Item) -> MediaItem {
        MediaItem(
            id: i.id ?? "", sourceKey: config.id, kind: .audiobook,
            title: i.media?.metadata?.title ?? "",
            subTitle: i.media?.metadata?.authorName,
            duration: i.media?.duration
        )
    }

    struct Item: Codable {
        let id: String?
        let media: Media?
        struct Media: Codable {
            let duration: TimeInterval?
            let metadata: Meta?
            let tracks: [Track]?
            struct Meta: Codable {
                let title: String?
                let authorName: String?
                let description: String?
            }
            struct Track: Codable {
                let title: String?
                let duration: TimeInterval?
            }
        }
    }
}
