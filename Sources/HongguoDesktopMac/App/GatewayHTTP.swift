import Foundation
import HongguoCore

// MARK: - 网关统一直连 HTTP（v2.0.3）
// 所有前端 → 本地网关（127.0.0.1:8787）的请求都走这里：
//  ① 直连（connectionProxyDictionary=[:]），绕过全局代理拦截本地回环；
//  ② 启动窗口期轮询等网关就绪，避免「网关未起听一次性失败」；
//  ③ 连接类错误自动重试（指数退避）。
// 修「媒体中枢点重试无效 / 各模块启动期连不上网关」的统一入口。

public enum GatewayHTTP {

    /// 共享直连 session（绕过系统代理）。
    public static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.connectionProxyDictionary = [:]
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 60
        return URLSession(configuration: c)
    }()

    private static var base: String { AppConfig.gatewayBaseURL }

    /// 等待网关就绪（轮询 /api/health）。最多 ~15s。
    @discardableResult
    public static func waitReady(maxAttempts: Int = 30) async -> Bool {
        guard let url = URL(string: "\(base)/api/health") else { return false }
        for _ in 0..<maxAttempts {
            if let (data, resp) = try? await session.data(from: url),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               obj["ok"] != nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    /// GET 并解包网关信封，连接类错误自动重试。
    /// - Parameters:
    ///   - path: 网关路径（含查询串），如 "/api/servers"。
    ///   - retries: 失败重试次数（默认 3）。
    ///   - timeout: 单次请求超时（默认 20s）。
    public static func get<T: Codable & Sendable>(_ path: String, retries: Int = 3, timeout: TimeInterval = 20) async throws -> T {
        guard let url = URL(string: "\(base)\(path)") else { throw URLError(.badURL) }
        var lastError: Error = URLError(.cannotConnectToHost)
        for attempt in 0..<max(1, retries) {
            do {
                var req = URLRequest(url: url, timeoutInterval: timeout)
                req.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, _) = try await session.data(for: req)
                let env = try JSONDecoder().decode(GatewayEnvelope<T>.self, from: data)
                if let e = env.error { throw HongguoParseError.fieldMissing(e) }
                guard let d = env.data else { throw HongguoParseError.fieldMissing("data") }
                return d
            } catch {
                lastError = error
                if attempt < retries - 1 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 700_000_000)
                }
            }
        }
        throw lastError
    }
}
