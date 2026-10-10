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

        // MARK: TVBox 视频源（maccms 聚合）
        // 订阅下载/解析/搜索/详情/播放代理由本机网关统一收口，前端不直连外网。

        // 导入订阅：/api/tvbox/import?url=<订阅地址> → {ok, data:{count}}
        router.get("api/tvbox/import") { request, _ async throws -> Response in
            guard let url = Self.queryValue(request, name: "url"), !url.isEmpty else {
                throw HTTPError(.badRequest, message: "missing url")
            }
            let count = try await TVBoxEngine.shared.importSubscription(url: url)
            return Self.json(GatewayEnvelope(ok: true, data: ["count": count]))
        }

        // 站点列表：/api/tvbox/sites
        router.get("api/tvbox/sites") { _, _ async throws -> Response in
            let sites = await TVBoxEngine.shared.allSites()
            return Self.json(GatewayEnvelope(ok: true, data: sites))
        }

        // 连通性测试：/api/tvbox/test?keys=a,b,c（无 keys 则全量）
        router.get("api/tvbox/test") { request, _ async throws -> Response in
            let keys = Self.queryValue(request, name: "keys")?
                .split(separator: ",").map { String($0) }.filter { !$0.isEmpty }
            let results = await TVBoxEngine.shared.testAll(keys: keys)
            return Self.json(GatewayEnvelope(ok: true, data: results))
        }

        // 站点最新列表：/api/tvbox/latest/:siteKey?page=n&t=typeId
        router.get("api/tvbox/latest/:site") { request, ctx async throws -> Response in
            guard let key = ctx.parameters.get("site", as: String.self), !key.isEmpty else {
                throw HTTPError(.badRequest, message: "missing site")
            }
            let page = Int(Self.queryValue(request, name: "page") ?? "1") ?? 1
            let typeId = Self.queryValue(request, name: "t").flatMap { Int($0) }
            let items = try await TVBoxEngine.shared.latest(siteKey: key, page: page, typeId: typeId)
            return Self.json(GatewayEnvelope(ok: true, data: items))
        }

        // 站点频道分类：/api/tvbox/categories/:site
        router.get("api/tvbox/categories/:site") { request, ctx async throws -> Response in
            guard let key = ctx.parameters.get("site", as: String.self), !key.isEmpty else {
                throw HTTPError(.badRequest, message: "missing site")
            }
            let cats = await TVBoxEngine.shared.categories(siteKey: key)
            return Self.json(GatewayEnvelope(ok: true, data: cats))
        }

        // 站点搜索：/api/tvbox/search/:site?q=xx&page=n
        router.get("api/tvbox/search/:site") { request, ctx async throws -> Response in
            guard let key = ctx.parameters.get("site", as: String.self), !key.isEmpty else {
                throw HTTPError(.badRequest, message: "missing site")
            }
            let q = Self.queryValue(request, name: "q") ?? ""
            let page = Int(Self.queryValue(request, name: "page") ?? "1") ?? 1
            let items = try await TVBoxEngine.shared.search(siteKey: key, query: q, page: page)
            return Self.json(GatewayEnvelope(ok: true, data: items))
        }

        // 站点详情：/api/tvbox/detail/:site/:id（含分集直链）
        router.get("api/tvbox/detail/:site/:id") { request, ctx async throws -> Response in
            guard let key = ctx.parameters.get("site", as: String.self), !key.isEmpty,
                  let id = ctx.parameters.get("id", as: String.self), !id.isEmpty else {
                throw HTTPError(.badRequest, message: "missing site/id")
            }
            let detail = try await TVBoxEngine.shared.detail(siteKey: key, vodId: id)
            return Self.json(GatewayEnvelope(ok: true, data: detail))
        }

        // 播放代理（解析模式）：/api/tvbox/play/:site/:id/:ep —— 重取详情选 m3u8 线路后代理
        router.get("api/tvbox/play/:site/:id/:ep") { request, ctx async throws -> Response in
            guard let key = ctx.parameters.get("site", as: String.self), !key.isEmpty,
                  let id = ctx.parameters.get("id", as: String.self), !id.isEmpty,
                  let ep = ctx.parameters.get("ep", as: Int.self) else {
                throw HTTPError(.badRequest, message: "missing site/id/ep")
            }
            let mainURL = try await TVBoxEngine.shared.resolvePlayURL(siteKey: key, vodId: id, episodeIndex: ep)
            return try await Self.proxyMedia(request, sourceURL: mainURL)
        }

        // MARK: NAS 资源库（WebDAV / 本机挂载目录）
        // 库配置由网关侧持久化（Application Support/nas-libraries.json），升级重装不丢。

        // 库列表：/api/nas/libraries
        router.get("api/nas/libraries") { _, _ async throws -> Response in
            let libs = await NASEngine.shared.allLibraries()
            return Self.json(GatewayEnvelope(ok: true, data: libs))
        }

        // 添加库：/api/nas/add?name=&type=webdav|mount&base=&user=&pass=
        router.get("api/nas/add") { request, _ async throws -> Response in
            guard let name = Self.queryValue(request, name: "name"), !name.isEmpty,
                  let typeStr = Self.queryValue(request, name: "type"),
                  let base = Self.queryValue(request, name: "base"), !base.isEmpty else {
                throw HTTPError(.badRequest, message: "missing name/type/base")
            }
            let type: NASEngine.Library.LibType = (typeStr == "mount") ? .mount : .webdav
            let lib = NASEngine.Library(
                name: name, type: type, baseURL: base,
                username: Self.queryValue(request, name: "user"),
                password: Self.queryValue(request, name: "pass"))
            let added = try await NASEngine.shared.addLibrary(lib)
            return Self.json(GatewayEnvelope(ok: true, data: added))
        }

        // 删除库：/api/nas/remove?id=
        router.get("api/nas/remove") { request, _ async throws -> Response in
            guard let id = Self.queryValue(request, name: "id"), !id.isEmpty else {
                throw HTTPError(.badRequest, message: "missing id")
            }
            try await NASEngine.shared.removeLibrary(id: id)
            return Self.json(GatewayEnvelope(ok: true, data: ["removed": id]))
        }

        // 开关库：/api/nas/toggle?id=&on=1
        router.get("api/nas/toggle") { request, _ async throws -> Response in
            guard let id = Self.queryValue(request, name: "id"), !id.isEmpty else {
                throw HTTPError(.badRequest, message: "missing id")
            }
            let on = (Self.queryValue(request, name: "on") ?? "1") == "1"
            try await NASEngine.shared.setEnabled(id: id, on)
            return Self.json(GatewayEnvelope(ok: true, data: ["id": id, "on": on ? "1" : "0"]))
        }

        // 测试库：/api/nas/test?id=
        router.get("api/nas/test") { request, _ async throws -> Response in
            guard let id = Self.queryValue(request, name: "id"), !id.isEmpty else {
                throw HTTPError(.badRequest, message: "missing id")
            }
            let r = await NASEngine.shared.test(id: id)
            return Self.json(GatewayEnvelope(ok: true, data: r))
        }

        // 浏览库：/api/nas/browse/:id?path=  （目录聚合为 Drama）
        router.get("api/nas/browse/:id") { request, ctx async throws -> Response in
            guard let id = ctx.parameters.get("id", as: String.self), !id.isEmpty else {
                throw HTTPError(.badRequest, message: "missing id")
            }
            let path = Self.queryValue(request, name: "path") ?? ""
            let items = try await NASEngine.shared.browse(id: id, path: path)
            return Self.json(GatewayEnvelope(ok: true, data: items))
        }

        // 目录详情：/api/nas/detail/:id?path=
        router.get("api/nas/detail/:id") { request, ctx async throws -> Response in
            guard let id = ctx.parameters.get("id", as: String.self), !id.isEmpty else {
                throw HTTPError(.badRequest, message: "missing id")
            }
            let path = Self.queryValue(request, name: "path") ?? ""
            let detail = try await NASEngine.shared.detail(id: id, dirPath: path)
            return Self.json(GatewayEnvelope(ok: true, data: detail))
        }

        // 播放地址还原：/api/nas/playurl/:id?path= → {ok, data:{url}}
        // webdav 返回网关代理地址（/api/nas/stream，附带鉴权）；mount 返回 file:// 直读。
        router.get("api/nas/playurl/:id") { request, ctx async throws -> Response in
            guard let id = ctx.parameters.get("id", as: String.self), !id.isEmpty else {
                throw HTTPError(.badRequest, message: "missing id")
            }
            let path = Self.queryValue(request, name: "path") ?? ""
            if let url = try await NASEngine.shared.playURL(id: id, path: path) {
                return Self.json(GatewayEnvelope(ok: true, data: ["url": url.absoluteString]))
            }
            let esc = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return Self.json(GatewayEnvelope(ok: true, data: ["url": "/api/nas/stream/\(id)?path=\(esc)"]))
        }

        // WebDAV 媒体流式代理：/api/nas/stream/:id?path= —— 带 Basic 鉴权 + Range 透传。
        // 裸直链给 AVPlayer 会 401（NSURLError -1013），必须经网关附鉴权头。
        router.get("api/nas/stream/:id") { request, ctx async throws -> Response in
            guard let id = ctx.parameters.get("id", as: String.self), !id.isEmpty else {
                throw HTTPError(.badRequest, message: "missing id")
            }
            let path = Self.queryValue(request, name: "path") ?? ""
            let range = request.headers[.range].flatMap { $0.isEmpty ? nil : $0 }
            let stream = try await NASEngine.shared.openStream(id: id, path: path, range: range)
            var headers = HTTPFields()
            headers[.contentType] = stream.contentType
            if let cl = stream.contentLength { headers[.contentLength] = cl }
            if let cr = stream.contentRange { headers[.contentRange] = cr }
            headers[.acceptRanges] = "bytes"
            let status: HTTPResponse.Status = stream.status == 206 ? .partialContent : .ok
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
