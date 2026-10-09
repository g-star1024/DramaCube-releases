import Foundation
import HongguoCore

/// 前端网关访问层。所有请求打本机 127.0.0.1:8787，不直接触外网。
///
/// 网关由 App 进程内 `GatewayController` 启动，可能略晚于首屏；
/// `decode` 对「连接被拒」类网络错误自动重试 3 次（间隔 1s），覆盖冷启动窗口。
@MainActor
public final class CatalogService: ObservableObject {
    public static let shared = CatalogService()
    private let base = AppConfig.gatewayBaseURL

    @Published public var items: [Drama] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?

    private init() {}

    private func decode<T: Codable & Sendable>(_ path: String, retries: Int = 3) async throws -> T {
        guard let url = URL(string: base + path) else {
            throw HongguoParseError.fieldMissing("url")
        }
        var lastError: Error?
        for attempt in 0..<max(1, retries) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let env = try JSONDecoder().decode(GatewayEnvelope<T>.self, from: data)
                if let e = env.error { throw HongguoParseError.fieldMissing(e) }
                guard let d = env.data else { throw HongguoParseError.fieldMissing("data") }
                return d
            } catch is URLError {
                lastError = URLError(.cannotConnectToHost)
                if attempt < retries - 1 { try? await Task.sleep(nanoseconds: 1_000_000_000) }
            }
        }
        throw lastError ?? HongguoParseError.fieldMissing("network")
    }

    public func search(_ query: String) async {
        isLoading = true; errorMessage = nil
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        do {
            items = try await decode("/api/search?q=\(q)")
        } catch {
            errorMessage = "搜索失败：\(error.localizedDescription)"
            items = []
        }
        isLoading = false
    }

    public func loadCatalog(path: String) async {
        isLoading = true; errorMessage = nil
        let p = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "/"
        do {
            items = try await decode("/api/catalog?path=\(p)")
        } catch {
            errorMessage = "加载失败：\(error.localizedDescription)"
            items = []
        }
        isLoading = false
    }

    public func detail(id: String) async -> DramaDetail? {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        return try? await decode("/api/detail/\(safe)")
    }
}
