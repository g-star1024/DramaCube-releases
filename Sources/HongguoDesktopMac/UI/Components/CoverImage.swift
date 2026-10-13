import SwiftUI
import AppKit
import ImageIO
import HongguoCore

/// 全局封面下载闸门：限制并发请求数，避免开局几十张封面同时请求
/// 打爆网络与主线程（App 卡死的根因之一）。
actor CoverGate {
    static let shared = CoverGate()
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// 并发上限 12：v1.0.5 限 5 防卡死，但 TVBox 首页 12-40 张封面按 5 并发串行，
    /// 每张 0.8-2.4s（CDN 边缘节点延迟方差实测）→ 全页封面要十几秒才出完；
    /// Flutter 版无限制并行秒开。12 并发配合 DirectURLSession 每主机 16 连接上限。
    private let limit = 12

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume() // 名额直接移交下一个等待者
        } else {
            running -= 1
        }
    }
}

/// 封面图组件：并发限流 + URLCache 磁盘缓存 + 失败占位。
///
/// 性能关键（v1.0.5 卡死修复）：
///  - 缓存查询、网络下载、位图解码**全部在后台线程**执行——
///    此前 `load()` 因 View 协议 @MainActor 推断跑在主线程，
///    URLCache 磁盘 I/O + 全分辨率解码串行阻塞主线程，是滚动/加载时卡死的元凶；
///  - 解码用 ImageIO 下采样（上限 640px）：海报展示宽度 ~200pt(2x=400px)，
///    全尺寸位图每张数 MB，几十张即可拖垮内存。
public struct CoverImage: View {
    let url: URL?
    /// 失败/加载占位上显示的标题（取首字作头像式占位，更美观）。
    let title: String?

    @State private var image: NSImage?
    @State private var failed = false

    public init(_ url: URL?, title: String? = nil) {
        self.url = url
        self.title = title
    }

