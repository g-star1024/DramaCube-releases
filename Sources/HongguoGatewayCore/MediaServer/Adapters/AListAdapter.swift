import Foundation
import HongguoCore

// MARK: - AList / OpenList 适配器（M3）
// 网盘聚合（阿里/夸克/115/OneDrive 等经 AList 统一挂载）。
// API：/api/fs/list 列目录、/api/fs/get 取直链。视频文件按目录即剧集库。

public struct AListAdapter: MediaServerProtocol {
    public let config: MediaServerConfig

    public init(config: MediaServerConfig) { self.config = config }

    private var base: String { config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    private var rootPath: String { config.extra["rootPath"] ?? "/" }

    private func request(_ path: String, body: [String: Any]? = nil) -> URLRequest? {
        guard let url = URL(string: "\(base)\(path)") else { return nil }
        var req = URLRequest(url: url)
        if let t = config.token { req.setValue(t, forHTTPHeaderField: "Authorization") }
        if let body = body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    private static let videoExts: Set<String> = ["mp4","mkv","avi","mov","m4v","ts","wmv","flv","webm","rmvb","mpg","mpeg"]

    // MARK: - 探测

    public func probe() async -> ServerCapability {
        let t0 = Date()
        guard let req = request("/api/fs/list", body: ["path": rootPath, "page": 1, "per_page": 1]),
              let (data, resp) = try? await DirectURLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            return ServerCapability(online: false, message: "连接失败")
        }
        struct R: Codable { let code: Int? }
        let ok = (try? JSONDecoder().decode(R.self, from: data))?.code == 200
        return ServerCapability(online: ok, latencyMs: Int(Date().timeIntervalSince(t0) * 1000),
                                canSearch: false, canReportProgress: false,
                                message: ok ? nil : "AList 返回异常")
    }

    // MARK: - 库（按一级子目录作为库）

    public func libraries() async throws -> [MediaLibrary] {
        let dirs = try await listDirs(rootPath)
        return dirs.map {
            MediaLibrary(id: $0, sourceKey: config.id,
                         title: ($0 as NSString).lastPathComponent, kind: .series)
        }
    }

    public func items(library: String, page: Int, limit: Int) async throws -> MediaPage {
        let dirs = try await listDirs(library)   // 库下每个子目录=一部剧
        let items = dirs.map { dir -> MediaItem in
            MediaItem(id: dir, sourceKey: config.id, kind: .series,
                      title: (dir as NSString).lastPathComponent,
                      extra: ["path": dir])
        }
        return MediaPage(items: items, page: page, hasMore: false)
    }

    public func detail(item: String) async throws -> MediaDetail {
        let files = try await listFiles(item)
        let episodes = files.map { f -> MediaItem in
            MediaItem(id: f, sourceKey: config.id, kind: .episode,
                      title: (f as NSString).lastPathComponent,
                      extra: ["path": f])
        }
        let item0 = MediaItem(id: item, sourceKey: config.id, kind: .series,
                              title: (item as NSString).lastPathComponent,
                              extra: ["path": item])
        return MediaDetail(item: item0, episodes: episodes)
    }

    public func playback(item: String, quality: Quality?) async throws -> PlaybackSource {
        // /api/fs/get 取直链（含临时签名 URL）
        guard let req = request("/api/fs/get", body: ["path": item]),
              let (data, _) = try? await DirectURLSession.shared.data(for: req) else {
            throw MediaServerError.network("fs/get failed")
        }
        struct R: Codable {
            let data: D?
            struct D: Codable {
                let raw_url: String?
                let url: String?       // 本站代理下载地址
            }
        }
        let r = try JSONDecoder().decode(R.self, from: data)
        let urlStr = r.data?.raw_url ?? r.data?.url
        guard let s = urlStr, let url = URL(string: s) else { throw MediaServerError.notFound }
        let headers = config.token.map { ["Authorization": $0] } ?? [:]
        return PlaybackSource(delivery: .direct, url: url, headers: headers)
    }

    public func search(query: String, filter: SearchFilter) async throws -> [MediaItem] {
        // AList 有 /api/fs/search（v3.20+），尝试；不支持则空
        guard let req = request("/api/fs/search", body: [
            "parent": rootPath, "keywords": query, "page": 1, "per_page": 30, "scope": 0
        ]), let (data, _) = try? await DirectURLSession.shared.data(for: req) else { return [] }
        struct R: Codable {
            let data: D?
            struct D: Codable {
                let content: [C]?
                struct C: Codable { let parent: String?; let name: String?; let is_dir: Bool? }
            }
        }
        guard let content = try? JSONDecoder().decode(R.self, from: data).data?.content else { return [] }
        return content.compactMap { c -> MediaItem? in
            guard let name = c.name else { return nil }
            let path = (c.parent ?? rootPath) + "/" + name
            return MediaItem(id: path, sourceKey: config.id,
                             kind: c.is_dir == true ? .series : .movie, title: name,
                             extra: ["path": path])
        }
    }

    public func reportProgress(item: String, position: TimeInterval, state: PlayState) async {}

    // MARK: - 目录遍历

    private struct FsList: Codable {
        let data: D?
        struct D: Codable {
            let content: [C]?
            struct C: Codable { let name: String; let is_dir: Bool }
        }
    }

    private func listDirs(_ path: String) async throws -> [String] {
        guard let req = request("/api/fs/list", body: ["path": path, "page": 1, "per_page": 0, "refresh": false]),
              let (data, _) = try? await DirectURLSession.shared.data(for: req),
              let content = try? JSONDecoder().decode(FsList.self, from: data).data?.content else { return [] }
        let prefix = path == "/" ? "" : path
        return content.filter { $0.is_dir }.map { "\(prefix)/\($0.name)" }
    }

    private func listFiles(_ path: String) async throws -> [String] {
        guard let req = request("/api/fs/list", body: ["path": path, "page": 1, "per_page": 0, "refresh": false]),
              let (data, _) = try? await DirectURLSession.shared.data(for: req),
              let content = try? JSONDecoder().decode(FsList.self, from: data).data?.content else { return [] }
        let prefix = path == "/" ? "" : path
        return content.filter { !$0.is_dir && Self.videoExts.contains(($0.name as NSString).pathExtension.lowercased()) }
                      .map { "\(prefix)/\($0.name)" }
                      .sorted()
    }
}
