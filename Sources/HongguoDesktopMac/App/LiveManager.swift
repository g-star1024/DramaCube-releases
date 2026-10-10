import Foundation
import Combine
import HongguoCore

/// 电视直播管理器（前端状态 + 网关通信）。
///
/// 直播源配置由网关侧持久化（live-sources.json），前端镜像一份（网关未就绪时也能展示入口）。
@MainActor
public final class LiveManager: ObservableObject {
    public static let shared = LiveManager()
    private init() {
        if let data = try? Data(contentsOf: Self.mirrorURL),
           let list = try? JSONDecoder().decode([LiveSource].self, from: data) {
            sources = list
        }
    }

    @Published public private(set) var sources: [LiveSource] = []
    @Published public private(set) var isImporting = false

    private let base = AppConfig.gatewayBaseURL

    /// 直连网关（绕过系统代理；127.0.0.1 本不应走代理，但全局代理可能拦）。
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.connectionProxyDictionary = [:]
        return URLSession(configuration: c)
    }()

    private static var mirrorURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DramaCube", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("live-sources-mirror.json")
    }

    // MARK: - 模型

    public struct LiveSource: Codable, Identifiable, Sendable, Hashable {
        public let id: String
        public let url: String
        public let name: String
        public let enabled: Bool
        public let userAgent: String?
    }

    public struct LiveChannel: Codable, Identifiable, Sendable, Hashable {
        public let id: String
        public let name: String
        public let logo: String?
        public let group: String
        public let url: String
    }

    // MARK: - 加载

    public func load() { Task { await refresh() } }

    public func refresh() async {
        do {
            let list: [LiveSource] = try await get("\(base)/api/live/sources")
            sources = list
            writeMirror()
        } catch {
            AppLog.log(.net, "直播源列表获取失败：\(error.localizedDescription)")
        }
    }

    private func writeMirror() {
        if let data = try? JSONEncoder().encode(sources) {
            try? data.write(to: Self.mirrorURL, options: .atomic)
        }
    }

    // MARK: - 操作

    /// 添加直播源（url 相同幂等更新）。返回是否新增（false=更新已有）。
    @discardableResult
    public func add(url: String, name: String?, userAgent: String? = nil) async throws -> Bool {
        isImporting = true
        defer { isImporting = false }
        let before = sources.count
        var comps = URLComponents(string: "\(base)/api/live/add")!
        comps.queryItems = [.init(name: "url", value: url)]
        if let name, !name.isEmpty { comps.queryItems?.append(.init(name: "name", value: name)) }
        if let ua = userAgent, !ua.isEmpty { comps.queryItems?.append(.init(name: "ua", value: ua)) }
        guard let u = comps.url else { throw URLError(.badURL) }
        let _: LiveSource = try await get(u.absoluteString)
        await refresh()
        let isNew = sources.count > before
        AppLog.log(.app, "直播源已\(isNew ? "添加" : "更新")：\(name ?? url)")
        return isNew
    }

    /// 设置源的自定义 UA（空串/nil = 恢复默认 okHttp UA）。
    public func setUserAgent(id: String, _ ua: String?) async {
        var comps = URLComponents(string: "\(base)/api/live/setua")!
        comps.queryItems = [.init(name: "id", value: id), .init(name: "ua", value: ua ?? "")]
        guard let u = comps.url else { return }
        let _: [String: String] = (try? await get(u.absoluteString)) ?? [:]
        await refresh()
    }

    public func remove(id: String) async {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        let _: [String: String] = (try? await get("\(base)/api/live/remove?id=\(enc)")) ?? [:]
        await refresh()
    }

    public func setEnabled(id: String, _ on: Bool) async {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        let _: [String: String] = (try? await get("\(base)/api/live/toggle?id=\(enc)&on=\(on ? 1 : 0)")) ?? [:]
        await refresh()
    }

    /// 单选当前启用的直播源（其余自动禁用，避免多源混杂）。
    public func setActive(id: String) async {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        let _: [String: String] = (try? await get("\(base)/api/live/setactive?id=\(enc)")) ?? [:]
        await refresh()
    }

    /// 单源探活：返回该源解析出的频道数（0 = 失效）。
    public func testSource(id: String) async -> Int {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        struct R: Codable { let id: String; let count: String }
        let r: R? = try? await get("\(base)/api/live/testsource?id=\(enc)")
        return Int(r?.count ?? "0") ?? 0
    }

    // MARK: - 频道

    public func channels() async throws -> [LiveChannel] {
        try await get("\(base)/api/live/channels")
    }

    /// 批量连通性测试：返回 [channelId: 是否可达]。分批避免单个 query 过长。
    public func testChannels(_ channels: [LiveChannel]) async -> [String: Bool] {
        var out: [String: Bool] = [:]
        let batchSize = 40
        for chunk in stride(from: 0, to: channels.count, by: batchSize) {
            let slice = Array(channels[chunk..<min(chunk + batchSize, channels.count)])
            // 换行分隔：id 内含 "|"（name|group），不能用 | 当分隔符。id/url 都保持原始，
            // 交给 URLComponents.queryItems 统一 percent 编码（再手动编码会双重编码导致 unsupported URL）。
            let ids = slice.map(\.id).joined(separator: "\n")
            let urls = slice.map(\.url).joined(separator: "\n")
            var comps = URLComponents(string: "\(base)/api/live/test")!
            comps.queryItems = [.init(name: "ids", value: ids), .init(name: "urls", value: urls)]
            guard let u = comps.url else { continue }
            if let part: [String: Bool] = try? await get(u.absoluteString) {
                out.merge(part) { a, _ in a }
            }
        }
        return out
    }

    /// 读取已持久化的连通性结果（重启后恢复角标状态，测试前也能看到上次结果）。
    public func savedReachability() async -> [String: Bool] {
        (try? await get("\(base)/api/live/reachability")) ?? [:]
    }

    /// 频道播放地址（经网关直播代理，统一 UA）。
    public func streamURLString(channelURL: String) -> String {
        let enc = channelURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? channelURL
        return "\(base)/api/live/stream?url=\(enc)"
    }

    // MARK: - 工具

    private func get<T: Codable & Sendable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 40)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await session.data(for: req)
        let env = try JSONDecoder().decode(GatewayEnvelope<T>.self, from: data)
        if let e = env.error { throw HongguoParseError.fieldMissing(e) }
        guard let d = env.data else { throw HongguoParseError.fieldMissing("data") }
        return d
    }
}
