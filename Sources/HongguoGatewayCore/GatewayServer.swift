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
            let results = await TVBoxEngine.shared.importSubscriptionDetailed(url: url)
            let added = results.reduce(0) { $0 + $1.added }
            // 兼容字段 count + 新明细 results（前端展示每地址成败）
            struct ImportPayload: Codable {
                let count: Int
                let results: [TVBoxEngine.ImportResult]
            }
            return Self.json(GatewayEnvelope(ok: true, data: ImportPayload(count: added, results: results)))
        }

        // 已存订阅地址列表：/api/tvbox/subscriptions
        router.get("api/tvbox/subscriptions") { _, _ async throws -> Response in
            let urls = await TVBoxEngine.shared.savedSubscriptionURLs()
            return Self.json(GatewayEnvelope(ok: true, data: urls))
        }

        // 删除订阅地址：/api/tvbox/removesub?url=
        router.get("api/tvbox/removesub") { request, _ async throws -> Response in
            guard let url = Self.queryValue(request, name: "url"), !url.isEmpty else {
                throw HTTPError(.badRequest, message: "missing url")
            }
            await TVBoxEngine.shared.removeSubscriptionURL(url)
            return Self.json(GatewayEnvelope(ok: true, data: ["removed": url]))
        }

        // 重新拉取全部已存订阅：/api/tvbox/refreshsubs
        router.get("api/tvbox/refreshsubs") { _, _ async throws -> Response in
            let results = await TVBoxEngine.shared.refreshAllSubscriptions()
            return Self.json(GatewayEnvelope(ok: true, data: results))
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
            // 容错：个别采集站/频道返回非法 JSON（截断/非 JSON）时，latest 已尽力抢救；
            // 仍彻底失败则返回空列表而非整页报错，让前端展示「该源暂无内容」而非错误页。
            let items = (try? await TVBoxEngine.shared.latest(siteKey: key, page: page, typeId: typeId)) ?? []
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

        // MARK: 电视直播（m3u 源聚合）
        // 直播源配置持久化（live-sources.json），频道列表排重合并按组返回。

        // 直播源列表：/api/live/sources
        router.get("api/live/sources") { _, _ async throws -> Response in
            let list = await LiveEngine.shared.allSources()
            return Self.json(GatewayEnvelope(ok: true, data: list))
        }

        // 添加直播源：/api/live/add?url=&name=&ua=  （url 相同幂等更新，不重复计数）
        router.get("api/live/add") { request, _ async throws -> Response in
            guard let url = Self.queryValue(request, name: "url"), !url.isEmpty else {
                throw HTTPError(.badRequest, message: "missing url")
            }
            let name = Self.queryValue(request, name: "name")
            let ua = Self.queryValue(request, name: "ua")
            let added = try await LiveEngine.shared.addSource(url: url, name: name, userAgent: ua)
            await LiveEngine.shared.invalidateCache()
            return Self.json(GatewayEnvelope(ok: true, data: added))
        }

        // 删除直播源：/api/live/remove?id=
        router.get("api/live/remove") { request, _ async throws -> Response in
            guard let id = Self.queryValue(request, name: "id"), !id.isEmpty else {
                throw HTTPError(.badRequest, message: "missing id")
            }
            try await LiveEngine.shared.removeSource(id: id)
            await LiveEngine.shared.invalidateCache()
            return Self.json(GatewayEnvelope(ok: true, data: ["removed": id]))
        }

        // 开关直播源：/api/live/toggle?id=&on=1
        router.get("api/live/toggle") { request, _ async throws -> Response in
            guard let id = Self.queryValue(request, name: "id"), !id.isEmpty else {
                throw HTTPError(.badRequest, message: "missing id")
            }
            let on = (Self.queryValue(request, name: "on") ?? "1") == "1"
            try await LiveEngine.shared.setEnabled(id: id, on)
            await LiveEngine.shared.invalidateCache()
            return Self.json(GatewayEnvelope(ok: true, data: ["id": id, "on": on ? "1" : "0"]))
        }

        // 单选当前启用的直播源：/api/live/setactive?id=（其余源自动禁用，避免多源混杂）
        router.get("api/live/setactive") { request, _ async throws -> Response in
            guard let id = Self.queryValue(request, name: "id"), !id.isEmpty else {
                throw HTTPError(.badRequest, message: "missing id")
            }
            try await LiveEngine.shared.setActiveSource(id: id)
            return Self.json(GatewayEnvelope(ok: true, data: ["active": id]))
        }

        // 单源探活：/api/live/testsource?id=（拉源解析返回频道数，切换前判断源是否可用）
        router.get("api/live/testsource") { request, _ async throws -> Response in
            guard let id = Self.queryValue(request, name: "id"), !id.isEmpty else {
                throw HTTPError(.badRequest, message: "missing id")
            }
            let count = await LiveEngine.shared.testSource(id: id)
            return Self.json(GatewayEnvelope(ok: true, data: ["id": id, "count": String(count)]))
        }

        // 频道列表：/api/live/channels  （多源排重合并，按 group 排序）
        router.get("api/live/channels") { _, _ async throws -> Response in
            let list = await LiveEngine.shared.channels()
            return Self.json(GatewayEnvelope(ok: true, data: list))
        }

        // 设置直播源自定义 UA：/api/live/setua?id=&ua=  （ua 空 = 恢复默认）
        router.get("api/live/setua") { request, _ async throws -> Response in
            guard let id = Self.queryValue(request, name: "id"), !id.isEmpty else {
                throw HTTPError(.badRequest, message: "missing id")
            }
            let ua = Self.queryValue(request, name: "ua")
            try await LiveEngine.shared.setUserAgent(id: id, userAgent: ua)
            await LiveEngine.shared.invalidateCache()
            return Self.json(GatewayEnvelope(ok: true, data: ["id": id]))
        }

        // 批量连通性测试：/api/live/test?ids=<换行分隔,各编码>&urls=<换行分隔,各编码>
        // 返回 [id: Bool]。并发探测各频道流可达性。
        router.get("api/live/test") { request, _ async throws -> Response in
            let idsRaw = Self.queryValue(request, name: "ids") ?? ""
            let urlsRaw = Self.queryValue(request, name: "urls") ?? ""
            // 换行分隔（id 内含 |，不能用 | 分隔）
            let ids = idsRaw.components(separatedBy: "\n").filter { !$0.isEmpty }
            let urls = urlsRaw.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard ids.count == urls.count, !ids.isEmpty else {
                throw HTTPError(.badRequest, message: "ids/urls 数量需一致且非空")
            }
            var map: [String: String] = [:]
            for (i, id) in ids.enumerated() { map[id] = urls[i] }
            let result = await LiveEngine.shared.testChannels(urls: map)
            return Self.json(GatewayEnvelope(ok: true, data: result))
        }

        // 已持久化的连通性结果：/api/live/reachability（重启后恢复角标）
        router.get("api/live/reachability") { _, _ async throws -> Response in
            let map = await LiveEngine.shared.savedReachability()
            return Self.json(GatewayEnvelope(ok: true, data: map))
        }

        // 直播流代理：/api/live/stream?url= —— 统一 UA（playbackUserAgent，浏览器 UA 实测全源通放）防盗链
        router.get("api/live/stream") { request, _ async throws -> Response in
            guard let url = Self.queryValue(request, name: "url"), !url.isEmpty else {
                throw HTTPError(.badRequest, message: "missing url")
            }
            return try await Self.proxyLiveMedia(request, sourceURL: url)
        }

        // MARK: - 统一媒体服务器（新架构聚合层）
        // 服务器列表+连接状态：/api/servers → {ok, data:[{id,kind,name,online,latencyMs,...}]}
        // 秒回：先返回已缓存的连接状态，同时后台触发全量 probe 刷新（下次请求拿到新状态），
        // 避免媒体中枢首屏被 150 源全量探测卡住。
        router.get("api/servers") { _, _ async throws -> Response in
            Task { _ = await MediaServerRegistry.shared.probeAll() }   // 后台刷新
            let caps = await MediaServerRegistry.shared.cachedCapabilities()
            let servers = await MediaServerRegistry.shared.allServers()
            struct ServerVO: Codable {
                let id, kind, name: String
                let online: Bool, latencyMs: Int
                let canTranscode, canSearch: Bool
            }
            let vos = servers.map { s -> ServerVO in
                let c = caps[s.config.id]
                return ServerVO(id: s.config.id, kind: s.config.kind.rawValue, name: s.config.name,
                                online: c?.online ?? false, latencyMs: c?.latencyMs ?? 0,
                                canTranscode: c?.canTranscode ?? false, canSearch: c?.canSearch ?? true)
            }
            return Self.json(GatewayEnvelope(ok: true, data: vos))
        }

        // 跨服务器聚合搜索：/api/aggregate/search?q=
        router.get("api/aggregate/search") { request, _ async throws -> Response in
            let q = Self.queryValue(request, name: "q") ?? ""
            guard !q.isEmpty else { throw HTTPError(.badRequest, message: "missing q") }
            let items = await MediaServerRegistry.shared.aggregateSearch(query: q, filter: SearchFilter())
            return Self.json(GatewayEnvelope(ok: true, data: items))
        }

        // 聚合首页：/api/aggregate/home?limit= → {continueWatching, recentlyAdded}
        router.get("api/aggregate/home") { request, _ async throws -> Response in
            let limit = Int(Self.queryValue(request, name: "limit") ?? "20") ?? 20
            async let cw = MediaServerRegistry.shared.aggregateContinueWatching(limit: limit)
            async let ra = MediaServerRegistry.shared.aggregateRecentlyAdded(limit: limit)
            struct HomeVO: Codable { let continueWatching, recentlyAdded: [MediaItem] }
            return Self.json(GatewayEnvelope(ok: true, data: HomeVO(continueWatching: await cw, recentlyAdded: await ra)))
        }

        // 本地继续观看：/api/aggregate/progress → [MediaItem]
        router.get("api/aggregate/progress") { _, _ async throws -> Response in
            let items = await ProgressStore.shared.continueWatching(limit: 30)
            return Self.json(GatewayEnvelope(ok: true, data: items))
        }

        // MARK: - 自建服务器管理（M3）
        router.get("api/mediaserver/list") { _, _ async throws -> Response in
            let cfgs = await ServerConfigStore.shared.all()
            return Self.json(GatewayEnvelope(ok: true, data: cfgs))
        }

        router.get("api/mediaserver/add-emby") { request, _ async throws -> Response in
            guard let base = Self.queryValue(request, name: "base"),
                  let user = Self.queryValue(request, name: "user"),
                  let pwd = Self.queryValue(request, name: "pwd") else {
                throw HTTPError(.badRequest, message: "missing base/user/pwd")
            }
            let kindStr = Self.queryValue(request, name: "kind") ?? "emby"
            let isJellyfin = (kindStr == "jellyfin")
            do {
                let cfg = try await EmbyAdapter.authenticate(baseURL: base, username: user, password: pwd, isJellyfin: isJellyfin)
                await ServerConfigStore.shared.add(cfg)
                await MediaServerBootstrap.reassemble()
                return Self.json(GatewayEnvelope(ok: true, data: cfg))
            } catch {
                return Self.json(GatewayEnvelope<MediaServerConfig>(ok: false, error: "认证失败：\(error.localizedDescription)"))
            }
        }

        router.get("api/mediaserver/add") { request, _ async throws -> Response in
            guard let kindStr = Self.queryValue(request, name: "kind"),
                  let kind = MediaServerKind(rawValue: kindStr),
                  let base = Self.queryValue(request, name: "base") else {
                throw HTTPError(.badRequest, message: "missing kind/base")
            }
            let name = Self.queryValue(request, name: "name") ?? kindStr
            var extra: [String: String] = [:]
            if let rp = Self.queryValue(request, name: "rootPath") { extra["rootPath"] = rp }
            if let lid = Self.queryValue(request, name: "libraryId") { extra["libraryId"] = lid }
            let host = URL(string: base)?.host ?? base
            let cfg = MediaServerConfig(
                id: "\(kindStr)|\(host)", kind: kind, name: name, baseURL: base,
                username: Self.queryValue(request, name: "user"),
                password: Self.queryValue(request, name: "pwd"),
                token: Self.queryValue(request, name: "token"),
                extra: extra
            )
            await ServerConfigStore.shared.add(cfg)
            await MediaServerBootstrap.reassemble()
            let cap = await MediaServerRegistry.shared.probe(key: cfg.id)
            struct AddVO: Codable { let config: MediaServerConfig; let online: Bool; let message: String? }
            return Self.json(GatewayEnvelope(ok: true, data: AddVO(config: cfg, online: cap.online, message: cap.message)))
        }

        router.get("api/mediaserver/remove") { request, _ async throws -> Response in
            guard let id = Self.queryValue(request, name: "id") else {
                throw HTTPError(.badRequest, message: "missing id")
            }
            await ServerConfigStore.shared.remove(id: id)
            await MediaServerRegistry.shared.unregister(key: id)
            return Self.json(GatewayEnvelope(ok: true, data: ["removed": id]))
        }

        router.get("api/mediaserver/toggle") { request, _ async throws -> Response in
            guard let id = Self.queryValue(request, name: "id") else {
                throw HTTPError(.badRequest, message: "missing id")
            }
            let on = Self.queryValue(request, name: "on") != "0"
            await ServerConfigStore.shared.setEnabled(id: id, on)
            await MediaServerBootstrap.reassemble()
            return Self.json(GatewayEnvelope(ok: true, data: ["id": id, "enabled": "\(on)"]))
        }

        // 封面回退：/api/cover?title= → {ok, data:{url}}（豆瓣海报，经 image-proxy 代理）
        router.get("api/cover") { request, _ async throws -> Response in
            guard let title = Self.queryValue(request, name: "title"), !title.isEmpty else {
                throw HTTPError(.badRequest, message: "missing title")
            }
            if let poster = await CoverEngine.shared.doubanPoster(forRawTitle: title) {
                let proxied = CoverEngine.proxiedImageURL(poster, gatewayBase: "http://127.0.0.1:8787")
                return Self.json(GatewayEnvelope(ok: true, data: ["url": proxied]))
            }
            return Self.json(GatewayEnvelope(ok: true, data: ["url": ""]))
        }

        // 豆瓣热门（MoonTVPlus 首页形式）：/api/douban/hot?kind=movie|tv&category=&type=&limit=
        router.get("api/douban/hot") { request, _ async throws -> Response in
            let kind = Self.queryValue(request, name: "kind") ?? "movie"
            let category = Self.queryValue(request, name: "category") ?? "热门"
            let type = Self.queryValue(request, name: "type") ?? "全部"
            let limit = Int(Self.queryValue(request, name: "limit") ?? "") ?? 18
            let start = Int(Self.queryValue(request, name: "start") ?? "") ?? 0
            let items = await CoverEngine.shared.doubanHot(kind: kind, category: category, type: type, limit: limit, start: start)
            return Self.json(GatewayEnvelope(ok: true, data: items))
        }

        // 图片代理：/api/image-proxy?url= —— 转发豆瓣等防盗链图片（带 Referer）。
        router.get("api/image-proxy") { request, _ async throws -> Response in
            guard let urlStr = Self.queryValue(request, name: "url"),
                  let url = URL(string: urlStr) else {
                throw HTTPError(.badRequest, message: "bad url")
            }
            var req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            // 豆瓣图片防盗链：Referer 设为豆瓣主站
            if url.host?.contains("doubanio.com") == true {
                req.setValue("https://movie.douban.com/", forHTTPHeaderField: "Referer")
            }
            // 强制直连：豆瓣/采集站图床国内可直连，系统代理境外出口拉图 25s 超时（封面转圈根因）。
            // 用 data() 而非 bytes()：封面图小（KB 级），全量读一次即可；bytes() 流式请求在系统代理下
            // 会被代理栈接管拖慢（实测同 session data() 0.05s / bytes() 25s）。
            let (data, resp) = try await DirectURLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            var headers = HTTPFields()
            headers[.contentType] = http?.value(forHTTPHeaderField: "Content-Type") ?? "image/jpeg"
            headers[.cacheControl] = "public, max-age=86400"
            headers[.contentLength] = "\(data.count)"
            return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(data: data)))
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

    /// 直播流式代理：拉 m3u8/视频流时带直播源约定的 UA（okHttp/Mod-1.5.0.0），
    /// 透传 Range，边收边发（直播无 Content-Length，AVPlayer 按 HLS 消费）。
    private static func proxyLiveMedia(_ request: Request, sourceURL: String) async throws -> Response {
        guard let url = URL(string: sourceURL) else { throw HTTPError(.badRequest, message: "bad url") }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.setValue(LiveEngine.playbackUserAgent, forHTTPHeaderField: "User-Agent")
        let range = request.headers[.range].flatMap { $0.isEmpty ? nil : $0 }
        if let range, !range.isEmpty { req.setValue(range, forHTTPHeaderField: "Range") }
        // 强制直连：直播/采集站 CDN 锁中国大陆 IP，系统代理（VPN）走境外会被区域拦截 403。
        let (bytes, resp) = try await DirectURLSession.shared.bytes(for: req)
        let http = resp as? HTTPURLResponse
        var contentType = http?.value(forHTTPHeaderField: "Content-Type") ?? "application/vnd.apple.mpegurl"
        let statusCode = http?.statusCode ?? 200
        // 分片/流按扩展名补正 MIME：jsdelivr 等 CDN 对 .ts 返回 text/plain，AVPlayer 不识别会拒播
        let lower = sourceURL.lowercased()
        if lower.contains(".ts") || contentType.contains("text/plain") {
            if lower.hasSuffix(".ts") || lower.contains(".ts?") { contentType = "video/mp2t" }
        }
        if lower.hasSuffix(".m3u8") || lower.contains(".m3u8?") { contentType = "application/vnd.apple.mpegurl" }

        // 关键：m3u8 播放列表必须重写——里面的分片/子列表是源站绝对 URL，
        // AVPlayer 会绕过网关直接请求分片，而分片域名对 AVPlayer UA 防盗链 → 播放失败。
        // 检测为 m3u8（按 content-type 或 .m3u8 后缀）时，读取全文并重写所有 URL 行走本网关代理。
        let isM3U8 = contentType.contains("mpegurl") || contentType.contains("m3u")
            || sourceURL.lowercased().contains(".m3u8")
        if isM3U8, statusCode == 200 {
            // m3u8 是文本且体积小（KB 级），全量读出重写
            var textBytes = [UInt8]()
            for try await b in bytes { textBytes.append(b) }
            if let text = String(bytes: textBytes, encoding: .utf8) {
                let rewritten = rewriteM3U8(text, baseURL: url)
                var headers = HTTPFields()
                headers[.contentType] = "application/vnd.apple.mpegurl"
                let buf = ByteBuffer(data: Data(rewritten.utf8))
                return Response(status: .ok, headers: headers, body: .init(byteBuffer: buf))
            }
            // 非文本则按流透传（不重写）
        }

        var headers = HTTPFields()
        headers[.contentType] = contentType
        if let cl = http?.value(forHTTPHeaderField: "Content-Length") { headers[.contentLength] = cl }
        if let cr = http?.value(forHTTPHeaderField: "Content-Range") { headers[.contentRange] = cr }
        headers[.acceptRanges] = "bytes"
        let status: HTTPResponse.Status = (statusCode == 206) ? .partialContent : .ok
        let body = ResponseBody { writer in
            var buffer = [UInt8]()
            buffer.reserveCapacity(65_536)
            for try await byte in bytes {
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

    /// 重写 m3u8：把分片 / 子播放列表 / 密钥的 URL 全部改写成走本网关 /api/live/stream 代理。
    /// 相对 URL 先按 baseURL 解析成绝对，再编码进代理 query。
    private static func rewriteM3U8(_ text: String, baseURL: URL) -> String {
        var out: [String] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.hasPrefix("#") {
                // #EXT-X-KEY / #EXT-X-MAP 等含 URI="..." 的标签行也要重写 URI
                if line.contains("URI=\"") {
                    out.append(rewriteTagURI(line, baseURL: baseURL))
                } else {
                    out.append(line)
                }
            } else if !line.isEmpty {
                // 分片 / 子播放列表地址行
                let absolute = resolveURL(line, base: baseURL)
                out.append(proxyURLString(absolute))
            } else {
                out.append(line)
            }
        }
        return out.joined(separator: "\n")
    }

    /// 重写标签行里的 URI="..."（如 #EXT-X-KEY:METHOD=AES-128,URI="..."）。
    private static func rewriteTagURI(_ line: String, baseURL: URL) -> String {
        guard let uriKeyRange = line.range(of: "URI=\"") else { return line }
        let valueStart = uriKeyRange.upperBound
        guard let closeQuote = line[valueStart...].firstIndex(of: "\"") else { return line }
        let uriValue = String(line[valueStart..<closeQuote])
        let absolute = resolveURL(uriValue, base: baseURL)
        let proxied = proxyURLString(absolute)
        return line.replacingCharacters(in: valueStart..<closeQuote, with: proxied)
    }

    /// 相对地址按 base 解析成绝对；已是 http 开头直接返回。
    private static func resolveURL(_ s: String, base: URL) -> String {
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return s }
        if let resolved = URL(string: s, relativeTo: base)?.absoluteURL {
            return resolved.absoluteString
        }
        return s
    }

    /// 把绝对 URL 编码进本网关直播代理地址（绝对地址，确保 AVPlayer 正确解析）。
    private static func proxyURLString(_ absolute: String) -> String {
        let enc = absolute.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? absolute
        return "http://127.0.0.1:8787/api/live/stream?url=\(enc)"
    }
    public static func run(port: Int) async throws {
        await MediaServerBootstrap.assemble()
        // 先快速标定首屏源（红果/NAS，秒级），保证首页立即有数据；
        // 再后台并发标定全部源（150 TVBox 慢源不阻塞起听），标定后聚合逐步纳入。
        await MediaServerRegistry.shared.probeQuick()
        Task { _ = await MediaServerRegistry.shared.probeAll() }
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
