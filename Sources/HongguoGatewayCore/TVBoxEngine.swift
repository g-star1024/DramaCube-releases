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
        var urls: [String]?          // 已导入成功的订阅地址（旧版缓存无此字段，向后兼容）
    }

    /// 内置默认采集源（路线 D：maccms 联盟采集站）。
    /// 首次启动且无订阅时自动导入，不直接暴露给用户选择——作为「开箱即用」兜底源。
    /// 已验证可用的 maccms JSON 接口站。
    public static let builtinSiteAPIs: [(name: String, api: String)] = [
        ("光速资源", "https://api.guangsuapi.com/api.php/provide/vod"),
        ("U酷资源", "https://api.ukuapi.com/api.php/provide/vod"),
        ("无尽资源", "https://api.wujinapi.cc/api.php/provide/vod"),
        ("1080资源", "https://api.1080zyku.com/inc/api_mac10.php"),
    ]

    /// 单个订阅地址的导入结果。
    public struct ImportResult: Codable, Sendable {
        public let url: String
        public let added: Int        // 新增站点数
        public let error: String?    // nil = 成功
        public var ok: Bool { error == nil }
        public init(url: String, added: Int, error: String?) {
            self.url = url; self.added = added; self.error = error
        }
    }

    // MARK: - 缓存与状态

    private var sites: [Site] = []
    private var lastLoad = Date.distantPast
    /// 已导入成功的订阅地址（持久化，重启后可「更新订阅」重新拉取）。
    private var subscriptionURLs: [String] = []

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DramaCube", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tvbox-sub.json")
    }

    private init() {}

    // MARK: - 订阅管理

    /// 从 URL 导入订阅（TVBox 格式）。支持一次传多个地址（换行/逗号分隔），
    /// 与已有站点按 api 排重合并（重复的不重复计数）。
    /// 单地址失败跳过继续其余，返回每个地址的导入明细（成功的新增数/失败原因）。
    /// 成功的地址持久化到订阅列表（重启后可「更新订阅」重拉）。
    @discardableResult
    public func importSubscriptionDetailed(url: String) async -> [ImportResult] {
        let urls = url
            .components(separatedBy: CharacterSet(charactersIn: "\n,;，；"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("http") }
        guard !urls.isEmpty else { return [ImportResult(url: url, added: 0, error: "订阅地址无效")] }

        await ensureLoaded()
        var results: [ImportResult] = []
        var dirty = false
        for u in urls {
            do {
                let list = try await Self.fetchSubscription(url: u)
                let cleaned = list.filter { !$0.api.isEmpty && $0.api.hasPrefix("http") }
                var existingApis = Set(sites.map { Self.normalizeAPI($0.api) })
                var added = 0
                for s in cleaned {
                    let key = Self.normalizeAPI(s.api)
                    if existingApis.insert(key).inserted {
                        sites.append(s)
                        added += 1
                    }
                }
                if !subscriptionURLs.contains(u) { subscriptionURLs.append(u) }
                dirty = true
                results.append(ImportResult(url: u, added: added, error: nil))
            } catch {
                results.append(ImportResult(url: u, added: 0, error: error.localizedDescription))
            }
        }
        if dirty {
            lastLoad = Date()
            try? JSONEncoder().encode(Subscription(sites: sites, urls: subscriptionURLs)).write(to: Self.cacheURL, options: .atomic)
        }
        return results
    }

    /// 已导入成功的订阅地址列表。
    public func savedSubscriptionURLs() async -> [String] {
        await ensureLoaded()
        return subscriptionURLs
    }

    /// 删除一个订阅地址（不删除其已导入的站点——站点可能也被其他地址提供）。
    public func removeSubscriptionURL(_ url: String) async {
        await ensureLoaded()
        subscriptionURLs.removeAll { $0 == url }
        try? JSONEncoder().encode(Subscription(sites: sites, urls: subscriptionURLs)).write(to: Self.cacheURL, options: .atomic)
    }

    /// 重新拉取全部已存订阅地址（「更新订阅」），返回每地址明细。
    @discardableResult
    public func refreshAllSubscriptions() async -> [ImportResult] {
        await ensureLoaded()
        let urls = subscriptionURLs
        guard !urls.isEmpty else { return [] }
        return await importSubscriptionDetailed(url: urls.joined(separator: "\n"))
    }

    /// api 归一化（去尾斜杠/去协议差异），用于排重键。
    private static func normalizeAPI(_ api: String) -> String {
        var s = api.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasSuffix("/") { s.removeLast() }
        return s.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
    }

    /// 拉取并解析单个订阅地址（不做排重/持久化）。
    private static func fetchSubscription(url: String) async throws -> [Site] {
        guard let u = URL(string: url) else { throw TVBoxError.badURL }
        var req = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TVBoxError.fetchFailed((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let sub = try JSONDecoder().decode(Subscription.self, from: data)
        return sub.sites
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
        if let data = try? Data(contentsOf: Self.cacheURL),
           let sub = try? JSONDecoder().decode(Subscription.self, from: data) {
            sites = sub.sites.filter { !$0.api.isEmpty && $0.api.hasPrefix("http") }
            subscriptionURLs = sub.urls ?? []
            lastLoad = Date()
        }
        // v1.2.3：去掉内置采集源自动注入 + 清掉历史缓存里曾由本 App 注入的内置源（用户要求不预置）。
        // 只清「key = 归一化 API」的注入项（seedBuiltinSites 生成的 key 形如 api_ukuapi_com_...），
        // 不动用户订阅导入的源（key 形如 api_6/api_18，即使域名与内置源同族——订阅内容用户拍板保留）。
        let builtinKeys = Set(Self.builtinSiteAPIs.map { Self.normalizeAPI($0.api) })
        let before = sites.count
        sites.removeAll { builtinKeys.contains($0.key) }
        if sites.count != before {
            try? JSONEncoder().encode(Subscription(sites: sites, urls: subscriptionURLs)).write(to: Self.cacheURL, options: .atomic)
        }
        // 站点完全来自用户订阅导入；空订阅时视频源页引导用户添加订阅。
    }

    private func site(key: String) async throws -> Site {
        await ensureLoaded()
        guard let s = sites.first(where: { $0.key == key }) else { throw TVBoxError.siteNotFound }
        return s
    }

    // MARK: - 连通性测试

    /// 单源测试：先测首页列表，再测搜索接口（ac=videolist&wd=），两者都通才算可用。
    /// 只测首页会漏掉「首页 ok 但搜索超时/403」的假在线源（采集站锁大陆 IP 时典型）。
    /// 首页/搜索各 8s 短超时。
    public func test(site s: Site) async -> TestResult {
        let t0 = Date()
        do {
            // ① 首页列表：校验 JSON 结构（快速判活）
            _ = try await fetchList(site: s, page: 1, timeoutSecs: 8)
            // ② 搜索接口：ac=videolist&wd=，真实检索能力（决定该源能不能被搜索到）
            var comps = URLComponents(string: s.api)
            comps?.queryItems = [
                URLQueryItem(name: "ac", value: "videolist"),
                URLQueryItem(name: "wd", value: "电影"),
                URLQueryItem(name: "pg", value: "1"),
            ]
            guard let u = comps?.url else { throw TVBoxError.badURL }
            let vods = try await fetchResponse(u, timeoutSecs: 8).list ?? []
            return TestResult(key: s.key, ok: true,
                              latencyMs: Int(Date().timeIntervalSince(t0) * 1000),
                              count: vods.count, error: nil)
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
    /// 过滤采集站混入的演员卡（纯人名、无封面、无集数）。
    public func latest(siteKey: String, page: Int, typeId: Int? = nil) async throws -> [Drama] {
        let s = try await site(key: siteKey)
        return try await fetchList(site: s, page: page, typeId: typeId)
            .map { Self.toDrama($0, siteKey: s.key) }
            .filter { !HongguoClient.isActorCard($0) }
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

    /// 搜索：`?ac=videolist&wd=q&pg=n`。短超时 8s（坏源快速让位，不拖垮聚合）。
    public func search(siteKey: String, query: String, page: Int = 1) async throws -> [Drama] {
        let s = try await site(key: siteKey)
        var comps = URLComponents(string: s.api)
        comps?.queryItems = [
            URLQueryItem(name: "ac", value: "videolist"),
            URLQueryItem(name: "wd", value: query),
            URLQueryItem(name: "pg", value: String(page)),
        ]
        guard let u = comps?.url else { throw TVBoxError.badURL }
        let vods = try await fetchResponse(u, timeoutSecs: 8).list ?? []
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

    private func fetchList(site s: Site, page: Int, typeId: Int? = nil, timeoutSecs: Int = 15) async throws -> [Vod] {
        var comps = URLComponents(string: s.api)
        var items = [
            URLQueryItem(name: "ac", value: "list"),
            URLQueryItem(name: "pg", value: String(page)),
        ]
        if let t = typeId { items.append(URLQueryItem(name: "t", value: String(t))) }
        comps?.queryItems = items
        guard let u = comps?.url else { throw TVBoxError.badURL }
        if timeoutSecs == 15 { return try await fetchVods(u) }
        // 测速等短超时场景：直接走带超时参数的 fetchResponse
        let resp = try await fetchResponse(u, timeoutSecs: timeoutSecs)
        return resp.list ?? []
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
    /// 容错：部分采集站（如 xinlangapi）个别频道的 JSON 被截断（未闭合字符串/数组），
    /// 整体解码会抛 dataCorrupted「correct format」。此时按「最后一个完整 list 条目」
    /// 截断数据、丢弃坏尾巴，抢救已完整解析出的条目，而不是整页报错。
    private func fetchResponse(_ url: URL, timeoutSecs: Int = 15) async throws -> VodListResponse {
        // 硬上限：请求级 + 资源级 + 任务级三重封顶，坏源最多 timeoutSecs+1s 必返回，不再挂起 15s+。
        let cap = timeoutSecs + 1
        return try await withThrowingTaskGroup(of: VodListResponse.self) { group in
            group.addTask { try await self.fetchResponseInner(url, timeoutSecs: timeoutSecs) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(cap) * 1_000_000_000)
                throw TVBoxError.fetchFailed(-2)  // -2 = 硬超时
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    private func fetchResponseInner(_ url: URL, timeoutSecs: Int) async throws -> VodListResponse {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: TimeInterval(timeoutSecs))
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // 强制直连：采集站 CDN 锁中国大陆 IP，系统代理（VPN）走境外会被区域拦截 403。
        let (data, resp) = try await DirectURLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TVBoxError.fetchFailed((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let decoder = JSONDecoder()
        if let full = try? decoder.decode(VodListResponse.self, from: data) {
            return full
        }
        // 截断容错：找最后一个完整 vod 条目（"vod_id" 起、到下一个 "vod_id" 前的 '}），
        // 直接把 list 数组在最后一个完整对象处闭合，其余字段不要。
        if let salvaged = Self.salvageTruncatedList(data) {
            return salvaged
        }
        // 抢救不出条目才真正报错
        throw TVBoxError.parseFailed
    }

    /// 从被截断的 maccms JSON 中抢救已完整的 list 条目。
    /// 思路：list 是 [ {...}, {...}, ...被截断 ]; 找到 "{...完整...}" 的最后一个完整对象，
    /// 在 list 数组该处补 `]` 与 `}`，重新解码一个只含 list 的 VodListResponse。
    private static func salvageTruncatedList(_ data: Data) -> VodListResponse? {
        guard var text = String(data: data, encoding: .utf8),
              let listStart = text.range(of: "\"list\"\\s*:\\s*\\[", options: .regularExpression) else { return nil }
        // 只扫描 list 数组内容区
        let scanFrom = listStart.upperBound
        var lastGoodEnd: String.Index?  // 最后一个完整对象的 '}' 位置
        var depth = 0
        var inString = false
        var escaped = false
        var objStart: String.Index?
        var idx = scanFrom
        while idx < text.endIndex {
            let ch = text[idx]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
                idx = text.index(after: idx)
                continue
            }
            switch ch {
            case "\"":
                inString = true
            case "{":
                if depth == 0 { objStart = idx }
                depth += 1
            case "}":
                depth -= 1
                if depth == 0, objStart != nil {
                    lastGoodEnd = text.index(after: idx) // 完整对象结束
                    objStart = nil
                }
                if depth < 0 { // 提前闭合（理论上不该发生），停
                    idx = text.endIndex
                    continue
                }
            case "]":
                if depth == 0 { // 数组完整结束，说明其实没截断在 list 里
                    lastGoodEnd = lastGoodEnd ?? idx
                    idx = text.endIndex
                    continue
                }
            default:
                break
            }
            idx = text.index(after: idx)
        }
        guard let goodEnd = lastGoodEnd, goodEnd > scanFrom else { return nil }
        // 重新拼一个最小合法 JSON：{"list":[ ...完整条目... ]}
        let body = String(text[scanFrom..<goodEnd])
        let rebuilt = "{\"list\":[\(body)]}"
        guard let redata = rebuilt.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(VodListResponse.self, from: redata)
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