    public var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                failureView
            } else {
                loadingView
            }
        }
        .task(id: url) { await load() }
    }

    private var loadingView: some View {
        placeholderView(showSpinner: true)
    }

    private var failureView: some View {
        placeholderView(showSpinner: false)
    }

    /// 占位：暖沙底 + 居中品牌色播放图标（NAS 占位同款，比色块+首字更干净）。
    private func placeholderView(showSpinner: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(LinearGradient(colors: [Brand.placeholder, Brand.secondaryBackground],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Brand.accent.opacity(0.5))
            if showSpinner {
                ProgressView().controlSize(.small)
                    .tint(Brand.accent.opacity(0.7))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 8)
            }
        }
    }

    /// 主线程只做状态赋值，重活全在 `fetchAndDecode`（nonisolated，后台执行）。
    private func load() async {
        failed = false
        image = nil
        // 无源封面：直接走豆瓣回退
        guard let url else {
            AppLog.net("封面无 URL title=\(title ?? "-")，走豆瓣回退")
            await loadDoubanFallback()
            return
        }
        let img = await Self.fetchAndDecode(url).image
        // task 可能已因 url 变化被取消，取消后不再写状态
        guard !Task.isCancelled else { return }
        if let img {
            image = img
        } else {
            AppLog.net("封面直连失败 url=\(url.host ?? "?") title=\(title ?? "-")，走豆瓣回退")
            // 源封面加载失败：尝试豆瓣回退
            await loadDoubanFallback()
        }
    }

    /// 豆瓣封面回退：按标题查网关 /api/cover，取豆瓣海报（经 image-proxy 防盗链）。
    private func loadDoubanFallback() async {
        guard let title, !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            AppLog.net("封面无标题，放弃豆瓣回退")
            failed = true
            return
        }
        guard let fallback = await Self.fetchDoubanCoverURL(title: title) else {
            AppLog.net("豆瓣回退无封面 title=\(title)")
            guard !Task.isCancelled else { return }
            failed = true
            return
        }
        AppLog.net("豆瓣回退命中 title=\(title) url=\(fallback.host ?? "?")")
        let img = await Self.fetchAndDecode(fallback).image
        guard !Task.isCancelled else { return }
        if let img {
            image = img
        } else {
            AppLog.net("豆瓣回退封面解码失败 title=\(title)")
            failed = true
        }
    }

    /// 调网关封面回退接口，拿豆瓣海报代理地址（带 8s 超时，防止一直转圈）。
    nonisolated private static func fetchDoubanCoverURL(title: String) async -> URL? {
        struct CoverResp: Codable { let ok: Bool; let data: [String: String]? }
        guard let q = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(AppConfig.gatewayBaseURL)/api/cover?title=\(q)") else {
            AppLog.net("豆瓣回退 URL 构造失败 title=\(title)")
            return nil
        }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.cachePolicy = .returnCacheDataElseLoad
        guard let (data, httpResp) = try? await URLSession.shared.data(for: req) else {
            AppLog.net("豆瓣回退请求失败 title=\(title)（网关未就绪或网络错误）")
            return nil
        }
        guard let http = httpResp as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (httpResp as? HTTPURLResponse)?.statusCode ?? -1
            AppLog.net("豆瓣回退非 200 title=\(title) code=\(code)")
            return nil
        }
        guard let resp = try? JSONDecoder().decode(CoverResp.self, from: data),
              resp.ok, let u = resp.data?["url"], !u.isEmpty else {
            AppLog.net("豆瓣回退解析失败 title=\(title)（豆瓣无此片或无海报）")
            return nil
        }
        return URL(string: u)
    }

    /// NSImage 非 Sendable，用只读盒子跨隔离域传递（内容构造后不再变更，安全）。
    private struct DecodedImage: @unchecked Sendable {
        let image: NSImage?
    }

    /// 封面专用 session：**强制直连**（清空代理），不跟随系统代理。
    ///
    /// 实测根因（v2.3.3 回正 v2.3.2 的误改）：视频源封面直接命中采集站图床
    /// （如 p.bfvp26.com，不走网关代理）。实测该图床**直连 0.99s 秒回、走系统
    /// 代理 15s 超时**——v2.3.2 误把封面 session 改回系统代理后，视频源封面
    /// 全部超时回占位（「数据恢复后封面仍不加载」）。Flutter 版无强制代理概念
    /// 即默认直连，故出图正常。采集站图床锁大陆 IP，境外代理出口必被拖死/403，
    /// 必须强制直连（与 v2.3.1 行为一致）。
    nonisolated private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        // 强制直连：清空代理（采集站 CDN 锁大陆 IP，系统代理境外出口拉图超时）。
        cfg.connectionProxyDictionary = [:]
        // 封面并发 12 时同步放宽每主机连接上限（默认 6 会级联排队）。
        cfg.httpMaximumConnectionsPerHost = 16
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        return URLSession(configuration: cfg)
    }()

    /// 后台执行：URLCache 查询 → 过闸门下载（失败重试一次）→ ImageIO 下采样解码。
    nonisolated private static func fetchAndDecode(_ url: URL) async -> DecodedImage {
        var req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        // 浏览器特征头：采集站图床对无头请求限速/403（实测同源 CDN 无头 7.3s vs Safari 头 0.8s）。
        for (k, v) in headers(for: url) { req.setValue(v, forHTTPHeaderField: k) }
        // 1) 命中磁盘/内存缓存直接出图（不占并发名额）
        if let cached = URLCache.shared.cachedResponse(for: req),
           let img = decodeDownsampled(cached.data) {
            return DecodedImage(image: img)
        }
        // 2) 过闸门再联网（最多 12 并发）；任务已取消则不占名额
        if Task.isCancelled { return DecodedImage(image: nil) }
        await CoverGate.shared.acquire()
        defer { Task { await CoverGate.shared.release() } }
        // 失败重试一次（边缘节点偶发慢/丢包，重试常换到更快节点）。
        var lastError: String?
        var lastCode: Int?
        for attempt in 0...1 {
            do {
                let (data, resp) = try await session.data(for: req)
                if let http = resp as? HTTPURLResponse {
                    lastCode = http.statusCode
                    if http.statusCode == 200 {
                        URLCache.shared.storeCachedResponse(CachedURLResponse(response: http, data: data), for: req)
                        if let img = decodeDownsampled(data) {
                            return DecodedImage(image: img)
                        } else {
                            lastError = "解码失败 data=\(data.count)B"
                        }
                    } else {
                        lastError = "HTTP \(http.statusCode)"
                    }
                } else {
                    lastError = "非 HTTP 响应"
                }
            } catch {
                lastError = error.localizedDescription
            }
            // 非末次继续重试
            if attempt == 0 { continue }
        }
        // 两次都失败：埋日志（含 URL host、状态码/错误、尝试次数）
        AppLog.net("封面下载失败 host=\(url.host ?? "?") code=\(lastCode ?? -1) err=\(lastError ?? "?")")
        return DecodedImage(image: nil)
    }

    /// 浏览器特征请求头：Safari UA + 按 host 推断的 Referer。
    /// 豆瓣图床校验 Referer 防盗链（对齐 Flutter 版 cover_image 的 m.douban.com Referer）；
    /// 其余图床用图片 host 自 Referer，满足常规防盗链校验。
    nonisolated private static func headers(for url: URL) -> [String: String] {
        let host = url.host ?? ""
        let referer = host.contains("douban") ? "https://m.douban.com/" : "https://\(host)/"
        return [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            "Referer": referer,
        ]
    }

    /// ImageIO 下采样解码：按 640px 上限生成缩略位图，内存占用降一个数量级。
    /// 解码失败的兜底走 NSImage(data:)（图较小或非标准格式时仍可显示）。
    nonisolated private static func decodeDownsampled(_ data: Data) -> NSImage? {
        guard !data.isEmpty else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
        ]
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            return NSImage(data: data)
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
