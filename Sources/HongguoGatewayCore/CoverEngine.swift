import Foundation
import HongguoCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 封面回退引擎：源站封面失效时，按标题从豆瓣搜索取海报，经本网关代理防盗链。
/// 缓存搜索结果（标题 → 豆瓣海报 URL）避免重复请求。
public actor CoverEngine {
    public static let shared = CoverEngine()
    private init() {}

    private var cache: [String: String?] = [:]  // normalizedTitle -> posterURL (nil = 查过没有)
    private var inFlight: [String: Task<String?, Never>] = [:]

    /// 按标题查豆瓣海报 URL（无则 nil）。结果缓存。
    public func doubanPoster(forRawTitle title: String) async -> String? {
        let key = Self.normalize(title)
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }
        if let task = inFlight[key] { return await task.value }
        let task = Task<String?, Never> { await Self.searchDoubanPoster(title: key) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        cache[key] = result
        return result
    }

    /// 标题归一化：去年份/季部集话/括号/空白，提高豆瓣命中率。
    private static func normalize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        t = t.replacingOccurrences(of: #"（.*?）|\(.*?\)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s*(第?\d+季|[0-9]{4}年?|全\d+集|更新至.*)$"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// 豆瓣搜索（movie 频道），取第一条的封面。返回豆瓣图片 URL（doubanio.com）。
    private static func searchDoubanPoster(title: String) async -> String? {
        // 豆瓣 subject_suggest 接口（轻量、无需 key）
        guard let q = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://movie.douban.com/j/subject_suggest?q=\(q)") else { return nil }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("https://movie.douban.com/", forHTTPHeaderField: "Referer")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        // 优先完全同名 + 有封面的条目
        for item in arr {
            guard let t = item["title"] as? String, let img = item["img"] as? String, !img.isEmpty else { continue }
            if Self.normalize(t) == title || t.contains(title) || title.contains(Self.normalize(t)) {
                return img
            }
        }
        // 退而取第一条有封面的
        for item in arr {
            if let img = item["img"] as? String, !img.isEmpty { return img }
        }
        return nil
    }

    /// 把豆瓣图片地址改写成走本网关 image-proxy（解决 Referer 防盗链）。
    public static func proxiedImageURL(_ absolute: String, gatewayBase: String) -> String {
        let enc = absolute.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? absolute
        return "\(gatewayBase)/api/image-proxy?url=\(enc)"
    }

    // MARK: - 豆瓣热门（MoonTVPlus 首页形式：热门电影/剧集/综艺横排）

    /// 豆瓣热门条目（对齐 MoonTVPlus DoubanItem）。
    public struct DoubanHotItem: Codable, Sendable {
        public let id: String
        public let title: String
        public let poster: String      // 豆瓣图（doubanio.com），前端经 image-proxy 加载
        public let rate: String        // 评分（可空字符串）
        public let year: String
        public init(id: String, title: String, poster: String, rate: String, year: String) {
            self.id = id; self.title = title; self.poster = poster; self.rate = rate; self.year = year
        }
    }

    private var hotCache: [String: (items: [DoubanHotItem], at: Date)] = [:]

    /// 拉豆瓣「最近热门」分类列表（对齐 MoonTVPlus /api/douban/categories）。
    /// - Parameters:
    ///   - kind: movie / tv
    ///   - category: 热门 / tv / show（MoonTVPlus：电影=热门，剧集=tv，综艺=show）
    ///   - type: 全部 / tv / show
    public func doubanHot(kind: String, category: String, type: String, limit: Int = 18) async -> [DoubanHotItem] {
        let key = "\(kind)|\(category)|\(type)|\(limit)"
        if let c = hotCache[key], Date().timeIntervalSince(c.at) < 3600 { return c.items }
        let cat = category.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? category
        let typ = type.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? type
        let urlStr = "https://m.douban.com/rexxar/api/v2/subject/recent_hot/\(kind)?start=0&limit=\(limit)&category=\(cat)&type=\(typ)"
        guard let url = URL(string: urlStr) else { return [] }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("https://m.douban.com/", forHTTPHeaderField: "Referer")
        // 豆瓣国内可直连；强制直连避免系统代理境外出口被拦。
        guard let (data, resp) = try? await DirectURLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [[String: Any]] else {
            return hotCache[key]?.items ?? []
        }
        let out: [DoubanHotItem] = items.compactMap { it in
            let title = (it["title"] as? String) ?? ""
            guard !title.isEmpty else { return nil }
            var id = (it["id"] as? String) ?? ""
            if id.isEmpty, let n = it["id"] as? Int { id = String(n) }
            if id.isEmpty, let n = it["id"] as? Int64 { id = String(n) }
            let poster = (it["pic"] as? [String: Any])?["normal"] as? String
                ?? (it["pic"] as? [String: Any])?["large"] as? String ?? ""
            let rate = (it["rating"] as? [String: Any])?["value"] as? Double
            let year = (it["year"] as? String) ?? ""
            return DoubanHotItem(id: id, title: title, poster: poster,
                                 rate: rate.map { String(format: "%.1f", $0) } ?? "", year: year)
        }
        if !out.isEmpty { hotCache[key] = (out, Date()) }
        return out
    }
}
