import Foundation
import Combine
import HongguoCore

/// NAS 资源库管理器（前端状态 + 网关通信）。
///
/// 库配置由网关侧持久化（nas-libraries.json），升级重装不丢；
/// 前端本地镜像一份（Application Support），网关未就绪时也能展示库名与入口。
@MainActor
public final class NASManager: ObservableObject {
    public static let shared = NASManager()
    private init() {
        if let data = try? Data(contentsOf: Self.mirrorURL),
           let list = try? JSONDecoder().decode([NASLibrary].self, from: data) {
            libraries = list
        }
    }

    @Published public private(set) var libraries: [NASLibrary] = []
    @Published public private(set) var isTesting = false

    private let base = AppConfig.gatewayBaseURL

    private static var mirrorURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DramaCube", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("nas-libraries-mirror.json")
    }

    // MARK: - 模型

    public struct NASLibrary: Codable, Identifiable, Sendable, Hashable {
        public let id: String
        public var name: String
        public var type: LibType
        public var baseURL: String
        public var username: String?
        public var password: String?
        public var enabled: Bool

        public enum LibType: String, Codable, Sendable { case webdav, mount }
        public var typeName: String { type == .webdav ? "WebDAV" : "本机挂载" }
    }

    public struct NASTestResult: Codable, Sendable {
        public let id: String
        public let ok: Bool
        public let latencyMs: Int
        public let videoCount: Int
        public let error: String?
    }

    // MARK: - 加载

    public func load() {
        Task { await refresh() }
    }

    public func refresh() async {
        do {
            let list: [NASLibrary] = try await get("\(base)/api/nas/libraries")
            libraries = list
            writeMirror()
        } catch {
            AppLog.log(.net, "NAS 库列表获取失败：\(error.localizedDescription)")
        }
    }

    private func writeMirror() {
        if let data = try? JSONEncoder().encode(libraries) {
            try? data.write(to: Self.mirrorURL, options: .atomic)
        }
    }

    // MARK: - 操作

    @discardableResult
    public func add(name: String, type: NASLibrary.LibType, base: String,
                    user: String?, pass: String?) async throws -> NASLibrary {
        var comps = URLComponents(string: "\(self.base)/api/nas/add")!
        comps.queryItems = [
            .init(name: "name", value: name),
            .init(name: "type", value: type == .webdav ? "webdav" : "mount"),
            .init(name: "base", value: base),
            .init(name: "user", value: user ?? ""),
            .init(name: "pass", value: pass ?? ""),
        ]
        guard let url = comps.url else { throw URLError(.badURL) }
        let lib: NASLibrary = try await get(url.absoluteString)
        await refresh()
        AppLog.log(.app, "NAS 库已添加：\(name)（\(type == .webdav ? "WebDAV" : "挂载")）")
        return lib
    }

    public func remove(id: String) async {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        let _: [String: String] = (try? await get("\(base)/api/nas/remove?id=\(enc)")) ?? [:]
        await refresh()
    }

    public func setEnabled(id: String, _ on: Bool) async {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        let _: [String: Int] = (try? await get("\(base)/api/nas/toggle?id=\(enc)&on=\(on ? 1 : 0)")) ?? [:]
        await refresh()
    }

    public func test(id: String) async -> NASTestResult? {
        isTesting = true
        defer { isTesting = false }
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        return try? await get("\(base)/api/nas/test?id=\(enc)")
    }

    // MARK: - 内容

    public func browse(id: String, path: String = "") async throws -> [Drama] {
        let p = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await get("\(base)/api/nas/browse/\(id)?path=\(p)")
    }

    public func detail(id: String, dirPath: String) async throws -> DramaDetail {
        let p = dirPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await get("\(base)/api/nas/detail/\(id)?path=\(p)")
    }

    /// 单文件播放地址还原。
    public func playURLString(id: String, path: String) async throws -> String {
        let p = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let r: [String: String] = try await get("\(base)/api/nas/playurl/\(id)?path=\(p)")
        guard let u = r["url"] else { throw HongguoParseError.fieldMissing("url") }
        // 网关代理路径（/api/nas/stream/...）补全为本机地址；file:// / http(s) 原样返回
        if u.hasPrefix("/") { return "\(base)\(u)" }
        return u
    }

    // MARK: - 工具

    private func get<T: Codable & Sendable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        // 大库递归扫描可能耗时，给 60s 超时（默认 60s 但显式声明更清晰，且避免偶发挂起）
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await URLSession.shared.data(for: req)
        let env = try JSONDecoder().decode(GatewayEnvelope<T>.self, from: data)
        if let e = env.error { throw HongguoParseError.fieldMissing(e) }
        guard let d = env.data else { throw HongguoParseError.fieldMissing("data") }
        return d
    }
}
