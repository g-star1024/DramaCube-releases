import Foundation
import Hummingbird
import NIOCore
import HongguoCore

/// 红果桌面 Mac 版本地网关。
///
/// 前端（SwiftUI）只与本机 127.0.0.1 的网关通信，所有外网请求在此统一收口：
///  - 浏览 / 搜索 / 详情：解析 novelquickapp.com 落地页
///  - 播放：代理 CDN 直链并剥离 Referer（绕过字节 CDN 防盗链）
@main
struct Gateway {
    static func main() async throws {
        let router = Router()

        router.get("api/health") { _, _ in
            return "ok"
        }

        // 详情：/api/detail/:id
        router.get("api/detail/:id") { request, ctx async throws -> Response in
            guard let id = ctx.parameters.get("id", as: String.self), !id.isEmpty else {
                throw HTTPError(.badRequest, message: "missing id")
            }
            let detail = try await HongguoClient.shared.fetchDetail(id: id)
            return json(GatewayEnvelope(ok: true, data: detail))
        }

        // 搜索：/api/search?q=xxx
        router.get("api/search") { request, _ async throws -> Response in
            let q = queryValue(request, name: "q") ?? ""
            let items = try await HongguoClient.shared.search(query: q)
            return json(GatewayEnvelope(ok: true, data: items))
        }

        // 列表：/api/catalog?path=/rank
        router.get("api/catalog") { request, _ async throws -> Response in
            let path = queryValue(request, name: "path") ?? "/"
            let items = try await HongguoClient.shared.catalog(path: path)
            return json(GatewayEnvelope(ok: true, data: items))
        }

        // 播放代理：/api/play?url=<CDN直链> —— 剥离 Referer 请求
        router.get("api/play") { request, _ async throws -> Response in
            guard let url = queryValue(request, name: "url"), !url.isEmpty else {
                throw HTTPError(.badRequest, message: "missing url")
            }
            let (data, ct) = try await HongguoClient.shared.fetchMedia(url)
            var headers = HTTPFields()
            headers[.contentType] = ct
            return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(data: data)))
        }

        var configuration = ApplicationConfiguration()
        configuration.address = .hostname("127.0.0.1", port: 8787)
        var app = Application(router: router, configuration: configuration)
        app.logger.logLevel = .info
        try await app.run()
    }

    /// 把 Encodable 编码为 JSON 响应的辅助（HB2 的 ResponseGenerator 不直接支持 Codable）。
    private static func json<T: Encodable>(_ value: T) -> Response {
        let data = (try? JSONEncoder().encode(value)) ?? Data()
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(data: data)))
    }

    /// 从请求 query 中安全取参数（HB2 无强类型 query，自行解析）。
    private static func queryValue(_ request: Request, name: String) -> String? {
        guard let raw = request.uri.query,
              let comps = URLComponents(string: "?" + raw) else { return nil }
        return comps.queryItems?.first(where: { $0.name == name })?.value
    }
}
