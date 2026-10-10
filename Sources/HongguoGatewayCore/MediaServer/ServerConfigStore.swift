import Foundation

// MARK: - 用户自建服务器配置存储（M3）
// 用户添加的 Emby/Jellyfin/AList/Subsonic/audiobookshelf 服务器持久化到 Application Support。
// 对标 Cinetry「保存多个服务器配置，避免重复输入」。

public actor ServerConfigStore {
    public static let shared = ServerConfigStore()

    private var configs: [String: MediaServerConfig] = [:]
    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DramaCube", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("media-servers.json")
        configs = Self.load(fileURL)
    }

    private nonisolated static func load(_ url: URL) -> [String: MediaServerConfig] {
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([MediaServerConfig].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: arr.map { ($0.id, $0) })
    }

    public func all() -> [MediaServerConfig] {
        configs.values.sorted { $0.name < $1.name }
    }

    public func add(_ config: MediaServerConfig) {
        configs[config.id] = config
        persist()
    }

    public func remove(id: String) {
        configs.removeValue(forKey: id)
        persist()
    }

    public func setEnabled(id: String, _ on: Bool) {
        configs[id]?.enabled = on
        persist()
    }

    public func config(id: String) -> MediaServerConfig? { configs[id] }

    private func persist() {
        if let data = try? JSONEncoder().encode(Array(configs.values)) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 按 config 构造对应适配器。
    public static func makeAdapter(for config: MediaServerConfig) -> (any MediaServerProtocol)? {
        switch config.kind {
        case .emby, .jellyfin: return EmbyAdapter(config: config)
        case .alist, .openlist: return AListAdapter(config: config)
        case .subsonic, .navidrome: return SubsonicAdapter(config: config)
        case .audiobookshelf: return AudiobookshelfAdapter(config: config)
        default: return nil   // tvbox/nas/iptv 由各自引擎装配，不在此存储
        }
    }
}
