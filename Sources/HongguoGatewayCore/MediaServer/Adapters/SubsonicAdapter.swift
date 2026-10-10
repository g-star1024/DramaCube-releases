import Foundation
import CryptoKit
import HongguoCore

// MARK: - Subsonic / Navidrome 适配器（M3，音乐）
// API：/rest/* 经典 Subsonic 协议。认证 u+t(token=md5(pwd+salt))+s(salt)。

public struct SubsonicAdapter: MediaServerProtocol {
    public let config: MediaServerConfig

    public init(config: MediaServerConfig) { self.config = config }

    private var base: String { config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }

    /// Subsonic token 认证参数（md5(password+salt)）。
    private func authParams() -> [URLQueryItem] {
        let salt = String(UUID().uuidString.prefix(8))
        let pwd = config.password ?? config.token ?? ""
        let token = Insecure.MD5.hash(data: Data((pwd + salt).utf8)).map { String(format: "%02x", $0) }.joined()
        return [
            URLQueryItem(name: "u", value: config.username ?? ""),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: "1.16.1"),
            URLQueryItem(name: "c", value: "DramaCube"),
            URLQueryItem(name: "f", value: "json"),
        ]
    }

    private func request(_ endpoint: String, extra: [URLQueryItem] = []) -> URLRequest? {
        var comp = URLComponents(string: "\(base)/rest/\(endpoint)")
        comp?.queryItems = authParams() + extra
        guard let url = comp?.url else { return nil }
        return URLRequest(url: url)
    }

    // Subsonic 响应壳
    private struct Resp<T: Codable>: Codable {
        let subsonic_response: Sub?
        struct Sub: Codable {
            let status: String
            let body: T?
            enum CodingKeys: String, CodingKey {
                case status
                case body = "__placeholder__"   // 动态键，外层另行解析
            }
        }
    }

    // 简化：直接解析 JSON 字典（Subsonic 各端点键名不同）
    private func call(_ endpoint: String, extra: [URLQueryItem] = []) async throws -> [String: Any] {
        guard let req = request(endpoint, extra: extra) else { throw MediaServerError.network("bad url") }
        let (data, _) = try await DirectURLSession.shared.data(for: req)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let sub = obj?["subsonic-response"] as? [String: Any]
        guard (sub?["status"] as? String) == "ok" else {
            let err = (sub?["error"] as? [String: Any])?["message"] as? String ?? "unknown"
            throw MediaServerError.network(err)
        }
        return sub ?? [:]
    }

    // MARK: - 探测

    public func probe() async -> ServerCapability {
        let t0 = Date()
        do {
            let r = try await call("ping")
            let ok = (r["status"] as? String) == "ok"
            return ServerCapability(online: ok, latencyMs: Int(Date().timeIntervalSince(t0) * 1000),
                                    canSearch: true, canReportProgress: true)
        } catch {
            return ServerCapability(online: false, needsAuth: true, message: "连接/认证失败")
        }
    }

    // MARK: - 库（音乐库=艺术家集合；也暴露歌单）

    public func libraries() async throws -> [MediaLibrary] {
        var libs: [MediaLibrary] = []
        // 歌单
        if let r = try? await call("getPlaylists"),
           let playlists = (r["playlists"] as? [String: Any])?["playlist"] as? [[String: Any]] {
            for p in playlists {
                if let id = p["id"] as? CustomStringConvertible,
                   let name = p["name"] as? String {
                    libs.append(MediaLibrary(id: "playlist|\(id)", sourceKey: config.id, title: name, kind: .music))
                }
            }
        }
        // 艺术家入口
        libs.insert(MediaLibrary(id: "__artists__", sourceKey: config.id, title: "全部艺术家", kind: .artist), at: 0)
        return libs
    }

    public func items(library: String, page: Int, limit: Int) async throws -> MediaPage {
        if library == "__artists__" {
            let r = try await call("getArtists")
            let index = (r["artists"] as? [String: Any])?["index"] as? [[String: Any]] ?? []
            var artists: [MediaItem] = []
            for ix in index {
                for a in ix["artist"] as? [[String: Any]] ?? [] {
                    if let id = a["id"] as? CustomStringConvertible, let name = a["name"] as? String {
                        artists.append(MediaItem(id: "\(id)", sourceKey: config.id, kind: .artist, title: name))
                    }
                }
            }
            return MediaPage(items: artists, page: page, hasMore: false)
        }
        if library.hasPrefix("playlist|") {
            let pid = String(library.dropFirst("playlist|".count))
            let r = try await call("getPlaylist", extra: [URLQueryItem(name: "id", value: pid)])
            let entries = (r["playlist"] as? [String: Any])?["entry"] as? [[String: Any]] ?? []
            return MediaPage(items: entries.map { toSong($0) }, page: page, hasMore: false)
        }
        return MediaPage(items: [], page: page, hasMore: false)
    }

    public func detail(item: String) async throws -> MediaDetail {
        // 艺术家 → 专辑列表
        let r = try await call("getArtist", extra: [URLQueryItem(name: "id", value: item)])
        let artist = r["artist"] as? [String: Any] ?? [:]
        let name = artist["name"] as? String ?? "艺术家"
        let albums = artist["album"] as? [[String: Any]] ?? []
        let albumItems = albums.map { a -> MediaItem in
            MediaItem(id: "\(a["id"] as? CustomStringConvertible ?? "")", sourceKey: config.id,
                      kind: .album, title: a["name"] as? String ?? "",
                      year: (a["year"] as? Int).map(String.init))
        }
        return MediaDetail(item: MediaItem(id: item, sourceKey: config.id, kind: .artist, title: name),
                           episodes: albumItems)
    }

    public func playback(item: String, quality: Quality?) async throws -> PlaybackSource {
        // /rest/stream?id=
        guard let url = request("stream", extra: [URLQueryItem(name: "id", value: item)])?.url else {
            throw MediaServerError.notFound
        }
        return PlaybackSource(delivery: .direct, url: url)
    }

    public func search(query: String, filter: SearchFilter) async throws -> [MediaItem] {
        let r = try await call("search3", extra: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "songCount", value: "30"),
        ])
        let result = r["searchResult3"] as? [String: Any] ?? [:]
        let songs = result["song"] as? [[String: Any]] ?? []
        return songs.map { toSong($0) }
    }

    public func reportProgress(item: String, position: TimeInterval, state: PlayState) async {
        // scrobble：完成或播放中上报
        guard state == .finished || state == .playing else { return }
        _ = try? await call("scrobble", extra: [
            URLQueryItem(name: "id", value: item),
            URLQueryItem(name: "submission", value: state == .finished ? "true" : "false"),
        ])
    }

    private func toSong(_ s: [String: Any]) -> MediaItem {
        let id = "\(s["id"] as? CustomStringConvertible ?? "")"
        return MediaItem(
            id: id, sourceKey: config.id, kind: .music,
            title: s["title"] as? String ?? "",
            subTitle: s["artist"] as? String,
            year: (s["year"] as? Int).map(String.init),
            duration: (s["duration"] as? Int).map(TimeInterval.init)
        )
    }
}
