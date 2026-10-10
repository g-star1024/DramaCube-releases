import Foundation
import HongguoGatewayCore

// MARK: - 弹幕来源（M4）
// 两路：① 弹弹play API（中文番剧/影视弹幕，按标题+集数匹配）
//       ② 本地弹幕文件（xml/ass，用户拖入或与视频同目录同名）。
// 中文内容匹配优化：标题经 DanmakuEngine.normalizeTitle 归一后匹配。

public enum DanmakuSource {

    // MARK: 弹弹play（公开弹幕聚合服务）

    /// 按标题搜索弹幕库条目 → 返回候选（animeId/episodeId 供拉弹幕）。
    public struct DandanCandidate: Sendable {
        public var animeTitle: String
        public var episodeTitle: String
        public var episodeId: Int
    }

    /// 弹弹play 搜索条目。base 可配置（默认官方 api）。
    public static func searchDandan(title: String, episode: Int?, base: String = "https://api.dandanplay.net") async -> [DandanCandidate] {
        let q = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        guard let url = URL(string: "\(base)/api/v2/search/episodes?anime=\(q)") else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let animes = json["animes"] as? [[String: Any]] else { return [] }

        var out: [DandanCandidate] = []
        for a in animes {
            let animeTitle = a["animeTitle"] as? String ?? ""
            guard let eps = a["episodes"] as? [[String: Any]] else { continue }
            for ep in eps {
                let epTitle = ep["episodeTitle"] as? String ?? ""
                let epId = (ep["episodeId"] as? Int) ?? ((ep["episodeId"] as? Double).map(Int.init) ?? 0)
                guard epId > 0 else { continue }
                out.append(DandanCandidate(animeTitle: animeTitle, episodeTitle: epTitle, episodeId: epId))
            }
        }
        return out
    }

    /// 拉取某集弹幕（comment 接口返回 XML）。
    public static func fetchDandan(episodeId: Int, base: String = "https://api.dandanplay.net") async -> [DanmakuEntry] {
        guard let url = URL(string: "\(base)/api/v2/comment/\(episodeId)?withRelated=true") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        // comment 接口返回 JSON（comments[].p / comments[].m），兼容 XML
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let comments = json["comments"] as? [[String: Any]] {
            var out: [DanmakuEntry] = []
            for c in comments {
                let text = c["m"] as? String ?? ""
                guard !text.isEmpty else { continue }
                var time: TimeInterval = 0, mode = 0, colorHex: String?
                if let p = c["p"] as? String {
                    let f = p.components(separatedBy: ",")
                    if let t = TimeInterval(f[0]) { time = t }
                    if f.count > 1, let m = Int(f[1]) { mode = (m == 5 ? 1 : (m == 4 ? 2 : 0)) }
                    if f.count > 2, let dec = Int(f[2]), dec <= 0xFFFFFF {
                        colorHex = String(format: "#%06X", dec)
                    }
                }
                out.append(DanmakuEntry(id: UUID().uuidString, time: time, text: text, color: colorHex, mode: mode))
            }
            return out.sorted { $0.time < $1.time }
        }
        // 兜底按 XML
        return DanmakuParser.parseXML(data)
    }

    /// 中文内容匹配：从候选中挑出与「本地标题+集数」最匹配的一集。
    /// 标题归一化后匹配；集数优先匹配 episodeTitle 中的数字。
    public static func pickDandan(candidates: [DandanCandidate], title: String, episode: Int?) -> DandanCandidate? {
        guard !candidates.isEmpty else { return nil }
        let normTitle = DanmakuTitleMatcher.normalizeTitle(title)
        // 先按标题过滤（归一化包含）
        let titleHits = candidates.filter {
            DanmakuTitleMatcher.titleMatch($0.animeTitle, title) ||
            DanmakuTitleMatcher.normalizeTitle($0.animeTitle).contains(normTitle)
        }
        let pool = titleHits.isEmpty ? candidates : titleHits
        // 再按集数匹配 episodeTitle 中的序号
        if let ep = episode {
            let epTag = "第\(ep)"
            let numTag = "\(ep)"
            let epHits = pool.filter {
                let t = $0.episodeTitle
                return t.contains(epTag) || t.contains("E\(ep)") || t.contains("e\(ep)") ||
                       t.contains("EP\(ep)") || t.hasSuffix(numTag) || t.contains(" \(numTag) ")
            }
            if !epHits.isEmpty { return epHits.first }
        }
        return pool.first
    }

    // MARK: 本地弹幕文件

    /// 在视频文件同目录找同名 .xml/.ass 弹幕并解析。
    public static func localDanmaku(near videoURL: URL) -> [DanmakuEntry] {
        let base = videoURL.deletingPathExtension()
        let fm = FileManager.default
        for ext in ["xml", "ass", "ssa"] {
            let candidate = base.appendingPathExtension(ext)
            if fm.fileExists(atPath: candidate.path),
               let data = try? Data(contentsOf: candidate) {
                let parsed = DanmakuParser.parse(data, filename: candidate.lastPathComponent)
                if !parsed.isEmpty { return parsed }
            }
        }
        return []
    }
}
