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
            // 连通性测试：只列根目录确认可达（不全库递归扫描，避免大库测试卡几十秒）
            _ = try await listEntries(lib: lib, path: "")
            // 视频数用一次限深递归粗估（复用 listVideos 的递归，但有 maxTotal 上限兜底）
            let vids = (try? await listVideos(lib: lib, path: "")) ?? []
            return TestResult(id: id, ok: true,
                              latencyMs: Int(Date().timeIntervalSince(t0) * 1000),
                              videoCount: vids.count, error: nil)
        } catch {
            return TestResult(id: id, ok: false,
                              latencyMs: Int(Date().timeIntervalSince(t0) * 1000),
                              videoCount: 0, error: error.localizedDescription)
        }
    }

    // MARK: - 浏览（直出视频列表）

    /// 浏览库：递归收集当前路径下全部视频文件，直出为可点播的单集列表（不聚合目录成卡片）。
    /// 目录仅用于路径导航（前端 pathBar），不作为内容展示。
    public func browse(id: String, path: String) async throws -> [Drama] {
        let lib = try library(id: id)
        let videos = try await listVideosWithPaths(lib: lib, path: path)
        return videos.map { (relPath, url) in
            Drama(
                id: "nas|\(id)|file|\(relPath)",
                title: (relPath as NSString).deletingPathExtension.components(separatedBy: "/").last ?? relPath,
                coverURL: nil,
                episodeCount: 1,
                tags: [lib.name],
                updateStatus: (relPath as NSString).pathExtension.uppercased()
            )
        }
    }

    /// 递归收集路径下全部视频（相对路径 + 可播 URL），按相对路径排序。
    private func listVideosWithPaths(lib: Library, path: String) async throws -> [(String, URL)] {
        var out: [(String, URL)] = []
        await collectVideos(lib: lib, path: path, depth: 0, into: &out)
        return out.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
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

    /// 把库内相对路径还原成可播 URL。
    ///  - mount：file:// 直读（AVPlayer 原生支持 Range）；
    ///  - webdav：返回 nil —— 飞牛等 WebDAV 需要 Basic 鉴权，裸直链给 AVPlayer 会 401
    ///    （实测 NSURLError -1013），必须经网关 /api/nas/stream 代理附带鉴权。
    public func playURL(id: String, path: String) throws -> URL? {
        let lib = try library(id: id)
        switch lib.type {
        case .mount: return try fileURL(lib: lib, path: path)
        case .webdav: return nil
        }
    }

    /// WebDAV 媒体流式代理：带 Basic 鉴权 + 透传 Range，206/Content-Range 原样返回。
    /// AVPlayer 的 seek 依赖 Range 支持（与 hongguo 源 proxyMedia 同一套设计）。
    public func openStream(id: String, path: String, range: String?) async throws -> NASStream {
        let lib = try library(id: id)
        guard lib.type == .webdav else { throw NASError.notStreamable }
        let url = try fileURL(lib: lib, path: path)
        var req = URLRequest(url: url, timeoutInterval: 60)
        if let u = lib.username, let p = lib.password, !u.isEmpty {
            let cred = "\(u):\(p)".data(using: .utf8)!.base64EncodedString()
            req.setValue("Basic \(cred)", forHTTPHeaderField: "Authorization")
        }
        if let range, !range.isEmpty { req.setValue(range, forHTTPHeaderField: "Range") }
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        let http = resp as? HTTPURLResponse
        if let code = http?.statusCode, !(200..<300).contains(code) {
            throw NASError.http(code)
        }
        return NASStream(
            status: http?.statusCode ?? 200,
            contentType: http?.value(forHTTPHeaderField: "Content-Type") ?? "video/mp4",
            contentLength: http?.value(forHTTPHeaderField: "Content-Length"),
            contentRange: http?.value(forHTTPHeaderField: "Content-Range"),
            bytes: bytes
        )
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

    /// 递归扫描某路径下全部视频文件 URL。
    ///
    /// 早期版本只递归 1 层，遇到「电影/年份/片名/xx.mp4」这类 ≥3 层结构会全盘扫空
    /// （实测飞牛 NAS：movie/feigrampub/... 视频在 3 层以下，导致测试显示 0 视频、浏览空白）。
    /// 现改为递归扫描：限深 `maxDepth`、单目录限量 `maxEntries`、总量上限 `maxTotal`，
    /// 防止巨型库扫爆；子目录失败跳过不拖垮整体。
    private func listVideos(lib: Library, path: String) async throws -> [URL] {
        var out: [URL] = []
        try await collectVideos(lib: lib, path: path, depth: 0, into: &out)
        return out.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private let maxDepth = 5
    private let maxEntries = 500   // 单目录最多处理条目
    private let maxTotal = 5000    // 全库视频总量上限

    private func collectVideos(lib: Library, path: String, depth: Int, into out: inout [URL]) async throws {
        if depth > maxDepth || out.count >= maxTotal { return }
        let entries: [Entry]
        do {
            entries = try await listEntries(lib: lib, path: path)
        } catch {
            return // 单目录失败（权限/超时）跳过，不中断整体扫描
        }
        for e in entries.prefix(maxEntries) {
            if out.count >= maxTotal { return }
            if e.isDir {
                try await collectVideos(lib: lib, path: join(path, e.name), depth: depth + 1, into: &out)
            } else if Self.isVideo(e.name) {
                if let u = try? fileURL(lib: lib, path: join(path, e.name)) {
                    out.append(u)
                }
            }
        }
    }

    /// 带相对路径的递归收集（browse 直出视频列表用）。
    private func collectVideos(lib: Library, path: String, depth: Int, into out: inout [(String, URL)]) async {
        if depth > maxDepth || out.count >= maxTotal { return }
        guard let entries = try? await listEntries(lib: lib, path: path) else { return }
        for e in entries.prefix(maxEntries) {
            if out.count >= maxTotal { return }
            let rel = join(path, e.name)
            if e.isDir {
                await collectVideos(lib: lib, path: rel, depth: depth + 1, into: &out)
            } else if Self.isVideo(e.name) {
                if let u = try? fileURL(lib: lib, path: rel) {
                    out.append((rel, u))
                }
            }
        }
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
        case notFound, badURL, notStreamable, http(Int)
        public var errorDescription: String? {
            switch self {
            case .notFound: return "资源库不存在"
            case .badURL: return "地址格式错误"
            case .notStreamable: return "本机挂载目录不走流式代理"
            case .http(let c): return "服务器返回 \(c)"
            }
        }
    }
}

/// NAS WebDAV 流式响应（网关代理透传用）。
public struct NASStream: Sendable {
    public let status: Int
    public let contentType: String
    public let contentLength: String?
    public let contentRange: String?
    public let bytes: URLSession.AsyncBytes
}
