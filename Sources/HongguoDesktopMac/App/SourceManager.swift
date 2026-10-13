import Foundation
import Combine
import HongguoCore

/// 视频源管理器（前端状态 + 网关通信）。
///
/// 数据源两种：
///  - `hongguo`：内置红果短剧站（原有链路，不可关闭）；
///  - `tvbox|<key>`：TVBox 订阅中的 maccms 站点（可开关、可测试）。
///
/// 订阅 URL 存 UserDefaults，站点开关/连通性结果持久化；
/// 订阅 JSON 本体由网关侧缓存（Application Support），重启后无需重新导入。
@MainActor
public final class SourceManager: ObservableObject {
    public static let shared = SourceManager()
    private init() {
        let d = UserDefaults.standard
        currentSource = d.string(forKey: "src.current") ?? "hongguo"
        subscriptionURL = d.string(forKey: "src.subURL") ?? ""
        disabled = Set(d.stringArray(forKey: "src.disabled") ?? [])
        manualDisabled = Set(d.stringArray(forKey: "src.manualDisabled") ?? [])
        autoTestIntervalHours = d.double(forKey: "src.autoTestHours") // 0 = 关闭
        lastAutoTest = d.object(forKey: "src.lastAutoTest") as? Date
        // 测速结果从 Application Support 文件恢复（兼容旧的 UserDefaults 迁移一次）。
        if let data = try? Data(contentsOf: Self.testResultsURL),
           let r = try? JSONDecoder().decode([String: SiteTestResult].self, from: data) {
            testResults = r
        } else if let data = d.data(forKey: "src.testResults"),
                  let r = try? JSONDecoder().decode([String: SiteTestResult].self, from: data) {
            testResults = r  // 旧数据迁移（didSet 会触发写入新文件）
            d.removeObject(forKey: "src.testResults")
        } else {
            testResults = [:]
        }
        // 启动即把已有失败测试记录的源并入禁用（不依赖手动测速按钮）
        reconcileDisabledWithTestResults()
    }

    // MARK: - 状态

    /// 订阅中的全部站点（来自网关 /api/tvbox/sites）。
    @Published public private(set) var sites: [TVBoxSite] = []
    /// 当前浏览/搜索使用的源（"hongguo" 或站点 key）。
    @Published public var currentSource: String {
        didSet { defaults.set(currentSource, forKey: "src.current") }
    }
    /// 订阅 URL（用于「更新订阅」）。
    @Published public var subscriptionURL: String {
        didSet { defaults.set(subscriptionURL, forKey: "src.subURL") }
    }
    /// 单源开关（key → disabled）。由测试结果与用户手动操作共同驱动：
    /// 测失败 → 自动禁用；测成功 → 自动恢复（除非在 manualDisabled 里）。
    @Published public private(set) var disabled: Set<String> {
        didSet { defaults.set(Array(disabled), forKey: "src.disabled") }
    }
    /// 用户手动关闭的源（尊重用户意图：测成功也不会自动重新启用，需用户手动打开）。
    @Published public private(set) var manualDisabled: Set<String> {
        didSet { defaults.set(Array(manualDisabled), forKey: "src.manualDisabled") }
    }
    /// 最近一次连通性测试结果（key → result）。
    /// 持久化到 Application Support 文件（v1.2.3 修：原 UserDefaults 在字典下标赋值时不触发 didSet，
    /// 且大字典写 UserDefaults 不可靠，重启即丢）。所有写入统一走 persistTestResults()。
    @Published public private(set) var testResults: [String: SiteTestResult] = [:] {
        didSet { persistTestResults() }
    }

