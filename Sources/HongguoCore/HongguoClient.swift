import Foundation

/// 红果内容接入客户端。
///
/// 策略（2026-10-09 站点改版后重调研，见 .workbuddy/analysis/api-research-2026-10-09.md）：
///  - 站点 `hongguoduanju.com`（原 novelquickapp.com 已 301 迁移）SSR 数据载体 `_ROUTER_DATA`；
///  - 首页 / 类目：`_ROUTER_DATA` 内剧集条目；榜单 / 搜索：SSR DOM 卡片；
///  - 详情：`/detail?series_id=X` 的 `seriesDetail.vid_list`（完整选集）；
///  - 播放：`/player/<sid>/<vid>` 内嵌 `video_player_info.main_url` CDN 直链（免签名、免 Referer，206 Range 可用）；
///  - 不依赖任何逆向签名（X-Argus / spade_a）。
public actor HongguoClient {

    public static let shared = HongguoClient()

    private let session: URLSession
    private let host = "hongguoduanju.com"
    // 桌面 Chrome UA，规避移动端重定向与基础风控。
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
                            "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    public init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpAdditionalHeaders = ["User-Agent": userAgent]
        cfg.timeoutIntervalForRequest = 20
        // 强制直连：红果/采集站 CDN 锁中国大陆 IP，系统代理（VPN）走境外会被区域拦截 403。
        cfg.connectionProxyDictionary = [:]
        self.session = URLSession(configuration: cfg)
    }

    private func getHTML(_ url: URL) async throws -> String {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        let (data, resp) = try await session.data(for: req)
        guard let html = String(data: data, encoding: .utf8) else {
            throw HongguoParseError.invalidJSON
        }
        // 404 兜底页也含空 _ROUTER_DATA，靠调用方解析结果为空兜底；此处仅拦 5xx。
        if let http = resp as? HTTPURLResponse, (500...599).contains(http.statusCode) {
            throw HongguoParseError.fieldMissing("http_\(http.statusCode)")
        }
        return html
    }

    /// 详情页：https://hongguoduanju.com/detail?series_id=<id>
    /// 选集来自 seriesDetail.vid_list；播放直链在点播时经 `resolvePlayURL` 解析。
    public func fetchDetail(id: String) async throws -> DramaDetail {
        guard let url = URL(string: "https://\(host)/detail?series_id=\(id)") else {
            throw HongguoParseError.fieldMissing("id")
        }
        let html = try await getHTML(url)
        guard let json = WebParser.extractRouterData(html) else {
            throw HongguoParseError.routerDataNotFound
        }
        var detail = try WebParser.parseSeriesDetail(json)
        // 回填 shareURL（此处即详情页 URL）供前端/调试使用
        detail.drama = Drama(id: detail.drama.id, title: detail.drama.title,
                             coverURL: detail.drama.coverURL, description: detail.drama.description,
                             episodeCount: detail.drama.episodeCount, tags: detail.drama.tags,
                             category: detail.drama.category, updateStatus: detail.drama.updateStatus,
                             shareURL: url.absoluteString)
        return detail
    }

    /// 搜索：https://hongguoduanju.com/search/<关键词>（SSR DOM 卡片）。
    public func search(query: String) async throws -> [Drama] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://\(host)/search/\(q)") else {
            throw HongguoParseError.fieldMissing("query")
        }
        let html = try await getHTML(url)
        return WebParser.parseCardsHTML(html)
    }

    /// 通用列表页。支持三类路径：
    ///  - `/`（首页 homeSections）
    ///  - `/category/real-drama`、`/category/comic-drama`、`/category/ai-drama`、`/category?tab=1&...`（_ROUTER_DATA recommendList）
    ///  - `/rank/hot-drama` 等榜单（SSR DOM 卡片）
    /// `page` 透传为 `?page=N`（榜单分页可用；类目/首页静默忽略）。
    public func catalog(path: String, page: Int = 1) async throws -> [Drama] {
        let safe = path.hasPrefix("/") ? path : "/" + path
        let pageSuffix = page > 1 ? (safe.contains("?") ? "&page=\(page)" : "?page=\(page)") : ""
        guard let url = URL(string: "https://\(host)\(safe)\(pageSuffix)") else {
            throw HongguoParseError.fieldMissing("path")
        }
        let html = try await getHTML(url)
        if safe.hasPrefix("/rank") {
            return WebParser.parseCardsHTML(html)
        }
        guard let json = WebParser.extractRouterData(html) else { return [] }
        return WebParser.parseSeriesList(json).filter { !Self.isActorCard($0) }
    }

    /// 演员卡片识别（红果 tag 页数据本身混入，非解析 bug）：
    /// 标题为纯中文人名（2-4 字，可带括号别名如「戴翎玥（戴戴）」）、无封面、无集数。
    /// 三者缺一不可——「最食人间烟火色」这类短剧名不会被误杀（>4字/有封面）。
    public static func isActorCard(_ d: Drama) -> Bool {
        let t = d.title.trimmingCharacters(in: .whitespaces)
        let isHanName = t.range(of: #"^[\u{4E00}-\u{9FA5}·]{2,4}(（[^）]*）)?$"#, options: .regularExpression) != nil
        guard isHanName else { return false }
        let noCover = (d.coverURL ?? "").isEmpty
        let noCount = d.episodeCount == nil
        return noCover && noCount
    }

    /// 播放直链解析：请求 /player/<sid>/<vid>，提取 video_player_info.main_url（CDN 直链）。
    public func resolvePlayURL(seriesId: String, vid: String) async throws -> String {
        guard let url = URL(string: "https://\(host)/player/\(seriesId)/\(vid)") else {
            throw HongguoParseError.fieldMissing("vid")
        }
        let html = try await getHTML(url)
        guard let json = WebParser.extractRouterData(html),
              let mainURL = WebParser.parseMainURL(json), !mainURL.isEmpty else {
            throw HongguoParseError.fieldMissing("main_url")
        }
        return mainURL
    }

    /// 播放代理（流式）：请求 CDN 直链，**刻意不携带 Referer**。
    /// 支持透传 `Range` 请求头（CDN 返回 206 + Content-Range），供网关边收边发，
    /// 避免 AVPlayer 的 `bytes=0-1` 探测收到全量 200 而无法 seek / 超时。
    public func openMediaStream(_ urlString: String, range: String? = nil) async throws -> MediaStream {
        guard let url = URL(string: urlString) else { throw HongguoParseError.fieldMissing("url") }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // 注意：不设置 Referer —— 字节 CDN 对带 Referer 的请求返回 403；直链本身免 Referer 可用。
        if let range, !range.isEmpty {
            req.setValue(range, forHTTPHeaderField: "Range")
        }
        let (bytes, resp) = try await session.bytes(for: req)
        let http = resp as? HTTPURLResponse
        return MediaStream(
            status: http?.statusCode ?? 200,
            contentType: http?.value(forHTTPHeaderField: "Content-Type") ?? "video/mp4",
            contentLength: http?.value(forHTTPHeaderField: "Content-Length"),
            contentRange: http?.value(forHTTPHeaderField: "Content-Range"),
            bytes: bytes
        )
    }
}

/// 流式媒体响应（网关 Range 透传代理专用）。
public struct MediaStream: Sendable {
    public let status: Int
    public let contentType: String
    public let contentLength: String?
    public let contentRange: String?
    public let bytes: URLSession.AsyncBytes
}
