import Foundation
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
}