    /// 测速结果持久化文件（Application Support，升级重装不丢）。
    private static var testResultsURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DramaCube", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tvbox-test-results.json")
    }

    /// 落盘测速结果（节流：连续写入合并，避免全量测试 154 次逐条写盘）。
    private var persistTestResultsWork: DispatchWorkItem?
    private func persistTestResults() {
        persistTestResultsWork?.cancel()
        let snapshot = testResults
        let work = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: Self.testResultsURL, options: .atomic)
            }
        }
        persistTestResultsWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    @Published public private(set) var isImporting = false
    @Published public private(set) var isTesting = false
    @Published public private(set) var lastImportCount: Int?
    /// 自动测速周期（小时，0=关闭）。测完自动禁用失败源、按延迟排序站点。
    @Published public var autoTestIntervalHours: Double {
        didSet {
            defaults.set(autoTestIntervalHours, forKey: "src.autoTestHours")
            scheduleAutoTest()
        }
    }
    /// 最近一次自动测速时间（展示用）。
    @Published public private(set) var lastAutoTest: Date? {
        didSet { defaults.set(lastAutoTest, forKey: "src.lastAutoTest") }
    }
    /// 站点频道缓存（siteKey → 频道），进程内缓存，切换站点时懒加载。
    @Published public private(set) var categories: [String: [TVBoxCategory]] = [:]
    /// 已导入成功的订阅地址（来自网关持久化，重启后展示在订阅管理列表）。
    @Published public private(set) var subscriptionURLs: [String] = []

    private let defaults = UserDefaults.standard
    /// 网关基址实时读取（不能缓存）：端口冲突递增后仍要打到实际端口。
    private var base: String { AppConfig.gatewayBaseURL }
    /// 直连网关（绕过系统代理；127.0.0.1 本不应走代理，但全局代理可能拦）。
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.connectionProxyDictionary = [:]
        return URLSession(configuration: c)
    }()
    private var autoTestTimer: Timer?

    /// 站点列表本地镜像（Application Support，升级重装不丢，网关不可达时兜底）。
    private static var mirrorURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DramaCube", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tvbox-sites-mirror.json")
    }

    /// 是否已导入订阅。
    public var hasSubscription: Bool { !sites.isEmpty }

    /// 启用的站点（参与聚合搜索），已测过的按延迟升序排前。
    public var enabledSites: [TVBoxSite] {
        sortedByLatency(sites.filter { !disabled.contains($0.key) })
    }

    /// 某源是否「确定失效」：有测试记录且失败。（未测过的不算）
    public func isFailed(_ key: String) -> Bool {
        testResults[key].map { !$0.ok } ?? false
    }

    /// 启动时把「有失败测试记录」的源一次性并入禁用——不依赖用户手动点「全部连通性测试」。
    /// 用户手动开着但已测失败的源同样禁用（渲染时即生效，不让失效源再进检索/勾选）。
    private func reconcileDisabledWithTestResults() {
        var d = disabled
        var changed = false
        for (key, r) in testResults where !r.ok {
            if !d.contains(key) { d.insert(key); changed = true }
        }
        if changed {
            disabled = d
            AppLog.log(.app, "已将 \(d.count) 个失效源并入禁用（基于已有测试记录）")
        }
    }

    /// 全部站点按延迟排序（有结果的升序在前，未测的按原名在后）。
    public var sortedSites: [TVBoxSite] { sortedByLatency(sites) }

    private func sortedByLatency(_ list: [TVBoxSite]) -> [TVBoxSite] {
        list.sorted { a, b in
            let la = testResults[a.key].flatMap { $0.ok ? $0.latencyMs : nil }
            let lb = testResults[b.key].flatMap { $0.ok ? $0.latencyMs : nil }
            switch (la, lb) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return false // 都未测：保持订阅原序
            }
        }
    }

    /// 延迟最低的可用源（视频源页默认展示）。
    public var fastestEnabledSite: TVBoxSite? { enabledSites.first }

    // MARK: - 模型

    public struct TVBoxSite: Codable, Identifiable, Sendable, Hashable {
        public let key: String
        public let name: String
        public let api: String
        public var id: String { key }
    }

    /// 站点频道（网关返回的 maccms class）。
    public struct TVBoxCategory: Codable, Identifiable, Sendable, Hashable {
        public let typeId: Int
        public let name: String
        public var id: Int { typeId }
    }

    public struct SiteTestResult: Codable, Sendable {
        public let key: String
        public let ok: Bool
        public let latencyMs: Int
        public let count: Int
        public let error: String?
    }

    /// 单个订阅地址的导入结果。
    public struct SubImportResult: Codable, Sendable {
        public let url: String
        public let added: Int
        public let error: String?
        public var ok: Bool { error == nil }
    }
    private struct ImportPayload: Codable, Sendable {
        let count: Int
        let results: [SubImportResult]
    }

    // MARK: - 初始化

    /// 启动时装载站点列表（状态已在 init 从 UserDefaults 恢复）。
    /// 先读本地镜像秒显，再等网关就绪拉真值；网关不可达时保留镜像数据（源不再"丢失"）。
    public func load() {
        // 1. 本地镜像秒显（镜像由最近一次成功导入/刷新写入）
        if sites.isEmpty,
           let data = try? Data(contentsOf: Self.mirrorURL),
           let mirrored = try? JSONDecoder().decode([TVBoxSite].self, from: data),
           !mirrored.isEmpty {
            sites = mirrored
            AppLog.log(.app, "视频源列表已从本地镜像恢复（\(mirrored.count) 站）")
        }
        // 2. 网关就绪后拉真值（重试兜住网关启动竞态：start() 异步，首个请求可能 502/拒绝）
        Task {
            await refreshSitesWithRetry()
            await refreshSubscriptionURLs()
            maybeAutoTest()
        }
        scheduleAutoTest()
    }

    /// 带重试的站点列表刷新：网关刚启动未监听时连接被拒，最多重试 6 次（1s/2s/3s/4s/5s/6s）。
    private func refreshSitesWithRetry() async {
        for attempt in 1...6 {
            await refreshSites()
            if !sites.isEmpty { return }
            // 若本来就没订阅（镜像也为空 + 网关空），不必死等，两次空响应就退
            if attempt >= 2, !FileManager.default.fileExists(atPath: Self.mirrorURL.path) { return }
            AppLog.log(.net, "视频源列表第 \(attempt) 次获取为空，\(attempt)s 后重试（等待网关就绪）")
            try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
        }
    }

    /// 站点列表写入本地镜像（导入成功 / 每次刷新成功后调用）。
    private func writeMirror() {
        guard !sites.isEmpty else { return }
        if let data = try? JSONEncoder().encode(sites) {
            try? data.write(to: Self.mirrorURL, options: .atomic)
        }
    }

    // MARK: - 订阅

    /// 一键导入（或更新）订阅。支持一次粘贴多个地址（换行/逗号/分号分隔），
    /// 单地址失败跳过继续其余。返回每个地址的导入明细（成功新增数/失败原因）。
    /// 成功的地址由网关持久化，重启后展示在订阅管理列表。
    @discardableResult
    public func importSubscription(url: String) async -> [SubImportResult] {
        isImporting = true
        defer { isImporting = false }
        subscriptionURL = url
        let enc = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        do {
            let payload: ImportPayload = try await get("\(base)/api/tvbox/import?url=\(enc)")
            lastImportCount = payload.count
            await refreshSites()
            await refreshSubscriptionURLs()
            writeMirror()
            AppLog.log(.app, "视频源订阅导入完成：新增 \(payload.count) 个站点（\(payload.results.filter(\.ok).count)/\(payload.results.count) 地址成功）")
            return payload.results
        } catch {
            return [SubImportResult(url: url, added: 0, error: error.localizedDescription)]
        }
    }

    /// 拉取已存订阅地址列表（订阅管理展示）。
    public func refreshSubscriptionURLs() async {
        let urls: [String] = (try? await get("\(base)/api/tvbox/subscriptions")) ?? []
        subscriptionURLs = urls
    }

    /// 删除一个订阅地址。
    public func removeSubscriptionURL(_ url: String) async {
        let enc = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        let _: [String: String] = (try? await get("\(base)/api/tvbox/removesub?url=\(enc)")) ?? [:]
        await refreshSubscriptionURLs()
    }

    /// 重新拉取全部已存订阅（更新订阅）。
    @discardableResult
    public func refreshAllSubscriptions() async -> [SubImportResult] {
        isImporting = true
        defer { isImporting = false }
        let results: [SubImportResult] = (try? await get("\(base)/api/tvbox/refreshsubs")) ?? []
        await refreshSites()
        await refreshSubscriptionURLs()
        writeMirror()
        return results
    }

    /// 刷新站点列表（导入后 / 启动时）。成功且有数据时写镜像。
    public func refreshSites() async {
        do {
            let list: [TVBoxSite] = try await get("\(base)/api/tvbox/sites")
            if !list.isEmpty {
                sites = list
                writeMirror()
            } else if !subscriptionURL.isEmpty {
                // 网关返回空 = 网关侧订阅缓存丢/被清，用已存订阅 URL 自动重导一次
                AppLog.log(.net, "网关站点列表为空，用已存订阅 URL 自动重新导入")
                _ = await importSubscription(url: subscriptionURL)
            }
        } catch {
            // 未导入订阅或网关未就绪时错误仅记录不打断（镜像数据已先展示）
            AppLog.log(.net, "视频源列表获取失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 开关与测试

    public func setEnabled(_ key: String, _ on: Bool) {
        if on {
            disabled.remove(key)
            manualDisabled.remove(key)
        } else {
            disabled.insert(key)
            manualDisabled.insert(key)
        }
        // 关掉的源如果正在用，切到最快可用源（红果内容源已清除，不再回退红果）
        if !on && currentSource == key, let fast = fastestEnabledSite {
            currentSource = fast.key
        }
    }

    /// 按测试结果应用自动开关：失败一律禁用（压过手动开启），成功自动恢复（除非用户手动关过）。
    private func applyTestResults(_ results: [SiteTestResult]) {
        var newDisabled = disabled
        var newManual = manualDisabled
        for r in results {
            if r.ok {
                if !newManual.contains(r.key) { newDisabled.remove(r.key) }
            } else {
                // 测失败的源如果用户手动开过，这次失败说明它已失效——清除手动标记并禁用
                newDisabled.insert(r.key)
                newManual.remove(r.key)
            }
        }
        disabled = newDisabled
        manualDisabled = newManual
        if disabled.contains(currentSource), let fast = fastestEnabledSite {
            currentSource = fast.key
        }
    }

    /// 测试全部站点（限流由网关侧控制）。
    /// 测完自动：失败源一律禁用（含手动开着的失效源）、成功源自动恢复（除非用户手动关过）、按延迟排序。
    public func testAll() async {
        isTesting = true
        defer { isTesting = false }
        do {
            let results: [SiteTestResult] = try await get("\(base)/api/tvbox/test")
            testResults = Dictionary(uniqueKeysWithValues: results.map { ($0.key, $0) })
            applyTestResults(results)
            AppLog.log(.app, "视频源全量测试完成：\(results.filter(\.ok).count)/\(results.count) 可用，失败源已自动禁用")
        } catch {
            AppLog.log(.error, "视频源测试失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 自动测速

    /// 启动/修改周期时调度；每小时检查一次是否到期（Timer 对长周期不精确也无所谓）。
    private func scheduleAutoTest() {
        autoTestTimer?.invalidate()
        autoTestTimer = nil
        guard autoTestIntervalHours > 0 else { return }
        autoTestTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.maybeAutoTest() }
        }
    }

    /// 到期则跑全量测试（导入后首测也走这里：lastAutoTest 为空且已有订阅）。
    private func maybeAutoTest() {
        guard autoTestIntervalHours > 0, hasSubscription, !isTesting else { return }
        if let last = lastAutoTest, Date().timeIntervalSince(last) < autoTestIntervalHours * 3600 { return }
        lastAutoTest = Date()
        AppLog.log(.app, "自动测速周期触发（每 \(Int(autoTestIntervalHours))h）")
        Task { await testAll() }
    }

    public func testOne(_ key: String) async {
        do {
            let results: [SiteTestResult] = try await get("\(base)/api/tvbox/test?keys=\(key)")
            for r in results { testResults[key] = r }
            applyTestResults(results)
        } catch {
            testResults[key] = SiteTestResult(key: key, ok: false, latencyMs: 0, count: 0,
                                             error: error.localizedDescription)
        }
    }

    // MARK: - 内容访问

    /// 当前源最新列表（cache-then-network 由调用方处理；typeId 传 nil 取最新）。
    public func tvboxLatest(siteKey: String, page: Int, typeId: Int? = nil) async throws -> [Drama] {
        let t = typeId.map { "&t=\($0)" } ?? ""
        return try await get("\(base)/api/tvbox/latest/\(siteKey)?page=\(page)\(t)")
    }

    /// 站点频道（懒加载 + 进程内缓存）。
    public func tvboxCategories(siteKey: String) async -> [TVBoxCategory] {
        if let cached = categories[siteKey], !cached.isEmpty { return cached }
        do {
            let cats: [TVBoxCategory] = try await get("\(base)/api/tvbox/categories/\(siteKey)")
            if !cats.isEmpty { categories[siteKey] = cats }
            return cats
        } catch {
            AppLog.log(.net, "视频源频道获取失败[\(siteKey)]：\(error.localizedDescription)")
            return []
        }
    }

    /// 单源搜索。
    public func tvboxSearch(siteKey: String, query: String) async throws -> [Drama] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await get("\(base)/api/tvbox/search/\(siteKey)?q=\(q)")
    }

    /// 聚合搜索：并发搜所有启用源（限并发 5，单源失败不拖垮整体）。
    /// 结果按「源响应快先归并」顺序拼，标题去重。
    public func aggregateSearch(query: String) async -> [Drama] {
        let targets = enabledSites
        guard !targets.isEmpty else { return [] }
        return await withTaskGroup(of: [Drama].self) { group in
            var results: [Drama] = []
            var pending = targets.makeIterator()
            for _ in 0..<5 {
                if let s = pending.next() {
                    group.addTask { (try? await self.tvboxSearch(siteKey: s.key, query: query)) ?? [] }
                }
            }
            while let chunk = await group.next() {
                results.append(contentsOf: chunk)
                if let s = pending.next() {
                    group.addTask { (try? await self.tvboxSearch(siteKey: s.key, query: query)) ?? [] }
                }
            }
            // 同标题去重（保留先到的）
            var seen = Set<String>()
            return results.filter { seen.insert($0.title).inserted }
        }
    }

    /// 详情（TVBox）。
    public func tvboxDetail(siteKey: String, vodId: String) async throws -> DramaDetail {
        let id = vodId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vodId
        return try await get("\(base)/api/tvbox/detail/\(siteKey)/\(id)")
    }

    /// 发现页短剧横排：从首个可用源拉最新列表（MoonTVPlus 热播短剧形式，返回真实可播 Drama）。
    /// 优先取该源的「短剧」频道，取不到则退回最新列表，按集数多者优先（短剧特征：集数多）。
    public func duanjuRecommends(limit: Int = 18) async -> [Drama] {
        guard let site = enabledSites.first else { return [] }
        // 找短剧频道
        let cats = await tvboxCategories(siteKey: site.key)
        let duanjuCat = cats.first { $0.name.contains("短剧") || $0.name.contains("微短") }
        if let list = try? await tvboxLatest(siteKey: site.key, page: 1, typeId: duanjuCat?.id), !list.isEmpty {
            return Array(list.prefix(limit))
        }
        if let list = try? await tvboxLatest(siteKey: site.key, page: 1, typeId: nil) {
            // 短剧特征：集数多；优先按集数降序
            let sorted = list.sorted { ($0.episodeCount ?? 0) > ($1.episodeCount ?? 0) }
            return Array(sorted.prefix(limit))
        }
        return []
    }

    /// 播放地址：m3u8 优先 + 网关代理（剥离 Referer）。
    public func tvboxPlayURL(siteKey: String, vodId: String, episodeIndex: Int) -> URL {
        URL(string: "\(base)/api/tvbox/play/\(siteKey)/\(vodId)/\(episodeIndex)")!
    }

    // MARK: - 工具

    private func get<T: Codable & Sendable>(_ urlString: String) async throws -> T {
        // 启动竞态修复：等网关 ready 再发（与 CatalogService.decode 对齐），避免首刷 -1004。
        await GatewayRuntime.waitUntilReady(maxSeconds: 15)
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        let env = try JSONDecoder().decode(GatewayEnvelope<T>.self, from: data)
        if let e = env.error { throw HongguoParseError.fieldMissing(e) }
        guard let d = env.data else { throw HongguoParseError.fieldMissing("data") }
        return d
    }

    // MARK: - 便捷

    /// 当前源显示名。
    public var currentSourceName: String {
        if currentSource == "hongguo" { return "红果短剧" }
        return sites.first(where: { $0.key == currentSource })?.name ?? currentSource
    }
}
