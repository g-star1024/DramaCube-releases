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
    public func add(url: String, name: String?) async throws -> Bool {
        isImporting = true
        defer { isImporting = false }
        let before = sources.count
        var comps = URLComponents(string: "\(base)/api/live/add")!
        comps.queryItems = [.init(name: "url", value: url)]
        if let name, !name.isEmpty { comps.queryItems?.append(.init(name: "name", value: name)) }
        guard let u = comps.url else { throw URLError(.badURL) }
        let _: LiveSource = try await get(u.absoluteString)
        await refresh()
        let isNew = sources.count > before
        AppLog.log(.app, "直播源已\(isNew ? "添加" : "更新")：\(name ?? url)")
        return isNew
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

    // MARK: - 频道

    public func channels() async throws -> [LiveChannel] {
        try await get("\(base)/api/live/channels")
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
        let (data, _) = try await URLSession.shared.data(for: req)
        let env = try JSONDecoder().decode(GatewayEnvelope<T>.self, from: data)
        if let e = env.error { throw HongguoParseError.fieldMissing(e) }
        guard let d = env.data else { throw HongguoParseError.fieldMissing("data") }
        return d
    }
}
