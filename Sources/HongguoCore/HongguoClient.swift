import Foundation

/// 红果内容接入客户端。
///
/// 策略（见 .workbuddy/analysis/api-research-2026-10-09.md）：
///  - 浏览 / 搜索 / 榜单：解析 novelquickapp.com 落地页内联的 `_ROUTER_DATA`，列表类接口免签名。
///  - 播放：取分享页解析出的 play_url 直链，经网关请求 CDN 时统一「剥离 Referer」（字节 CDN 对带 Referer 返回 403）。
/// 不依赖任何逆向签名（X-Argus / spade_a），因此不需要设备仿真或私有密钥。
public actor HongguoClient {

    public static let shared = HongguoClient()

    private let session: URLSession
    private let host = "www.novelquickapp.com"
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
        let (data, _) = try await session.data(for: req)
        guard let html = String(data: data, encoding: .utf8) else {
            throw HongguoParseError.invalidJSON
        }
        return html
    }

    /// 分享落地页：https://www.novelquickapp.com/s/<id>/
    public func fetchDetail(id: String) async throws -> DramaDetail {
        let url = URL(string: "https://\(host)/s/\(id)/")!
        let html = try await getHTML(url)
        guard let json = WebParser.extractRouterData(html) else {
            throw HongguoParseError.routerDataNotFound
        }
        var detail = try WebParser.parseDetail(json)
        // 回填 shareURL 供前端/调试使用
        detail = DramaDetail(
            drama: Drama(id: detail.drama.id, title: detail.drama.title,
                         coverURL: detail.drama.coverURL, description: detail.drama.description,
                         episodeCount: detail.drama.episodeCount, tags: detail.drama.tags,
                         category: detail.drama.category, updateStatus: detail.drama.updateStatus,
                         shareURL: url.absoluteString),
            episodes: detail.episodes
        )
        return detail
    }

    /// 搜索：https://www.novelquickapp.com/search?q=<query>
    public func search(query: String) async throws -> [Drama] {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://\(host)/search?q=\(q)") else {
            throw HongguoParseError.fieldMissing("query")
        }
        let html = try await getHTML(url)
        guard let json = WebParser.extractRouterData(html) else { return [] }
        return try WebParser.parseCatalog(json)
    }

    /// 通用列表页（榜单 / 最新 / 分类）：传入相对路径，如 "/rank" 或 "/latest"。
    /// `page` 透传为分页参数（站点不支持时静默忽略，仍返回首屏结果）。
    public func catalog(path: String, page: Int = 1) async throws -> [Drama] {
        let safe = path.hasPrefix("/") ? path : "/" + path
        let pageSuffix = page > 1 ? "?page=\(page)" : ""
        guard let url = URL(string: "https://\(host)\(safe)\(pageSuffix)") else {
            throw HongguoParseError.fieldMissing("path")
        }
        let html = try await getHTML(url)
        guard let json = WebParser.extractRouterData(html) else { return [] }
        return try WebParser.parseCatalog(json)
    }

    /// 播放代理：请求 CDN 直链，**刻意不携带 Referer**。返回 (data, contentType)。
    public func fetchMedia(_ urlString: String) async throws -> (Data, String) {
        guard let url = URL(string: urlString) else { throw HongguoParseError.fieldMissing("url") }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // 注意：不设置 Referer —— 这是绕过字节 CDN 防盗链的关键。
        let (data, resp) = try await session.data(for: req)
        let ct = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
        return (data, ct)
    }
}
