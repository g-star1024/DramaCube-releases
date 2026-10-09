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
        return WebParser.parseSeriesList(json)
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

    /// 播放代理：请求 CDN 直链，**刻意不携带 Referer**。返回 (data, contentType)。
    public func fetchMedia(_ urlString: String) async throws -> (Data, String) {
        guard let url = URL(string: urlString) else { throw HongguoParseError.fieldMissing("url") }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // 注意：不设置 Referer —— 字节 CDN 对带 Referer 的请求返回 403；直链本身免 Referer 可用。
        let (data, resp) = try await session.data(for: req)
        let ct = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
        return (data, ct)
    }
}
