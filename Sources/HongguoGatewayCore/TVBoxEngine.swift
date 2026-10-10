import Foundation
import HongguoCore

/// TVBox（maccms/苹果 CMS）视频源引擎。
///
/// 订阅格式：`{"sites":[{"key","name","api","searchable",...}]}`（TVBox/MoonTV 标准）。
/// 站点接口：maccms JSON —— `?ac=videolist&wd=` 搜索、`?ac=list` 最新、`?ac=detail&ids=` 详情。
/// 播放地址：`vod_play_url` = `名称$URL#名称$URL`，多线路用 `$$$` 分隔；
/// 优先选含 "m3u8" 的线路（share/解析类链接大多不可直接播）。
///
/// 订阅 JSON 缓存在用户目录（~/Library/Application Support/DramaCube/tvbox-sub.json），
/// 网关独立进程与 App 进程内启动都能读到同一份。
public actor TVBoxEngine {
    public static let shared = TVBoxEngine()

    // MARK: - 数据模型

    public struct Site: Codable, Sendable, Identifiable {
        public let key: String
        public let name: String
        public let api: String
        public var id: String { key }
    }

    public struct TestResult: Codable, Sendable {
        public let key: String
        public let ok: Bool
        public let latencyMs: Int
        public let count: Int
        public let error: String?
    }

    /// 站点频道（maccms class 分类，type_id → type_name）。
    public struct Category: Codable, Sendable, Identifiable {
        public let typeId: Int
        public let name: String
        public var id: Int { typeId }
    }

    struct Subscription: Codable, Sendable {
        var sites: [Site]
    }

    // MARK: - 缓存与状态

    private var sites: [Site] = []
    private var lastLoad = Date.distantPast

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DramaCube", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tvbox-sub.json")
    }

    private init() {}

    // MARK: - 订阅管理

    /// 从 URL 导入订阅（TVBox 格式）。返回站点数。
    @discardableResult
    public func importSubscription(url: String) async throws -> Int {
        guard let u = URL(string: url) else { throw TVBoxError.badURL }
        var req = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TVBoxError.fetchFailed((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let sub: Subscription
        do {
            sub = try JSONDecoder().decode(Subscription.self, from: data)
        } catch {
            throw TVBoxError.parseFailed
        }
        // 仅保留 maccms 类源（api 非空）
        let cleaned = sub.sites.filter { !$0.api.isEmpty && $0.api.hasPrefix("http") }
        guard !cleaned.isEmpty else { throw TVBoxError.noSites }
        sites = cleaned
        lastLoad = Date()
        try data.write(to: Self.cacheURL, options: .atomic)
        return cleaned.count
    }

    /// 已导入的站点列表（先尝试读缓存）。
    public func allSites() async -> [Site] {
        await ensureLoaded()
        return sites
    }

    public var hasSubscription: Bool {
        get async {
            await ensureLoaded()
            return !sites.isEmpty
        }
    }

    private func ensureLoaded() async {
        guard sites.isEmpty, Date().timeIntervalSince(lastLoad) > 5 else { return }
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let sub = try? JSONDecoder().decode(Subscription.self, from: data) else { return }
        sites = sub.sites.filter { !$0.api.isEmpty && $0.api.hasPrefix("http") }
        lastLoad = Date()
    }

    private func site(key: String) async throws -> Site {
        await ensureLoaded()
        guard let s = sites.first(where: { $0.key == key }) else { throw TVBoxError.siteNotFound }
        return s
    }

    // MARK: - 连通性测试

    /// 单源测试：请求首页列表，校验 JSON 结构。超时 12s。
    public func test(site s: Site) async -> TestResult {
        let t0 = Date()
        do {
            let list = try await fetchList(site: s, page: 1)
            return TestResult(key: s.key, ok: true,
                              latencyMs: Int(Date().timeIntervalSince(t0) * 1000),
                              count: list.count, error: nil)
        } catch {
            return TestResult(key: s.key, ok: false,
                              latencyMs: Int(Date().timeIntervalSince(t0) * 1000),
                              count: 0, error: String(describing: error))
        }
    }

    /// 批量测试（限并发 6，避免把站点打挂）。
    public func testAll(keys: [String]?) async -> [TestResult] {
        await ensureLoaded()
        let targets = keys == nil ? sites : sites.filter { keys!.contains($0.key) }
        var results: [TestResult] = []
        results.reserveCapacity(targets.count)
        await withTaskGroup(of: TestResult.self) { group in
            var pending = targets.makeIterator()
            var inFlight = 0
            // 初始填 6 个
            for _ in 0..<6 {
                if let s = pending.next() {
                    group.addTask { await self.test(site: s) }
                    inFlight += 1
                }
            }
            while let r = await group.next() {
                results.append(r)
                inFlight -= 1
                if let s = pending.next() {
                    group.addTask { await self.test(site: s) }
                    inFlight += 1
                }
            }
        }
        return results
    }

    // MARK: - 列表 / 搜索 / 详情

    /// 最新列表：`?ac=list&pg=n`，可选 `typeId` 频道过滤（t 参数）。
    public func latest(siteKey: String, page: Int, typeId: Int? = nil) async throws -> [Drama] {
        let s = try await site(key: siteKey)
        return try await fetchList(site: s, page: page, typeId: typeId).map { Self.toDrama($0, siteKey: s.key) }
    }

    // MARK: - 频道分类（class）

    /// 每站频道缓存（type_id 与站点的对应关系不变，进程内永久缓存即可）。
    private var classCache: [String: [Category]] = [:]
    private var classFetchedAt: [String: Date] = [:]

    /// 站点频道列表：优先取 ac=list 响应的 class 字段（标准 maccms），
    /// 站点不返回 class 时降级用 ac=videolist 翻页归并 vod 的 type_id+type_name。
    public func categories(siteKey: String) async -> [Category] {
        if let cached = classCache[siteKey], !cached.isEmpty { return cached }
        guard let s = try? await site(key: siteKey) else { return [] }
        // ① 标准途径：ac=list 响应的 class 字段
        var comps = URLComponents(string: s.api)
        comps?.queryItems = [URLQueryItem(name: "ac", value: "list"), URLQueryItem(name: "pg", value: "1")]
        if let u = comps?.url, let resp = try? await fetchResponse(u), let cls = resp.class, !cls.isEmpty {
            let cats = cls.compactMap { c -> Category? in
                guard let tid = c.type_id?.intValue, let name = c.type_name, !name.isEmpty else { return nil }
                return Category(typeId: tid, name: name)
            }.sorted { $0.typeId < $1.typeId }
            if !cats.isEmpty {
                classCache[siteKey] = cats
                classFetchedAt[siteKey] = Date()
                return cats
            }
        }
        // ② 降级：ac=videolist 翻页归并（最多 10 页，≥8 频道或耗尽即停）
        var seen: [Int: String] = [:]
        for page in 1...10 {
            guard let vods = try? await fetchVodListFull(site: s, page: page), !vods.isEmpty else { break }
            for v in vods {
                if let tid = v.type_id?.intValue, let name = v.type_name, !name.isEmpty, seen[tid] == nil {
                    seen[tid] = name
                }
            }
            if seen.count >= 8 || vods.count < 20 { break }
        }
        let cats = seen.map { Category(typeId: $0.key, name: $0.value) }.sorted { $0.typeId < $1.typeId }
        if !cats.isEmpty {
            classCache[siteKey] = cats
            classFetchedAt[siteKey] = Date()
        }
        return cats
    }

    /// 搜索：`?ac=videolist&wd=q&pg=n`。
    public func search(siteKey: String, query: String, page: Int = 1) async throws -> [Drama] {
        let s = try await site(key: siteKey)
        var comps = URLComponents(string: s.api)
        comps?.queryItems = [
            URLQueryItem(name: "ac", value: "videolist"),
            URLQueryItem(name: "wd", value: query),
            URLQueryItem(name: "pg", value: String(page)),
        ]
        guard let u = comps?.url else { throw TVBoxError.badURL }
        let vods = try await fetchVods(u)
        return vods.map { Self.toDrama($0, siteKey: s.key) }
    }

    /// 详情：`?ac=detail&ids=id`，解析播放地址到 Episode 直链。
    /// Drama.id 带 `tvbox|<siteKey>|` 前缀，搜索/列表页拿到的卡片可直接复用播放。
    public func detail(siteKey: String, vodId: String) async throws -> DramaDetail {
        let s = try await site(key: siteKey)
        var comps = URLComponents(string: s.api)
        comps?.queryItems = [
            URLQueryItem(name: "ac", value: "detail"),
            URLQueryItem(name: "ids", value: vodId),
        ]
        guard let u = comps?.url else { throw TVBoxError.badURL }
        let vods = try await fetchVods(u)
        guard let v = vods.first else { throw TVBoxError.noSites }

        let drama = Self.toDrama(v, siteKey: s.key)
        // 详情接口信息更全，覆盖简介/状态
        let episodes = Self.parseEpisodes(v)
        return DramaDetail(drama: drama, episodes: episodes, related: nil)
    }

    // MARK: - 播放地址解析（网关代理包装由调用方处理）

    /// 解析单集真实播放 URL（选 m3u8 优先线路）。
    public func resolvePlayURL(siteKey: String, vodId: String, episodeIndex: Int) async throws -> String {
        let s = try await site(key: siteKey)
        var comps = URLComponents(string: s.api)
        comps?.queryItems = [
            URLQueryItem(name: "ac", value: "detail"),
            URLQueryItem(name: "ids", value: vodId),
        ]
        guard let u = comps?.url else { throw TVBoxError.badURL }
        let vods = try await fetchVods(u)
        guard let v = vods.first else { throw TVBoxError.noSites }
        let eps = Self.parseEpisodes(v)
        guard eps.indices.contains(episodeIndex), let url = eps[episodeIndex].playURL, !url.isEmpty else {
            throw TVBoxError.parseFailed
        }
        return url
    }

    // MARK: - 内部实现

    private struct Vod: Decodable {
        let vod_id: JSONValue?
        let vod_name: String?
        let vod_pic: String?
        let vod_remarks: String?
        let vod_total: JSONValue?
        let type_id: JSONValue?
        let type_name: String?
        let vod_year: String?
        let vod_area: String?
        let vod_content: String?
        let vod_blurb: String?
        let vod_play_from: String?
        let vod_play_url: String?
    }

    /// JSON 值兼容（有的站把数字输出成字符串）。
    private enum JSONValue: Decodable {
        case int(Int), string(String), other
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let i = try? c.decode(Int.self) { self = .int(i); return }
            if let s = try? c.decode(String.self) { self = .string(s); return }
            self = .other
        }
        var intValue: Int? {
            switch self {
            case .int(let i): return i
            case .string(let s): return Int(s)
            case .other: return nil
            }
        }
        var stringValue: String? {
            switch self {
            case .int(let i): return String(i)
            case .string(let s): return s
            case .other: return nil
            }
        }
    }

    private struct VodListResponse: Decodable {
        let list: [Vod]?
        let `class`: [ClassItem]?
    }

    /// maccms ac=list 响应里的标准频道分类（type_id → type_name）。
    private struct ClassItem: Decodable {
        let type_id: JSONValue?
        let type_name: String?
    }

    private func fetchList(site s: Site, page: Int, typeId: Int? = nil) async throws -> [Vod] {
        var comps = URLComponents(string: s.api)
        var items = [
            URLQueryItem(name: "ac", value: "list"),
            URLQueryItem(name: "pg", value: String(page)),
        ]
        if let t = typeId { items.append(URLQueryItem(name: "t", value: String(t))) }
        comps?.queryItems = items
        guard let u = comps?.url else { throw TVBoxError.badURL }
        return try await fetchVods(u)
    }

    /// ac=videolist 全量字段拉取（含 type_id/type_name），供频道归并。
    private func fetchVodListFull(site s: Site, page: Int) async throws -> [Vod] {
        var comps = URLComponents(string: s.api)
        comps?.queryItems = [
            URLQueryItem(name: "ac", value: "videolist"),
            URLQueryItem(name: "pg", value: String(page)),
        ]
        guard let u = comps?.url else { throw TVBoxError.badURL }
        return try await fetchVods(u)
    }

    private func fetchVods(_ url: URL) async throws -> [Vod] {
        try await fetchResponse(url).list ?? []
    }

    /// 拉取并解码完整 maccms 响应（含 list 与 class）。
    private func fetchResponse(_ url: URL) async throws -> VodListResponse {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TVBoxError.fetchFailed((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try JSONDecoder().decode(VodListResponse.self, from: data)
    }

    /// Vod → Drama（id 带 tvbox 前缀，便于路由识别与进度隔离）。
    private static func toDrama(_ v: Vod, siteKey: String) -> Drama {
        let vid = v.vod_id?.stringValue ?? ""
        let remarks = v.vod_remarks?.trimmingCharacters(in: .whitespaces)
        var count = v.vod_total?.intValue
        if (count ?? 0) == 0 {
            // 从 "更新至第80集" / "全80集" 提取
            if let r = remarks, let m = r.range(of: #"(\d+)\s*集"#, options: .regularExpression) {
                count = Int(r[m].dropLast().trimmingCharacters(in: .whitespaces).filter { $0.isNumber }.description)
            }
        }
        return Drama(
            id: "tvbox|\(siteKey)|\(vid)",
            title: v.vod_name ?? "未命名",
            coverURL: v.vod_pic?.isEmpty == false ? v.vod_pic : nil,
            description: (v.vod_content ?? v.vod_blurb)?.strippingHTML,
            episodeCount: (count ?? 0) > 0 ? count : nil,
            tags: [v.type_name, v.vod_year, v.vod_area].compactMap { $0 }.filter { !$0.isEmpty },
            category: v.type_name,
            updateStatus: remarks?.isEmpty == false ? remarks : nil,
            shareURL: nil
        )
    }

    /// 解析播放列表：`名称$URL#名称$URL`，多线路 `$$$` 分隔，m3u8 线路优先。
    private static func parseEpisodes(_ v: Vod) -> [Episode] {
        guard let playURL = v.vod_play_url, !playURL.isEmpty else { return [] }
        let lines = playURL.components(separatedBy: "$$$")
        let froms = (v.vod_play_from ?? "").components(separatedBy: "$$$")
        // 选线路：优先名字或 URL 含 m3u8 的
        var chosenIdx = 0
        for (i, line) in lines.enumerated() {
            let from = i < froms.count ? froms[i].lowercased() : ""
            if from.contains("m3u8") || line.lowercased().contains(".m3u8") { chosenIdx = i; break }
        }
        guard lines.indices.contains(chosenIdx) else { return [] }
        let items = lines[chosenIdx].components(separatedBy: "#").filter { !$0.isEmpty }
        var eps: [Episode] = []
        for (i, item) in items.enumerated() {
            let parts = item.components(separatedBy: "$")
            let url = parts.count >= 2 ? parts[1...].joined(separator: "$").trimmingCharacters(in: .whitespaces) : ""
            let name = parts.first?.trimmingCharacters(in: .whitespaces) ?? "第\(i + 1)集"
            guard url.hasPrefix("http") else { continue }
            eps.append(Episode(id: "\(i)", index: i + 1, title: name, playURL: url, duration: nil))
        }
        return eps
    }

    public enum TVBoxError: Error, LocalizedError {
        case badURL, fetchFailed(Int), parseFailed, noSites, siteNotFound
        public var errorDescription: String? {
            switch self {
            case .badURL: return "订阅地址无效"
            case .fetchFailed(let c): return "请求失败（HTTP \(c)）"
            case .parseFailed: return "数据格式无法解析"
            case .noSites: return "订阅中没有可用视频源"
            case .siteNotFound: return "视频源不存在（可能未导入订阅）"
            }
        }
    }
}

private extension String {
    /// 粗略去 HTML 标签（简介字段常带 <p>/<br>）。
    var strippingHTML: String {
        var s = self.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
