import Foundation
import HongguoCore

/// NAS 资源库引擎（WebDAV 直连 + 本机已挂载目录扫描）。
///
/// 两类源：
///  - `webdav`：填服务器地址 + 账号密码，PROPFIND 列目录，直链 HTTP GET 播放；
///  - `mount`：本机已挂载目录（如 macOS 已挂载的 SMB/AFP 卷 /Volumes/xxx），FileManager 扫描。
///
/// 库配置持久化到 Application Support/DramaCube/nas-libraries.json，升级重装不丢。
/// 媒体识别：按扩展名（mp4/mkv/mov/m4v/avi/wmv/flv/ts/m3u8）。
/// 目录即「剧集」：含 ≥2 个视频文件的目录聚合为一个 Drama，文件为集；单文件目录逐文件成剧。
public actor NASEngine {
    public static let shared = NASEngine()

    // MARK: - 模型

    public struct Library: Codable, Sendable, Identifiable, Hashable {
        public let id: String          // UUID
        public var name: String        // 用户命名（如「群晖电影库」）
        public var type: LibType       // webdav / mount
        public var baseURL: String     // webdav: http(s)://host:port/path；mount: /Volumes/xxx
        public var username: String?
        public var password: String?   // 明文存本地（个人 NAS 场景；不落 Keychain 以保持网关进程独立可读）
        public var enabled: Bool

        public enum LibType: String, Codable, Sendable { case webdav, mount }

        public init(id: String = UUID().uuidString, name: String, type: LibType,
                    baseURL: String, username: String? = nil, password: String? = nil, enabled: Bool = true) {
            self.id = id; self.name = name; self.type = type; self.baseURL = baseURL
            self.username = username; self.password = password; self.enabled = enabled
        }
    }

    public struct TestResult: Codable, Sendable {
        public let id: String
        public let ok: Bool
        public let latencyMs: Int
        public let videoCount: Int
        public let error: String?
    }

    private static let videoExts: Set<String> = ["mp4", "mkv", "mov", "m4v", "avi", "wmv", "flv", "ts", "m3u8"]

    // MARK: - 持久化

    private var libraries: [Library] = []
    private var loaded = false

    private static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DramaCube", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("nas-libraries.json")
    }

    private func loadIfNeeded() -> [Library] {
        // actor 内 let 常量不能改，用可变副本读
        if let data = try? Data(contentsOf: Self.storeURL),
           let list = try? JSONDecoder().decode([Library].self, from: data) {
            return list
        }
        return []
    }

    private func save() throws {
        let data = try JSONEncoder().encode(libraries)
        try data.write(to: Self.storeURL, options: .atomic)
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        libraries = loadIfNeeded()
        loaded = true
    }

    private init() {}

    // MARK: - CRUD

    public func allLibraries() -> [Library] {
        ensureLoaded()
        return libraries
    }

    @discardableResult
    public func addLibrary(_ lib: Library) throws -> Library {
        ensureLoaded()
        libraries.append(lib)
        try save()
        return lib
    }

    public func removeLibrary(id: String) throws {
        ensureLoaded()
        libraries.removeAll { $0.id == id }
        try save()
    }

    public func setEnabled(id: String, _ on: Bool) throws {
        ensureLoaded()
        guard let i = libraries.firstIndex(where: { $0.id == id }) else { return }
        libraries[i].enabled = on
        try save()
    }

    private func library(id: String) throws -> Library {
        ensureLoaded()
        guard let lib = libraries.first(where: { $0.id == id }) else { throw NASError.notFound }
        return lib
    }

    // MARK: - 连通性测试

    public func test(id: String) async -> TestResult {
        let t0 = Date()
        do {
            let lib = try library(id: id)
            let items = try await listVideos(lib: lib, path: "")
            return TestResult(id: id, ok: true,
                              latencyMs: Int(Date().timeIntervalSince(t0) * 1000),
                              videoCount: items.count, error: nil)
        } catch {
            return TestResult(id: id, ok: false,
                              latencyMs: Int(Date().timeIntervalSince(t0) * 1000),
                              videoCount: 0, error: error.localizedDescription)
        }
    }

    // MARK: - 浏览（聚合为 Drama）

    /// 浏览库根目录：目录（含视频）→ Drama（多集）；散文件 → 单集 Drama。
    public func browse(id: String, path: String) async throws -> [Drama] {
        let lib = try library(id: id)
        let entries = try await listEntries(lib: lib, path: path)
        var dramas: [Drama] = []

        // 目录：若（递归一层）含视频则聚合为一部剧
        for e in entries where e.isDir {
            let sub = try? await listVideos(lib: lib, path: join(path, e.name))
            guard let vids = sub, !vids.isEmpty else { continue }
            dramas.append(Drama(
                id: "nas|\(id)|dir|\(join(path, e.name))",
                title: e.name,
                coverURL: nil,
                episodeCount: vids.count,
                tags: [lib.name],
                updateStatus: "\(vids.count) 个视频"
            ))
        }
        // 散文件：逐文件成剧（单集）
        for e in entries where !e.isDir && Self.isVideo(e.name) {
            dramas.append(Drama(
                id: "nas|\(id)|file|\(join(path, e.name))",
                title: (e.name as NSString).deletingPathExtension,
                coverURL: nil,
                episodeCount: 1,
                tags: [lib.name],
                updateStatus: "单集"
            ))
        }
        return dramas
    }

    /// 目录剧集详情：列出目录内全部视频为集。
    public func detail(id: String, dirPath: String) async throws -> DramaDetail {
        let lib = try library(id: id)
        let vids = try await listVideos(lib: lib, path: dirPath)
        let episodes: [Episode] = vids.enumerated().map { idx, u in
            Episode(id: "\(idx + 1)",
                    index: idx + 1,
                    title: (u.lastPathComponent as NSString).deletingPathExtension,
                    playURL: u.absoluteString)
        }
        let name = (dirPath as NSString).lastPathComponent
        return DramaDetail(
            drama: Drama(id: "nas|\(id)|dir|\(dirPath)", title: name, coverURL: nil,
                         episodeCount: episodes.count, tags: [lib.name],
                         updateStatus: "\(episodes.count) 个视频"),
            episodes: episodes
        )
    }

    // MARK: - 播放地址（前端拼网关代理或直接 file/http）

    /// 把库内相对路径还原成可播 URL（webdav 拼鉴权后的 http 直链，mount 走 file://）。
    public func playURL(id: String, path: String) throws -> URL {
        let lib = try library(id: id)
        return try fileURL(lib: lib, path: path)
    }

    // MARK: - 内部：条目列举

    private struct Entry { let name: String; let isDir: Bool }

    private static func isVideo(_ name: String) -> Bool {
        videoExts.contains((name as NSString).pathExtension.lowercased())
    }

    private func join(_ base: String, _ name: String) -> String {
        base.isEmpty ? name : "\(base)/\(name)"
    }

    /// 列出某路径下的直接子条目（不递归）。
    private func listEntries(lib: Library, path: String) async throws -> [Entry] {
        switch lib.type {
        case .mount:
            let root = lib.baseURL
            let dir = path.isEmpty ? root : "\(root)/\(path)"
            let keys: [URLResourceKey] = [.isDirectoryKey]
            let urls = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: dir), includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles])
            return try urls.map { u in
                let r = try u.resourceValues(forKeys: [.isDirectoryKey])
                return Entry(name: u.lastPathComponent, isDir: r.isDirectory == true)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        case .webdav:
            return try await webdavList(lib: lib, path: path)
        }
    }

    /// 列出某路径下（递归一层）全部视频文件 URL。
    private func listVideos(lib: Library, path: String) async throws -> [URL] {
        let entries = try await listEntries(lib: lib, path: path)
        var out: [URL] = []
        for e in entries {
            if e.isDir {
                let sub = try await listEntries(lib: lib, path: join(path, e.name))
                for s in sub where !s.isDir && Self.isVideo(s.name) {
                    out.append(try fileURL(lib: lib, path: join(join(path, e.name), s.name)))
                }
            } else if Self.isVideo(e.name) {
                out.append(try fileURL(lib: lib, path: join(path, e.name)))
            }
        }
        return out.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func fileURL(lib: Library, path: String) throws -> URL {
        switch lib.type {
        case .mount:
            return URL(fileURLWithPath: path.isEmpty ? lib.baseURL : "\(lib.baseURL)/\(path)")
        case .webdav:
            let base = lib.baseURL.hasSuffix("/") ? String(lib.baseURL.dropLast()) : lib.baseURL
            let esc = path.split(separator: "/").map {
                String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
            }.joined(separator: "/")
            guard let u = URL(string: "\(base)/\(esc)") else { throw NASError.badURL }
            return u
        }
    }

    // MARK: - WebDAV PROPFIND

    private func webdavList(lib: Library, path: String) async throws -> [Entry] {
        let base = lib.baseURL.hasSuffix("/") ? String(lib.baseURL.dropLast()) : lib.baseURL
        let esc = path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        let urlStr = path.isEmpty ? "\(base)/" : "\(base)/\(esc)/"
        guard let url = URL(string: urlStr) else { throw NASError.badURL }

        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "PROPFIND"
        req.setValue("1", forHTTPHeaderField: "Depth")
        req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        if let u = lib.username, let p = lib.password, !u.isEmpty {
            let cred = "\(u):\(p)".data(using: .utf8)!.base64EncodedString()
            req.setValue("Basic \(cred)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <D:propfind xmlns:D="DAV:">
          <D:prop><D:displayname/><D:resourcetype/></D:prop>
        </D:propfind>
        """.utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NASError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return parseMultistatus(data: data, requestPath: url.path)
    }

    /// 解析 PROPFIND multistatus（用正则轻量解析，避免引 XML 依赖）。
    private func parseMultistatus(data: Data, requestPath: String) -> [Entry] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var out: [Entry] = []
        // 每个 <D:response> 块
        let respBlocks = xml.components(separatedBy: "<D:response>").dropFirst()
        for block in respBlocks {
            guard let hrefRange = block.range(of: "<D:href>"),
                  let hrefEnd = block.range(of: "</D:href>") else { continue }
            let href = String(block[hrefRange.upperBound..<hrefEnd.lowerBound])
            let isDir = block.contains("<D:collection")
            // 去掉自身（Depth:1 会包含请求路径本身）
            let clean = href.hasSuffix("/") ? String(href.dropLast()) : href
            let reqClean = requestPath.hasSuffix("/") ? String(requestPath.dropLast()) : requestPath
            if clean == reqClean || clean.isEmpty { continue }
            let name = URL(string: clean)?.lastPathComponent.removingPercentEncoding
                ?? (clean as NSString).lastPathComponent
            if name.isEmpty || name.hasPrefix(".") { continue }
            out.append(Entry(name: name, isDir: isDir))
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public enum NASError: LocalizedError {
        case notFound, badURL, http(Int)
        public var errorDescription: String? {
            switch self {
            case .notFound: return "资源库不存在"
            case .badURL: return "地址格式错误"
            case .http(let c): return "服务器返回 \(c)"
            }
        }
    }
}
