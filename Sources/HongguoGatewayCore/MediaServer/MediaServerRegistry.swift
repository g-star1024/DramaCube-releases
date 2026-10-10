import Foundation

// MARK: - 媒体服务器注册中心
// 职责：多服务器管理 / 一键切换 / 连接状态缓存 / 聚合搜索 / 聚合首页 / 进度归并。
// 对标 Cinetry「服务器一键切换 + 多服务器数据聚合搜索」。
// 全平台约束：actor 保证并发安全，只依赖 Foundation。

public actor MediaServerRegistry {
    public static let shared = MediaServerRegistry()

    /// 已注册的服务器（key → 适配器实例）。
    private var servers: [String: any MediaServerProtocol] = [:]
    /// 连接状态缓存（key → capability，probe 后填充）。
    private var capabilities: [String: ServerCapability] = [:]
    /// 当前聚焦/浏览的服务器 key（nil = 聚合模式，跨全部服务器）。
    private var focusedKey: String?

    private init() {}

    // MARK: - 注册管理

    public func register(_ server: any MediaServerProtocol) {
        servers[server.config.id] = server
    }

    public func unregister(key: String) {
        servers.removeValue(forKey: key)
        capabilities.removeValue(forKey: key)
        if focusedKey == key { focusedKey = nil }
    }

    public func server(key: String) -> (any MediaServerProtocol)? { servers[key] }

    public func allServers() -> [any MediaServerProtocol] {
        servers.values.sorted { $0.config.name < $1.config.name }
    }

    public func enabledServers() -> [any MediaServerProtocol] {
        servers.values.filter { $0.config.enabled }.sorted { $0.config.name < $1.config.name }
    }

    // MARK: - 一键切换

    /// 聚焦某服务器（nil=聚合模式）。
    public func focus(_ key: String?) {
        focusedKey = key.flatMap { servers[$0] != nil ? $0 : nil }
    }

    public func focused() -> (any MediaServerProtocol)? {
        focusedKey.flatMap { servers[$0] }
    }

    /// 当前作用域：聚焦则只该源，否则全部启用源。
    private func scope() -> [any MediaServerProtocol] {
        if let f = focused() { return [f] }
        return enabledServers()
    }

    /// 聚合作用域（过滤失败源）：probe 已判定 offline 的源不纳入聚合，
    /// 避免首页/搜索被 150 个低质死源拖垮或展示失败源内容。
    private func liveScope() -> [any MediaServerProtocol] {
        scope().filter { s in
            guard let cap = capabilities[s.config.id] else { return true }  // 未探测=纳入
            return cap.online
        }
    }

    /// 首页聚合作用域（先返回+异步补全）：只用「已判定在线」的源。
    /// 未探测的源不纳入（避免对 150 个未知源逐一 HTTP 导致首页超时），
    /// 由 probeAll 后台标定后，后续请求自然纳入在线源。
    private func homeScope() -> [any MediaServerProtocol] {
        scope().filter { capabilities[$0.config.id]?.online == true }
    }

    /// 首屏快速源：内置红果 + NAS(mount 本地直读) 无需 HTTP 即可视为在线，
    /// 保证首次启动（probeAll 未标定前）首页也能立即出数据。
    private func quickScope() -> [any MediaServerProtocol] {
        scope().filter { s in
            switch s.config.kind {
            case .hongguo, .mount: return true
            default: return capabilities[s.config.id]?.online == true
            }
        }
    }

    /// 快速标定首屏快速源的在线状态（只 probe 红果/NAS 等，秒级返回）。
    public func probeQuick() async {
        let quick = scope().filter { [.hongguo, .mount, .webdav].contains($0.config.kind) }
        await withTaskGroup(of: (String, ServerCapability).self) { group in
            for s in quick {
                group.addTask { (s.config.id, await s.probe()) }
            }
            for await (k, cap) in group { capabilities[k] = cap }
        }
    }

    // MARK: - 连接状态

    /// 探测单个并缓存。
    @discardableResult
    public func probe(key: String) async -> ServerCapability {
        guard let s = servers[key] else {
            return ServerCapability(online: false, message: "server not found")
        }
        let cap = await s.probe()
        capabilities[key] = cap
        return cap
    }

    /// 探测全部（并发），返回 key → capability。
    public func probeAll() async -> [String: ServerCapability] {
        await withTaskGroup(of: (String, ServerCapability).self) { group in
            for (k, s) in servers where s.config.enabled {
                group.addTask { (k, await s.probe()) }
            }
            var out: [String: ServerCapability] = [:]
            for await (k, cap) in group {
                out[k] = cap
                capabilities[k] = cap
            }
            return out
        }
    }

    public func capability(key: String) -> ServerCapability? { capabilities[key] }

    /// 已缓存的连接状态快照（秒回，不触发探测）。
    public func cachedCapabilities() -> [String: ServerCapability] { capabilities }

    // MARK: - 聚合搜索

    /// 跨服务器聚合搜索：并发查作用域内所有源，按相关性归并，标注来源。
    /// 失败源静默跳过（单源挂不影响整体）。
    public func aggregateSearch(query: String, filter: SearchFilter) async -> [MediaItem] {
        let targets = liveScope()   // 只搜在线源，失败源不纳入
        return await withTaskGroup(of: [MediaItem].self) { group in
            for s in targets {
                group.addTask {
                    // 单源搜索超时保护（12s），慢源及时放弃不拖垮整体
                    await Self.withTimeout(seconds: 12) {
                        (try? await s.search(query: query, filter: filter)) ?? []
                    } ?? []
                }
            }
            var merged: [MediaItem] = []
            for await items in group { merged.append(contentsOf: items) }
            return Self.rank(merged, query: query)
        }
    }

    /// 超时包装：超时返回 nil。
    private static func withTimeout<T: Sendable>(seconds: UInt64,
                                                 _ work: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// 相关性排序：标题精确 > 前缀 > 包含 > 副标题命中，其次年份匹配。
    private static func rank(_ items: [MediaItem], query: String) -> [MediaItem] {
        let q = query.lowercased()
        func score(_ it: MediaItem) -> Int {
            let t = it.title.lowercased()
            var s = 0
            if t == q { s += 100 } else if t.hasPrefix(q) { s += 60 } else if t.contains(q) { s += 30 }
            if let sub = it.subTitle?.lowercased(), sub.contains(q) { s += 10 }
            if it.rate != nil { s += 2 }
            return s
        }
        return items.sorted { score($0) > score($1) }
    }

    // MARK: - 聚合首页

    /// 跨源「继续观看」归并（按各源返回，来源已标注）。
    public func aggregateContinueWatching(limit: Int) async -> [MediaItem] {
        await collect(limit: limit) { try? await $0.continueWatching(limit: limit) }
    }

    /// 跨源「最新入库」归并。
    public func aggregateRecentlyAdded(limit: Int) async -> [MediaItem] {
        await collect(limit: limit) { try? await $0.recentlyAdded(limit: limit) }
    }

    private func collect(limit: Int,
                         _ fetch: @escaping @Sendable (any MediaServerProtocol) async -> [MediaItem]?) async -> [MediaItem] {
        // 首屏用快速源（红果/NAS 即时 + 已在线源），probeAll 标定后自然纳入更多
        let targets = quickScope()
        guard !targets.isEmpty else { return [] }
        return await withTaskGroup(of: [MediaItem].self) { group in
            for s in targets {
                group.addTask { await fetch(s) ?? [] }
            }
            var merged: [MediaItem] = []
            for await items in group { merged.append(contentsOf: items) }
            return Array(merged.prefix(limit))
        }
    }

    // MARK: - 播放（自动路由到条目所属源）

    public func playback(item: MediaItem, quality: Quality?) async throws -> PlaybackSource {
        guard let s = servers[item.sourceKey] else { throw MediaServerError.notFound }
        return try await s.playback(item: item.id, quality: quality)
    }

    public func detail(item: MediaItem) async throws -> MediaDetail {
        guard let s = servers[item.sourceKey] else { throw MediaServerError.notFound }
        return try await s.detail(item: item.id)
    }

    // MARK: - 进度归并（本地持久化 + 服务端上报）

    /// 上报进度：服务端尽力而为 + 本地持久化（跨源续看的事实来源）。
    public func reportProgress(item: MediaItem, position: TimeInterval, state: PlayState) async {
        if let s = servers[item.sourceKey] {
            await s.reportProgress(item: item.id, position: position, state: state)
        }
        await ProgressStore.shared.save(item: item, position: position, state: state)
    }
}

// MARK: - 本地播放进度存储（跨源续看事实来源）
public actor ProgressStore {
    public static let shared = ProgressStore()

    public struct Record: Codable, Sendable {
        public var item: MediaItem
        public var position: TimeInterval
        public var state: PlayState
        public var updatedAt: Date
    }

    private var records: [String: Record] = [:]   // key = sourceKey + "|" + item.id
    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DramaCube", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("play-progress.json")
        records = Self.loadFrom(fileURL)
    }

    /// 非隔离静态加载，供 init 同步调用。
    private nonisolated static func loadFrom(_ url: URL) -> [String: Record] {
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([Record].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: arr.map { ("\($0.item.sourceKey)|\($0.item.id)", $0) })
    }

    private func key(of item: MediaItem) -> String { "\(item.sourceKey)|\(item.id)" }

    public func save(item: MediaItem, position: TimeInterval, state: PlayState) {
        records[key(of: item)] = Record(item: item, position: position, state: state, updatedAt: Date())
        persist()
    }

    public func position(for item: MediaItem) -> TimeInterval? {
        records[key(of: item)]?.position
    }

    /// 本地继续观看（按更新时间倒序）。
    public func continueWatching(limit: Int) -> [MediaItem] {
        records.values
            .filter { $0.state != .finished && $0.position > 30 }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0.item }
    }

    private func persist() {
        let arr = Array(records.values)
        if let data = try? JSONEncoder().encode(arr) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
