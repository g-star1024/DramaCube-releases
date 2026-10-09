import Foundation

/// 落地页 / 列表页解析器。
///
/// 红果分享站 `novelquickapp.com` 的页面会把业务数据塞进 `window._ROUTER_DATA = {...}` 内联 JSON。
/// 该 JSON 字段名随版本变动，因此这里采用「候选键名 + 递归查找」的稳健策略，
/// 不硬编码具体路径，运行时对任意结构都能尽力提取。
public enum HongguoParseError: Error, LocalizedError, Sendable {
    case routerDataNotFound
    case fieldMissing(String)
    case invalidJSON
    public var errorDescription: String? {
        switch self {
        case .routerDataNotFound: return "未在页面中找到 _ROUTER_DATA"
        case .fieldMissing(let k): return "缺少关键字段: \(k)"
        case .invalidJSON: return "页面内联 JSON 解析失败"
        }
    }
}

public struct WebParser {

    /// 候选键名（小写包含匹配）。新增站点字段时在此追加即可。
    private static let titleKeys      = ["title", "name", "drama_name", "album_name"]
    private static let coverKeys      = ["cover", "cover_url", "poster", "img", "image", "pic"]
    private static let descKeys       = ["description", "desc", "intro", "brief", "subtitle"]
    private static let playURLKeys    = ["play_url", "video_url", "url", "playurl", "src"]
    private static let episodeKeys    = ["episodes", "album_video_list", "video_list", "list", "tracks"]
    private static let idKeys         = ["id", "album_id", "drama_id", "vid"]

    /// 从 HTML 中抽取 `window._ROUTER_DATA = {...}` 的 JSON Data（括号配对，兼容字符串内大括号）。
    public static func extractRouterData(_ html: String) -> Data? {
        let patterns = ["window\\._ROUTER_DATA\\s*=\\s*", "_ROUTER_DATA\\s*=\\s*"]
        for p in patterns {
            guard let range = html.range(of: p, options: .regularExpression) else { continue }
            let tail = String(html[range.upperBound...])
            guard let start = tail.firstIndex(of: "{") else { continue }
            var depth = 0, inStr = false, esc = false
            var end = tail.endIndex
            for i in tail.indices {
                let c = tail[i]
                if esc { esc = false; continue }
                if c == "\\" { esc = true; continue }
                if c == "\"" { inStr.toggle(); continue }
                if !inStr {
                    if c == "{" { depth += 1 }
                    else if c == "}" { depth -= 1; if depth == 0 { end = i; break } }
                }
            }
            let jsonStr = String(tail[start...end])
            if let d = jsonStr.data(using: .utf8) { return d }
        }
        return nil
    }

    /// 递归在任意 JSON 容器中按候选键（小写包含）收集所有匹配值。
    public static func findValues(_ obj: Any, candidates: [String]) -> [Any] {
        var out: [Any] = []
        if let dict = obj as? [String: Any] {
            for (k, v) in dict {
                if candidates.contains(where: { k.lowercased().contains($0) }) { out.append(v) }
                out.append(contentsOf: findValues(v, candidates: candidates))
            }
        } else if let arr = obj as? [Any] {
            for e in arr { out.append(contentsOf: findValues(e, candidates: candidates)) }
        }
        return out
    }

    private static func firstString(_ values: [Any]) -> String? {
        values.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }.first(where: { !$0.isEmpty })
    }
    private static func firstInt(_ values: [Any]) -> Int? {
        if let n = values.first(where: { $0 is Int }) as? Int { return n }
        if let s = firstString(values), let n = Int(s) { return n }
        return nil
    }

    /// 仅查传入字典顶层（不递归），精确键名优先，其次子串包含匹配。
    private static func topValue(_ dict: [String: Any], candidates: [String]) -> String? {
        for c in candidates where dict[c] is String {
            if let s = dict[c] as? String, !s.isEmpty { return s }
        }
        for (k, v) in dict where candidates.contains(where: { k.lowercased().contains($0) }) {
            if let s = v as? String, !s.isEmpty { return s }
        }
        return nil
    }

    /// 解析落地页 JSON -> DramaDetail（顶层字段优先，episodes 单独提取）。
    public static func parseDetail(_ data: Data) throws -> DramaDetail {
        guard let top = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HongguoParseError.invalidJSON
        }
        let id = topValue(top, candidates: idKeys) ?? "unknown"
        guard let title = topValue(top, candidates: titleKeys) else {
            throw HongguoParseError.fieldMissing("title")
        }
        let cover = topValue(top, candidates: coverKeys)
        let desc  = topValue(top, candidates: descKeys)

        var episodes: [Episode] = []
        if let list = findValues(top, candidates: episodeKeys).compactMap({ $0 as? [Any] }).first {
            for (i, e) in list.enumerated() {
                guard let d = e as? [String: Any] else { continue }
                let eid = topValue(d, candidates: idKeys) ?? "\(id)-\(i)"
                let etitle = topValue(d, candidates: titleKeys) ?? "第 \(i + 1) 集"
                let eurl = topValue(d, candidates: playURLKeys)
                let dur = firstInt([d["duration"] as Any, d["time"] as Any, d["length"] as Any])
                episodes.append(Episode(id: eid, index: i + 1, title: etitle, playURL: eurl, duration: dur))
            }
        }

        let drama = Drama(id: id, title: title, coverURL: cover, description: desc,
                          episodeCount: episodes.isEmpty ? nil : episodes.count, shareURL: nil)
        return DramaDetail(drama: drama, episodes: episodes)
    }

    /// 解析列表页 JSON -> [Drama]。
    public static func parseCatalog(_ data: Data) throws -> [Drama] {
        guard let top = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HongguoParseError.invalidJSON
        }
        let cardCandidates = ["album", "drama", "item", "video", "card", "data", "list"]
        var list: [[String: Any]] = []
        if let arr = top["list"] as? [[String: Any]] { list = arr }
        else if let arr = top["data"] as? [[String: Any]] { list = arr }
        else {
            for (k, v) in top where cardCandidates.contains(where: { k.lowercased().contains($0) }) {
                if let arr = v as? [[String: Any]] { list = arr; break }
            }
        }
        var out: [Drama] = []
        for d in list {
            guard let title = topValue(d, candidates: titleKeys) else { continue }
            let id = topValue(d, candidates: idKeys) ?? UUID().uuidString
            let cover = topValue(d, candidates: coverKeys)
            let cnt = firstInt([d["episode_count"] as Any, d["total"] as Any, d["count"] as Any, d["num"] as Any])
            out.append(Drama(id: id, title: title, coverURL: cover, episodeCount: cnt))
        }
        return out
    }
}
