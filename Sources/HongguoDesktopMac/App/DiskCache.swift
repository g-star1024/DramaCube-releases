import Foundation

/// 轻量文件缓存：把列表 / 详情 JSON 落盘到 Application Support，
/// 实现「先展示缓存 → 后台刷新 → 回写缓存」的 cache-then-network 策略。
///
/// 存储路径：~/Library/Application Support/DramaCube/Cache/<sha1(url)>.json
actor DiskCache {
    static let shared = DiskCache()

    private let dir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        dir = base.appendingPathComponent("DramaCube/Cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String) -> URL {
        let digest = sha1(key)
        return dir.appendingPathComponent("\(digest).json")
    }

    /// 读取缓存；超过 maxAge 秒视为过期（仍可返回，由调用方决定是否先展示）。
    func read<T: Codable>(_ type: T.Type, key: String) -> T? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func write<T: Codable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    func remove(key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    /// 清空全部缓存（设置页可用）。
    func clearAll() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func sha1(_ s: String) -> String {
        // 简易指纹即可（仅文件名用途），无需密码学强度。
        var h1: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h1 ^= UInt64(b)
            h1 = h1 &* 0x100000001b3
        }
        var h2: UInt64 = 0x84222325cbf29ce4
        for b in s.utf8.reversed() {
            h2 ^= UInt64(b)
            h2 = h2 &* 0x100000001b3
        }
        return String(format: "%016llx%016llx", h1, h2)
    }
}
