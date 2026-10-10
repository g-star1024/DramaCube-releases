import Foundation
import HongguoCore

/// 电视直播引擎：m3u 订阅解析、多源排重合并、频道分组。
///
/// 直播源 = 一个 m3u/m3u8 订阅地址（含 #EXTINF 元数据 + 流地址）。
/// 多个源导入后按「频道名+分组」排重，合并为一个频道列表。
/// 频道结构：[{name, logo, group, url}...]，按 group 分组展示。
public actor LiveEngine {
    public static let shared = LiveEngine()

    // MARK: - 模型

    public struct Channel: Codable, Sendable, Identifiable, Hashable {
        public let id: String          // name|group 派生，排重键
        public let name: String
        public let logo: String?
        public let group: String
        public let url: String
    }

    private struct Source: Codable, Sendable, Identifiable, Hashable {
        let id: String                 // UUID
        var url: String
        var name: String
        var enabled: Bool
    }

    // MARK: - 持久化

    private var sources: [Source] = []
    private var loaded = false

    private static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DramaCube", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("live-sources.json")
    }

    private func loadIfNeeded() -> [Source] {
        if let data = try? Data(contentsOf: Self.storeURL),
           let list = try? JSONDecoder().decode([Source].self, from: data) {
            return list
        }
        return []
    }

    private func save() throws {
        try JSONEncoder().encode(sources).write(to: Self.storeURL, options: .atomic)
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        sources = loadIfNeeded()
        // 首次：内置用户给的默认源（未导入过时预置）
        if sources.isEmpty {
            sources = [Source(id: UUID().uuidString,
                              url: "https://live.ottiptv.cc/iptv.m3u?userid=6844226565&sign=c08de8ed458d23d075a3fdef4e74b8bf16787d9699d4569d3f02b8107c574f93d1276e657c542a596f151cb0edfbf15301c2ba1e44374feb7b320e993ad5e78cf2a992740d4ffb&auth_token=831f2b63aeabceb95bba8dda78752da7",
                              name: "OTT IPTV", enabled: true)]
            try? save()
        }
        loaded = true
    }

    private init() {}

    // MARK: - 源管理

    public struct SourceInfo: Codable, Sendable, Identifiable, Hashable {
        public let id: String
        public let url: String
        public let name: String
        public let enabled: Bool
    }

    public func allSources() -> [SourceInfo] {
        ensureLoaded()
        return sources.map { SourceInfo(id: $0.id, url: $0.url, name: $0.name, enabled: $0.enabled) }
    }

    /// 添加/更新直播源。url 相同视为同一源（幂等），返回是否为新增。
    @discardableResult
    public func addSource(url: String, name: String? = nil) throws -> SourceInfo {
        ensureLoaded()
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("http") else { throw LiveError.badURL }
        if let i = sources.firstIndex(where: { $0.url == trimmed }) {
            // 已存在：更新名字，视为更新不重复计数
            if let name, !name.isEmpty { sources[i].name = name; try save() }
            return SourceInfo(id: sources[i].id, url: trimmed, name: sources[i].name, enabled: sources[i].enabled)
        }
        let displayName = (name?.isEmpty == false) ? name! : Self.hostName(of: trimmed)
        let s = Source(id: UUID().uuidString, url: trimmed, name: displayName, enabled: true)
        sources.append(s)
        try save()
        return SourceInfo(id: s.id, url: s.url, name: s.name, enabled: s.enabled)
    }

    public func removeSource(id: String) throws {
        ensureLoaded()
        sources.removeAll { $0.id == id }
        try save()
    }

    public func setEnabled(id: String, _ on: Bool) throws {
        ensureLoaded()
        guard let i = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[i].enabled = on
        try save()
    }

    private static func hostName(of url: String) -> String {
        URL(string: url)?.host ?? "直播源"
    }

    // MARK: - 频道获取

    /// 拉取所有启用源的频道，排重合并，按 group 分组返回（组内按名排序）。
    /// 单源失败不拖垮整体（跳过该源）。结果缓存 30 分钟。
    public func channels() async -> [Channel] {
        ensureLoaded()
        if let cached = channelCache, Date().timeIntervalSince(cachedAt) < 1800 {
            return cached
        }
        let active = sources.filter(\.enabled)
        var merged: [String: Channel] = [:]  // key = name|group 排重
        await withTaskGroup(of: [Channel].self) { group in
            for s in active {
                group.addTask { (try? await Self.fetchChannels(url: s.url)) ?? [] }
            }
            for await list in group {
                for ch in list {
                    let key = "\(ch.name)|\(ch.group)"
                    if merged[key] == nil { merged[key] = ch }
                }
            }
        }
        let result = merged.values.sorted { a, b in
            if a.group != b.group { return a.group < b.group }
            return a.name < b.name
        }
        channelCache = result
        cachedAt = Date()
        return result
    }

    private var channelCache: [Channel]?
    private var cachedAt = Date.distantPast

    /// 强制刷新（清缓存）。
    public func invalidateCache() { channelCache = nil }

    // MARK: - m3u 解析

    private static func fetchChannels(url: String) async throws -> [Channel] {
        guard let u = URL(string: url) else { throw LiveError.badURL }
        var req = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        // 苹果端直播源要求自定义 UA（okHttp 通用约定）
        req.setValue("okHttp/Mod-1.5.0.0", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LiveError.fetchFailed((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw LiveError.parseFailed
        }
        return Self.parseM3U(text)
    }

    /// 解析 m3u：#EXTINF 元数据 + 下一行流地址。
    static func parseM3U(_ text: String) -> [Channel] {
        var out: [Channel] = []
        var pendingName = "", pendingLogo: String?, pendingGroup = "其他"
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXTINF") {
                // 频道名 = 最后一个逗号之后
                pendingName = line.components(separatedBy: ",").last?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                pendingLogo = Self.attr(line, key: "tvg-logo")
                pendingGroup = Self.attr(line, key: "group-title") ?? "其他"
                if pendingGroup.isEmpty { pendingGroup = "其他" }
            } else if line.hasPrefix("http"), !pendingName.isEmpty {
                let id = "\(pendingName)|\(pendingGroup)"
                out.append(Channel(id: id, name: pendingName, logo: pendingLogo, group: pendingGroup, url: line))
                pendingName = ""; pendingLogo = nil
            }
        }
        return out
    }

    private static func attr(_ line: String, key: String) -> String? {
        // 匹配 key="value"
        guard let range = line.range(of: "\(key)=\"([^\"]*)\"", options: .regularExpression) else { return nil }
        let s = line[range]
        guard let open = s.firstIndex(of: "\""), let close = s.lastIndex(of: "\""), close > open else { return nil }
        return String(s[s.index(after: open)..<close])
    }

    // MARK: - 播放地址
    // 直播走网关代理（统一 UA / 防盗链），由 GatewayServer 的路由处理，引擎只提供 UA 约定。
    public static let playbackUserAgent = "okHttp/Mod-1.5.0.0"

    public enum LiveError: Error, LocalizedError {
        case badURL, fetchFailed(Int), parseFailed
        public var errorDescription: String? {
            switch self {
            case .badURL: return "直播源地址无效"
            case .fetchFailed(let c): return "请求失败（HTTP \(c)）"
            case .parseFailed: return "直播源格式无法解析"
            }
        }
    }
}
