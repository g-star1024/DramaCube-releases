import Foundation
import HongguoCore

/// 前端网关访问层。所有请求打本机 127.0.0.1:8787，不直接触外网。
///
/// 网关由 App 进程内 `GatewayController` 启动，可能略晚于首屏；
/// `decode` 对「连接被拒」类网络错误自动重试 3 次（间隔 1s），覆盖冷启动窗口。
///
/// 所有方法返回解包后的业务数据（不污染共享状态），由各 View 自管 `@State`，
/// 以便发现/排行榜/探索多分区并存互不干扰。
@MainActor
public final class CatalogService: ObservableObject {
    public static let shared = CatalogService()
    private let base = AppConfig.gatewayBaseURL

    private init() {}

    /// 把网关响应统一解包；对连接类错误重试以覆盖网关冷启动。
    /// JSON 解码放后台线程（v1.0.5 卡死修复）：列表/详情 payload 可达数百 KB，
    /// JSONDecoder 在主线程执行会造成可感知的掉帧。
    private func decode<T: Codable & Sendable>(_ url: URL, retries: Int = 3) async throws -> T {
        var lastError: Error?
        let tag = url.path + (url.query.map { "?\($0)" } ?? "")
        for attempt in 0..<max(1, retries) {
            let t0 = Date()
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                let env = try await Task.detached(priority: .userInitiated) {
                    try JSONDecoder().decode(GatewayEnvelope<T>.self, from: data)
                }.value
                AppLog.log(.net, "GET \(tag) → \(code) \(data.count >> 10)KB \(Int(Date().timeIntervalSince(t0) * 1000))ms")
                if let e = env.error { throw HongguoParseError.fieldMissing(e) }
                guard let d = env.data else { throw HongguoParseError.fieldMissing("data") }
                return d
            } catch let e as URLError {
                AppLog.log(.net, "GET \(tag) ✗ 网络错误(\(e.code.rawValue)) 第\(attempt + 1)次")
                lastError = URLError(.cannotConnectToHost)
                if attempt < retries - 1 { try? await Task.sleep(nanoseconds: 1_000_000_000) }
            } catch {
                AppLog.log(.error, "GET \(tag) ✗ \(error.localizedDescription)")
                throw error
            }
        }
        throw lastError ?? HongguoParseError.fieldMissing("network")
    }

    /// 列表：/api/catalog?path=<path>&page=<n>
    public func catalog(path: String, page: Int = 1) async throws -> [Drama] {
        let p = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let q = page > 1 ? "&page=\(page)" : ""
        guard let url = URL(string: "\(base)/api/catalog?path=\(p)\(q)") else {
            throw HongguoParseError.fieldMissing("url")
        }
        return try await decode(url)
    }

    /// 搜索：/api/search?q=<query>
    public func search(query: String) async throws -> [Drama] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "\(base)/api/search?q=\(q)") else {
            throw HongguoParseError.fieldMissing("url")
        }
        return try await decode(url)
    }

    /// 详情：/api/detail/:id
    public func detail(id: String) async throws -> DramaDetail {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        guard let url = URL(string: "\(base)/api/detail/\(safe)") else {
            throw HongguoParseError.fieldMissing("url")
        }
        return try await decode(url)
    }

    // MARK: - 豆瓣热门（MoonTVPlus 首页形式）

    /// 豆瓣热门条目（对齐网关 CoverEngine.DoubanHotItem）。
    public struct DoubanHotItem: Codable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let poster: String
        public let rate: String
        public let year: String
    }

    /// 拉豆瓣热门列表（kind: movie/tv；category/type 对齐 MoonTVPlus）。
    public func doubanHot(kind: String, category: String, type: String, limit: Int = 18, start: Int = 0) async throws -> [DoubanHotItem] {
        let cat = category.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? category
        let typ = type.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? type
        guard let url = URL(string: "\(base)/api/douban/hot?kind=\(kind)&category=\(cat)&type=\(typ)&limit=\(limit)&start=\(start)") else {
            throw HongguoParseError.fieldMissing("url")
        }
        return try await decode(url)
    }
}
