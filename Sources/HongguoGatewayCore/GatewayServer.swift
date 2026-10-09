import Foundation
import Hummingbird
import NIOCore
import HongguoCore

/// 红果桌面 Mac 版本地网关核心。
///
/// 前端（SwiftUI）只与本机 127.0.0.1 的网关通信，所有外网请求在此统一收口：
///  - 浏览 / 搜索 / 详情：解析 novelquickapp.com 落地页
///  - 播放：代理 CDN 直链并剥离 Referer（绕过字节 CDN 防盗链）
///
/// 该核心同时被两处复用：
///  - `HongguoGateway` 可执行文件（独立运行 / 调试用）
///  - `HongguoDesktopMac` App（进程内启动，随 App 生命周期）
public enum GatewayServer {

    /// 构建路由表（与运行方式无关，便于测试与复用）。
    public static func makeRouter() -> Router<BasicRequestContext> {
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

        // 列表：/api/catalog?path=/rank&page=2
        router.get("api/catalog") { request, _ async throws -> Response in
            let path = queryValue(request, name: "path") ?? "/"
            let page = Int(queryValue(request, name: "page") ?? "1") ?? 1
            let items = try await HongguoClient.shared.catalog(path: path, page: page)
            return json(GatewayEnvelope(ok: true, data: items))
        }

        // 播放代理（直链模式）：/api/play?url=<CDN直链> —— Range 透传 + 流式转发
        router.get("api/play") { request, _ async throws -> Response in
            guard let url = queryValue(request, name: "url"), !url.isEmpty else {
                throw HTTPError(.badRequest, message: "missing url")
            }
            return try await Self.proxyMedia(request, sourceURL: url)
        }

        // 播放代理（解析模式）：/api/stream/<seriesId>/<vid>
        // 先解析 /player/<sid>/<vid> 拿 main_url，再代理 CDN（剥离 Referer、Range 透传）。
        router.get("api/stream/:sid/:vid") { request, ctx async throws -> Response in
            guard let sid = ctx.parameters.get("sid", as: String.self), !sid.isEmpty,
                  let vid = ctx.parameters.get("vid", as: String.self), !vid.isEmpty else {
                throw HTTPError(.badRequest, message: "missing sid/vid")
            }
            let mainURL = try await HongguoClient.shared.resolvePlayURL(seriesId: sid, vid: vid)
            return try await Self.proxyMedia(request, sourceURL: mainURL)
        }

        return router
    }

    /// 媒体流式代理：透传客户端 Range 请求头，CDN 的 206/200、Content-Range、
    /// Content-Length、Content-Type 原样回传，body 用 AsyncBytes 边收边发。
    /// 这是 AVPlayer 能正常 seek / 秒开的关键（此前全量缓冲导致播放失败）。
    private static func proxyMedia(_ request: Request, sourceURL: String) async throws -> Response {
        let range = request.headers[.range].flatMap { $0.isEmpty ? nil : $0 }
        let stream = try await HongguoClient.shared.openMediaStream(sourceURL, range: range)
        var headers = HTTPFields()
        headers[.contentType] = stream.contentType
        if let cl = stream.contentLength { headers[.contentLength] = cl }
        if let cr = stream.contentRange { headers[.contentRange] = cr }
        headers[.acceptRanges] = "bytes"
        let status: HTTPResponse.Status = stream.status == 206 ? .partialContent : .ok
        // 64KB 缓冲批量写：URLSession.AsyncBytes 逐字节产出，直接转发会产生海量小包。
        let body = ResponseBody { writer in
            var buffer = [UInt8]()
            buffer.reserveCapacity(65_536)
            for try await byte in stream.bytes {
                buffer.append(byte)
                if buffer.count >= 65_536 {
                    try await writer.write(ByteBuffer(bytes: buffer))
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            if !buffer.isEmpty {
                try await writer.write(ByteBuffer(bytes: buffer))
            }
        }
        return Response(status: status, headers: headers, body: body)
    }

    /// 前台运行网关（阻塞直到 app 停止）。供独立可执行文件与 App 进程内调用。
    public static func run(port: Int) async throws {
        var configuration = ApplicationConfiguration()
        configuration.address = .hostname("127.0.0.1", port: port)
        var app = Application(router: makeRouter(), configuration: configuration)
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
