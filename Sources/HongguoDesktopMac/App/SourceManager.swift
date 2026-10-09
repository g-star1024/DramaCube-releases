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
        if let data = d.data(forKey: "src.testResults"),
           let r = try? JSONDecoder().decode([String: SiteTestResult].self, from: data) {
            testResults = r
        } else {
            testResults = [:]
        }
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
    /// 单源开关（key → enabled），默认开。
    @Published public private(set) var disabled: Set<String> {
        didSet { defaults.set(Array(disabled), forKey: "src.disabled") }
    }
    /// 最近一次连通性测试结果（key → result）。
    @Published public private(set) var testResults: [String: SiteTestResult] {
        didSet {
            if let data = try? JSONEncoder().encode(testResults) {
                defaults.set(data, forKey: "src.testResults")
            }
        }
    }
    @Published public private(set) var isImporting = false
    @Published public private(set) var isTesting = false
    @Published public private(set) var lastImportCount: Int?

    private let defaults = UserDefaults.standard
    private let base = AppConfig.gatewayBaseURL

    /// 是否已导入订阅。
    public var hasSubscription: Bool { !sites.isEmpty }

    /// 启用的站点（参与聚合搜索）。
    public var enabledSites: [TVBoxSite] { sites.filter { !disabled.contains($0.key) } }

    // MARK: - 模型

    public struct TVBoxSite: Codable, Identifiable, Sendable, Hashable {
        public let key: String
        public let name: String
        public let api: String
        public var id: String { key }
    }

    public struct SiteTestResult: Codable, Sendable {
        public let key: String
        public let ok: Bool
        public let latencyMs: Int
        public let count: Int
        public let error: String?
    }

    // MARK: - 初始化

    /// 启动时装载站点列表（状态已在 init 从 UserDefaults 恢复）。
    public func load() {
        Task { await refreshSites() }
    }

    // MARK: - 订阅

    /// 一键导入（或更新）订阅。
    public func importSubscription(url: String) async throws -> Int {
        isImporting = true
        defer { isImporting = false }
        subscriptionURL = url
        let enc = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        let resp: [String: Int] = try await get("\(base)/api/tvbox/import?url=\(enc)")
        let count = resp["count"] ?? 0
        lastImportCount = count
        await refreshSites()
        AppLog.log(.app, "视频源订阅导入成功：\(count) 个站点")
        return count
    }

    /// 刷新站点列表（导入后 / 启动时）。
    public func refreshSites() async {
        do {
            let list: [TVBoxSite] = try await get("\(base)/api/tvbox/sites")
            sites = list
        } catch {
            // 未导入订阅时网关返回空数组，错误仅记录不打断
            AppLog.log(.net, "视频源列表获取失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 开关与测试

    public func setEnabled(_ key: String, _ on: Bool) {
        if on { disabled.remove(key) } else { disabled.insert(key) }
        // 关掉的源如果正在用，切回红果
        if !on && currentSource == key { currentSource = "hongguo" }
    }

    /// 测试全部站点（限流由网关侧控制）。
    public func testAll() async {
        isTesting = true
        defer { isTesting = false }
        do {
            let results: [SiteTestResult] = try await get("\(base)/api/tvbox/test")
            testResults = Dictionary(uniqueKeysWithValues: results.map { ($0.key, $0) })
            AppLog.log(.app, "视频源全量测试完成：\(results.filter(\.ok).count)/\(results.count) 可用")
        } catch {
            AppLog.log(.error, "视频源测试失败：\(error.localizedDescription)")
        }
    }

    public func testOne(_ key: String) async {
        do {
            let results: [SiteTestResult] = try await get("\(base)/api/tvbox/test?keys=\(key)")
            for r in results { testResults[key] = r }
        } catch {
            testResults[key] = SiteTestResult(key: key, ok: false, latencyMs: 0, count: 0,
                                             error: error.localizedDescription)
        }
    }

    // MARK: - 内容访问

    /// 当前源最新列表（TVBox 站点走站点接口；红果由现有 BrowseView 处理，不走这里）。
    public func tvboxLatest(siteKey: String, page: Int) async throws -> [Drama] {
        try await get("\(base)/api/tvbox/latest/\(siteKey)?page=\(page)")
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

    /// 播放地址：m3u8 优先 + 网关代理（剥离 Referer）。
    public func tvboxPlayURL(siteKey: String, vodId: String, episodeIndex: Int) -> URL {
        URL(string: "\(base)/api/tvbox/play/\(siteKey)/\(vodId)/\(episodeIndex)")!
    }

    // MARK: - 工具

    private func get<T: Codable & Sendable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
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
