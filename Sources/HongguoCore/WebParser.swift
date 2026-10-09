import Foundation

/// 落地页 / 列表页解析器。
///
/// 红果官网 `hongguoduanju.com`（原 novelquickapp.com 已 301 迁移，2026-10 站点改版）：
///  - 页面数据载体为内联 `_ROUTER_DATA = {...}`（Modern.js SSR，赋值不带 `window.` 前缀）；
///  - 详情：`loaderData.detail_page.seriesDetail`（含完整 `vid_list`）；
///  - 播放：`/player/<sid>/<vid>` 的 loaderData 任意块含 `video_player_info.main_url`（CDN 直链，免签名）；
///  - 榜单 / 搜索：结果以 DOM 卡片渲染（`href="/detail?series_id=X"` + `<img alt>`）。
/// 字段名随版本变动，因此统一采用「候选键名 + 递归查找」的稳健策略。
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

    /// 候选键名（小写包含匹配）。站点字段变动时在此追加即可。
    private static let titleKeys      = ["series_name", "series_title", "title", "name", "album_name"]
    private static let coverKeys      = ["series_cover", "cover", "cover_url", "poster", "img", "image", "pic"]
    private static let descKeys       = ["series_intro", "description", "desc", "intro", "brief"]
    private static let playURLKeys    = ["play_url", "video_url", "url", "playurl", "src"]
    private static let episodeKeys    = ["episodes", "album_video_list", "video_list", "list", "tracks"]
    private static let idKeys         = ["series_id", "album_id", "drama_id", "id", "vid"]
    private static let countKeys      = ["episode_cnt", "episode_count", "episodeCount", "total", "count", "num"]
    private static let statusKeys     = ["episode_right_text"]

    /// 从 HTML 中抽取 `_ROUTER_DATA = {...}` 的 JSON Data（括号配对，兼容字符串内大括号）。
    public static func extractRouterData(_ html: String) -> Data? {
        // 新站点赋值不带 window. 前缀；两种形态都兜住。
        let patterns = ["window\\._ROUTER_DATA\\s*=\\s*", "(?<![A-Za-z0-9_])_ROUTER_DATA\\s*=\\s*"]
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

    // MARK: - 递归查找工具

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

    /// 递归查找第一个匹配键的值（深度优先）。
    public static func findDictValue(_ obj: Any, key: String) -> Any? {
        if let dict = obj as? [String: Any] {
            if let v = dict[key] { return v }
            for (_, v) in dict {
                if let hit = findDictValue(v, key: key) { return hit }
            }
        } else if let arr = obj as? [Any] {
            for e in arr {
                if let hit = findDictValue(e, key: key) { return hit }
            }
        }
        return nil
    }

    /// 标题合理性：过滤 SEO/配置类杂项（如 "www.hongguoduanju.com"）。
    private static func isPlausibleTitle(_ t: String) -> Bool {
        !t.isEmpty && !t.contains("www.") && !t.hasPrefix("http") && t.range(of: #"^\d+$"#, options: .regularExpression) == nil
    }

    /// 递归收集所有「剧集条目字典」（含 series_id 且含标题键）。
    public static func findSeriesDicts(_ obj: Any) -> [[String: Any]] {
        var out: [[String: Any]] = []
        var seen = Set<String>()
        func walk(_ o: Any) {
            if let dict = o as? [String: Any] {
                let id = topValue(dict, candidates: idKeys)
                let title = topValue(dict, candidates: titleKeys)
                // 剧集 id 为长数字串（19 位 series_id）；过滤 tag/分类等 id+name 小字典与 SEO 杂项
                if let id, let title, id.count >= 10, id.allSatisfy({ $0.isNumber }),
                   isPlausibleTitle(title), !seen.contains(id) {
                    seen.insert(id)
                    out.append(dict)
                }
                for (_, v) in dict { walk(v) }
            } else if let arr = o as? [Any] {
                for e in arr { walk(e) }
            }
        }
        walk(obj)
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

    private static func topInt(_ dict: [String: Any], candidates: [String]) -> Int? {
        for c in candidates where dict[c] != nil {
            if let n = firstInt([dict[c]!]) { return n }
        }
        for (k, v) in dict where candidates.contains(where: { k.lowercased().contains($0) }) {
            if let n = firstInt([v]) { return n }
        }
        return nil
    }

    /// 剧集条目字典 → Drama（站点字段统一映射）。
    private static func dramaFromSeriesDict(_ d: [String: Any]) -> Drama? {
        guard let title = topValue(d, candidates: titleKeys) else { return nil }
        let id = topValue(d, candidates: idKeys) ?? UUID().uuidString
        let tagsArr = (d["tags"] as? [Any]) ?? (d["category_list"] as? [Any]) ?? []
        let tags = tagsArr.compactMap { ($0 as? String) ?? (($0 as? [String: Any])?["name"] as? String) }
        return Drama(id: id, title: title, coverURL: topValue(d, candidates: coverKeys),
                     description: topValue(d, candidates: descKeys),
                     episodeCount: topInt(d, candidates: countKeys),
                     tags: tags, updateStatus: topValue(d, candidates: statusKeys))
    }

    // MARK: - 详情页（loaderData.detail_page.seriesDetail）

    /// 解析详情页 `_ROUTER_DATA` → DramaDetail。
    /// 选集来自 `seriesDetail.vid_list`（播放直链在点播时经 /player/<sid>/<vid> 解析），
    /// 相关推荐来自 `recommendations.videoList`。
    public static func parseSeriesDetail(_ data: Data) throws -> DramaDetail {
        guard let top = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HongguoParseError.invalidJSON
        }
        // 精确定位 seriesDetail 键（recommendations 在文档序中靠前，不能用「首个含 vid_list 的字典」）
        guard let series = findDictValue(top, key: "seriesDetail") as? [String: Any],
              let vids = series["vid_list"] as? [Any], !vids.isEmpty else {
            throw HongguoParseError.fieldMissing("seriesDetail")
        }
        let id = topValue(series, candidates: idKeys) ?? "unknown"
        let drama = Drama(id: id,
                          title: topValue(series, candidates: titleKeys) ?? "未知剧集",
                          coverURL: topValue(series, candidates: coverKeys),
                          description: topValue(series, candidates: descKeys),
                          episodeCount: topInt(series, candidates: countKeys) ?? vids.count,
                          tags: (series["tags"] as? [Any])?.compactMap { $0 as? String } ?? [],
                          updateStatus: topValue(series, candidates: statusKeys))
        let episodes = vids.enumerated().compactMap { idx, v -> Episode? in
            guard let vid = v as? String, !vid.isEmpty else { return nil }
            return Episode(id: vid, index: idx + 1, title: "第 \(idx + 1) 集", playURL: nil)
        }
        // 相关推荐：排除自身
        let related = findSeriesDicts(top)
            .filter { topValue($0, candidates: idKeys) != id }
            .compactMap(dramaFromSeriesDict)
        return DramaDetail(drama: drama, episodes: episodes, related: Array(related.prefix(12)))
    }

    // MARK: - 播放页（video_player_info.main_url）

    /// 解析播放页 `_ROUTER_DATA` → CDN 直链（main_url）。
    public static func parseMainURL(_ data: Data) -> String? {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return findValues(top, candidates: ["main_url"]).compactMap { $0 as? String }.first
    }

    // MARK: - 列表页（_ROUTER_DATA：首页 homeSections / 类目 recommendList）

    /// 解析列表页 `_ROUTER_DATA` → [Drama]（递归收集全部剧集条目并去重）。
    public static func parseSeriesList(_ data: Data) -> [Drama] {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return findSeriesDicts(top).compactMap(dramaFromSeriesDict)
    }

    // MARK: - DOM 卡片（榜单 / 搜索结果）

    /// 解析榜单 / 搜索页 SSR DOM 卡片：`href="/detail?series_id=X"` + 封面 `<img alt>`。
    public static func parseCardsHTML(_ html: String) -> [Drama] {
        var out: [Drama] = []
        var seen = Set<String>()
        let anchorRE = try! NSRegularExpression(pattern: #"href="/detail\?series_id=(\d+)""#)
        let imgRE = try! NSRegularExpression(pattern: #"<img[^>]*src="(https?://[^"]+)"[^>]*alt="([^"]*)""#)
        let ns = html as NSString
        func sub(_ r: NSRange) -> String? {
            guard r.location != NSNotFound else { return nil }
            return ns.substring(with: r)
        }
        for m in anchorRE.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let id = sub(m.range(at: 1)) ?? ""
            guard !id.isEmpty, !seen.contains(id) else { continue }
            // 向前找窗口内的封面 img（卡片头部紧邻锚点）
            let window = NSRange(location: m.range.location, length: min(4000, ns.length - m.range.location))
            var cover: String?, title: String?
            if let im = imgRE.firstMatch(in: html, range: window) {
                cover = sub(im.range(at: 1))
                let alt = sub(im.range(at: 2)) ?? ""
                title = alt.hasSuffix("封面") ? String(alt.dropLast(2)) : alt
            }
            // alt 缺失时退化为 aria-label="查看X"
            if title == nil {
                let ariaRE = try! NSRegularExpression(pattern: #"aria-label="查看([^"]+)""#)
                if let am = ariaRE.firstMatch(in: html, range: window) {
                    title = sub(am.range(at: 1))
                }
            }
            guard let t = title, isPlausibleTitle(t) else { continue }
            seen.insert(id)
            out.append(Drama(id: id, title: t, coverURL: cover))
        }
        return out
    }

    // MARK: - 旧版分享落地页解析（保留兼容）

    /// 解析旧版落地页 JSON -> DramaDetail（顶层字段优先，episodes 单独提取）。
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

    /// 解析通用列表 JSON -> [Drama]（旧版结构兼容）。
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
        return list.compactMap(dramaFromSeriesDict)
    }
}
