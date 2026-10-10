import Foundation
import HongguoCore

// MARK: - Emby / Jellyfin 适配器（M2/M3）
// 两者 API 高度同构（/emby/* 前缀，Jellyfin 去掉前缀），共用一套实现。
// 能力：认证 / 媒体库 / 分页列表 / 详情 / 服务端转码 HLS / 播放进度上报(Sessions/Playing)。

public struct EmbyAdapter: MediaServerProtocol {
    public let config: MediaServerConfig
    private let isJellyfin: Bool

    public init(config: MediaServerConfig) {
        self.config = config
        self.isJellyfin = (config.kind == .jellyfin)
    }

    // Emby 用 /emby 前缀，Jellyfin 直接用根路径
    private var prefix: String { isJellyfin ? "" : "/emby" }
    private var base: String { config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }

    private var userId: String? { config.extra["userId"] }
    private var token: String? { config.token }

    // MARK: - 认证

    /// 用户名密码登录，拿 accessToken + userId。
    public static func authenticate(baseURL: String, username: String, password: String,
                                    isJellyfin: Bool) async throws -> MediaServerConfig {
        let prefix = isJellyfin ? "" : "/emby"
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: "\(base)\(prefix)/Users/AuthenticateByName")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.authHeader(), forHTTPHeaderField: "X-Emby-Authorization")
        req.httpBody = try JSONEncoder().encode(["Username": username, "Pw": password])
        let (data, resp) = try await DirectURLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw MediaServerError.unauthorized
        }
        struct AuthResp: Codable {
            let AccessToken: String
            let User: UserInfo
            struct UserInfo: Codable { let Id: String }
        }
        let auth = try JSONDecoder().decode(AuthResp.self, from: data)
        let kind: MediaServerKind = isJellyfin ? .jellyfin : .emby
        let host = URL(string: base)?.host ?? base
        return MediaServerConfig(
            id: "\(kind.rawValue)|\(host)", kind: kind, name: "\(kind.rawValue.capitalized) \(host)",
            baseURL: base, username: username, token: auth.AccessToken,
            extra: ["userId": auth.User.Id]
        )
    }

    private static func authHeader() -> String {
        "MediaBrowser Client=\"DramaCube\", Device=\"macOS\", DeviceId=\"dramacube-mac\", Version=\"2.0\""
    }

    private func authedRequest(_ path: String, query: [URLQueryItem] = []) -> URLRequest? {
        var comp = URLComponents(string: "\(base)\(prefix)\(path)")
        var items = query
        if let t = token { items.append(URLQueryItem(name: "api_key", value: t)) }
        comp?.queryItems = items.isEmpty ? nil : items
        guard let url = comp?.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue(Self.authHeader(), forHTTPHeaderField: "X-Emby-Authorization")
        if let t = token { req.setValue(t, forHTTPHeaderField: "X-Emby-Token") }
        return req
    }

    // MARK: - 探测

    public func probe() async -> ServerCapability {
        let t0 = Date()
        guard let req = authedRequest("/System/Info"),
              let (data, resp) = try? await DirectURLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            return ServerCapability(online: false, needsAuth: true, authenticated: token != nil,
                                    message: "连接失败或未认证")
        }
        struct Info: Codable { let Version: String? }
        let info = try? JSONDecoder().decode(Info.self, from: data)
        return ServerCapability(
            online: true, latencyMs: Int(Date().timeIntervalSince(t0) * 1000),
            serverVersion: info?.Version, canTranscode: true, canSearch: true,
            canReportProgress: true, authenticated: true
        )
    }

    // MARK: - 媒体库

    public func libraries() async throws -> [MediaLibrary] {
        guard let uid = userId, let req = authedRequest("/Users/\(uid)/Views") else { return [] }
        let (data, _) = try await DirectURLSession.shared.data(for: req)
        struct Views: Codable {
            let Items: [Lib]
            struct Lib: Codable { let Id, Name: String; let CollectionType: String? }
        }
        let views = try JSONDecoder().decode(Views.self, from: data)
        return views.Items.map {
            MediaLibrary(id: $0.Id, sourceKey: config.id, title: $0.Name,
                         kind: Self.mapKind($0.CollectionType))
        }
    }

    public func items(library: String, page: Int, limit: Int) async throws -> MediaPage {
        guard let uid = userId else { return MediaPage(items: [], page: page, hasMore: false) }
        let req = authedRequest("/Users/\(uid)/Items", query: [
            URLQueryItem(name: "ParentId", value: library),
            URLQueryItem(name: "StartIndex", value: "\(page * limit)"),
            URLQueryItem(name: "Limit", value: "\(limit)"),
            URLQueryItem(name: "SortBy", value: "DateCreated"),
            URLQueryItem(name: "SortOrder", value: "Descending"),
            URLQueryItem(name: "Fields", value: "Overview,ProductionYear,CommunityRating"),
            URLQueryItem(name: "ImageTypeLimit", value: "1"),
        ])!
        let (data, _) = try await DirectURLSession.shared.data(for: req)
        let page0 = try JSONDecoder().decode(ItemList.self, from: data)
        let items = page0.Items.map { toItem($0) }
        return MediaPage(items: items, page: page,
                         hasMore: (page * limit + items.count) < (page0.TotalRecordCount ?? 0),
                         total: page0.TotalRecordCount)
    }

    // MARK: - 详情

    public func detail(item: String) async throws -> MediaDetail {
        guard let uid = userId else { throw MediaServerError.unauthorized }
        guard let req = authedRequest("/Users/\(uid)/Items/\(item)", query: [
            URLQueryItem(name: "Fields", value: "Overview,ProductionYear,CommunityRating,People,Genres,MediaSources")
        ]) else { throw MediaServerError.network("bad request") }
        let (data, _) = try await DirectURLSession.shared.data(for: req)
        let raw = try JSONDecoder().decode(RawItem.self, from: data)

        // 剧集：拉子集
        var episodes: [MediaItem] = []
        if raw.Type == "Series", let ereq = authedRequest("/Shows/\(item)/Episodes", query: [
            URLQueryItem(name: "UserId", value: uid),
            URLQueryItem(name: "Fields", value: "Overview,MediaSources")
        ]), let (edata, _) = try? await DirectURLSession.shared.data(for: ereq),
           let elist = try? JSONDecoder().decode(ItemList.self, from: edata) {
            episodes = elist.Items.map { toItem($0, kind: .episode) }
        }

        // 音轨/字幕从 MediaSources 提取
        let (subs, auds) = Self.extractTracks(from: raw)
        return MediaDetail(
            item: toItem(raw),
            overview: raw.Overview,
            episodes: episodes,
            subtitles: subs, audioTracks: auds,
            actors: raw.People?.filter { $0.Type == "Actor" }.map { $0.Name } ?? [],
            directors: raw.People?.filter { $0.Type == "Director" }.map { $0.Name } ?? [],
            genres: raw.Genres ?? []
        )
    }

    // MARK: - 播放（服务端转码 HLS）

    public func playback(item: String, quality: Quality?) async throws -> PlaybackSource {
        guard userId != nil, let t = token else { throw MediaServerError.unauthorized }

        // 走转码 HLS：/Videos/{id}/master.m3u8（按 quality 限定码率）
        var comp = URLComponents(string: "\(base)\(prefix)/Videos/\(item)/master.m3u8")!
        var items = [
            URLQueryItem(name: "api_key", value: t),
            URLQueryItem(name: "MediaSourceId", value: item),
            URLQueryItem(name: "VideoCodec", value: "h264,h265,hevc,av1"),
            URLQueryItem(name: "AudioCodec", value: "aac,mp3,ac3,eac3,flac"),
            URLQueryItem(name: "PlaySessionId", value: UUID().uuidString.replacingOccurrences(of: "-", with: "")),
        ]
        if let br = Self.bitrate(for: quality) {
            items.append(URLQueryItem(name: "VideoBitrate", value: "\(br)"))
        }
        comp.queryItems = items
        guard let url = comp.url else { throw MediaServerError.parse("bad transcode url") }

        let source = PlaybackSource(
            delivery: .transcodeHLS,
            url: url,
            headers: ["X-Emby-Authorization": Self.authHeader()]
        )
        return source
    }

    private static func bitrate(for q: Quality?) -> Int? {
        switch q {
        case .p1080: return 10_000_000
        case .p720: return 5_000_000
        case .p480: return 2_000_000
        case .audioOnly: return 192_000
        default: return nil   // original/auto 不限码率
        }
    }

    // MARK: - 搜索

    public func search(query: String, filter: SearchFilter) async throws -> [MediaItem] {
        guard let uid = userId else { return [] }
        guard let req = authedRequest("/Users/\(uid)/Items", query: [
            URLQueryItem(name: "SearchTerm", value: query),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Limit", value: "50"),
            URLQueryItem(name: "Fields", value: "ProductionYear,CommunityRating"),
        ]) else { return [] }
        let (data, _) = try await DirectURLSession.shared.data(for: req)
        let list = try JSONDecoder().decode(ItemList.self, from: data)
        return list.Items.map { toItem($0) }
    }

    // MARK: - 进度上报（Sessions/Playing）

    public func reportProgress(item: String, position: TimeInterval, state: PlayState) async {
        guard let uid = userId else { return }
        let ticks = Int64(position * 10_000_000)   // Emby 用 100ns ticks
        let path: String
        switch state {
        case .playing, .paused: path = "/Sessions/Playing/Progress"
        case .stopped, .finished: path = "/Sessions/Playing/Stopped"
        }
        guard var req = authedRequest(path) else { return }
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Codable {
            let ItemId: String; let PositionTicks: Int64
            let IsPaused: Bool; let UserId: String
        }
        req.httpBody = try? JSONEncoder().encode(Body(
            ItemId: item, PositionTicks: ticks,
            IsPaused: state == .paused, UserId: uid))
        _ = try? await DirectURLSession.shared.data(for: req)
    }

    // MARK: - 继续观看 / 最新入库

    public func continueWatching(limit: Int) async throws -> [MediaItem] {
        guard let uid = userId,
              let req = authedRequest("/Users/\(uid)/Items/Resume", query: [
                  URLQueryItem(name: "Limit", value: "\(limit)"),
                  URLQueryItem(name: "Fields", value: "ProductionYear,CommunityRating"),
              ]) else { return [] }
        let (data, _) = try await DirectURLSession.shared.data(for: req)
        let list = try JSONDecoder().decode(ItemList.self, from: data)
        return list.Items.map { toItem($0) }
    }

    public func recentlyAdded(limit: Int) async throws -> [MediaItem] {
        guard let uid = userId,
              let req = authedRequest("/Users/\(uid)/Items/Latest", query: [
                  URLQueryItem(name: "Limit", value: "\(limit)"),
                  URLQueryItem(name: "Fields", value: "ProductionYear,CommunityRating"),
              ]) else { return [] }
        let (data, _) = try await DirectURLSession.shared.data(for: req)
        let list = try JSONDecoder().decode([RawItem].self, from: data)
        return list.map { toItem($0) }
    }

    // MARK: - 映射

    private static func mapKind(_ collection: String?) -> MediaKind {
        switch collection {
        case "movies": return .movie
        case "tvshows": return .series
        case "music": return .music
        case "homevideos", "movies", "boxsets": return .movie
        default: return .unknown
        }
    }

    private func imageURL(_ item: RawItem, type: String) -> String? {
        guard item.ImageTags?.Primary != nil else { return nil }
        return "\(base)\(prefix)/Items/\(item.Id)/Images/\(type)?maxWidth=500&quality=90"
    }

    private func toItem(_ r: RawItem, kind: MediaKind? = nil) -> MediaItem {
        MediaItem(
            id: r.Id, sourceKey: config.id,
            kind: kind ?? Self.mapItemType(r.Type),
            title: r.Name, subTitle: r.SeriesName,
            poster: imageURL(r, type: "Primary"),
            backdrop: imageURL(r, type: "Backdrop"),
            year: r.ProductionYear.map(String.init),
            rate: r.CommunityRating.map { String(format: "%.1f", $0) },
            duration: r.RunTimeTicks.map { $0 / 10_000_000 }
        )
    }

    private static func mapItemType(_ t: String?) -> MediaKind {
        switch t {
        case "Movie": return .movie
        case "Series": return .series
        case "Episode": return .episode
        case "Audio": return .music
        case "MusicAlbum": return .album
        case "AudioBook", "Book": return .audiobook
        default: return .unknown
        }
    }

    private static func extractTracks(from r: RawItem) -> ([SubtitleTrack], [AudioTrack]) {
        var subs: [SubtitleTrack] = []
        var auds: [AudioTrack] = []
        for stream in r.MediaSources?.first?.MediaStreams ?? [] {
            switch stream.Type {
            case "Subtitle":
                subs.append(SubtitleTrack(id: "\(stream.Index)", title: stream.DisplayTitle ?? "字幕",
                                          language: stream.Language, format: stream.Codec,
                                          isEmbedded: stream.IsExternal != true))
            case "Audio":
                auds.append(AudioTrack(id: "\(stream.Index)", title: stream.DisplayTitle ?? "音轨",
                                       language: stream.Language, channels: stream.Channels))
            default: break
            }
        }
        return (subs, auds)
    }

    // MARK: - Codable 中间结构

    struct ItemList: Codable {
        let Items: [RawItem]
        let TotalRecordCount: Int?
    }

    struct RawItem: Codable {
        let Id, Name: String
        let Type: String?
        let SeriesName: String?
        let Overview: String?
        let ProductionYear: Int?
        let CommunityRating: Double?
        let RunTimeTicks: TimeInterval?
        let Genres: [String]?
        let ImageTags: ImageTags?
        let People: [Person]?
        let MediaSources: [MediaSource]?

        struct ImageTags: Codable { let Primary: String? }
        struct Person: Codable { let Name, Type: String }
        struct MediaSource: Codable {
            let MediaStreams: [MediaStream]?
            struct MediaStream: Codable {
                let Index: Int
                let Type: String?
                let Codec: String?
                let Language: String?
                let DisplayTitle: String?
                let Channels: Int?
                let IsExternal: Bool?
            }
        }
    }
}
