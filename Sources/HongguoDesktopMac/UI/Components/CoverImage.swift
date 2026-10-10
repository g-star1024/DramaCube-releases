import SwiftUI
import AppKit
import ImageIO

/// 全局封面下载闸门：限制并发请求数，避免开局几十张封面同时请求
/// 打爆网络与主线程（App 卡死的根因之一）。
actor CoverGate {
    static let shared = CoverGate()
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let limit = 5

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
        guard let url else { failed = true; return }
        let img = await Self.fetchAndDecode(url).image
        // task 可能已因 url 变化被取消，取消后不再写状态
        guard !Task.isCancelled else { return }
        if let img {
            image = img
        } else {
            failed = true
        }
    }

    /// NSImage 非 Sendable，用只读盒子跨隔离域传递（内容构造后不再变更，安全）。
    private struct DecodedImage: @unchecked Sendable {
        let image: NSImage?
    }

    /// 后台执行：URLCache 查询 → 过闸门下载 → ImageIO 下采样解码。
    nonisolated private static func fetchAndDecode(_ url: URL) async -> DecodedImage {
        let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        // 1) 命中磁盘/内存缓存直接出图（不占并发名额）
        if let cached = URLCache.shared.cachedResponse(for: req),
           let img = decodeDownsampled(cached.data) {
            return DecodedImage(image: img)
        }
        // 2) 过闸门再联网（最多 5 并发）
        await CoverGate.shared.acquire()
        defer { Task { await CoverGate.shared.release() } }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                URLCache.shared.storeCachedResponse(CachedURLResponse(response: http, data: data), for: req)
            }
            return DecodedImage(image: decodeDownsampled(data))
        } catch {
            return DecodedImage(image: nil)
        }
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
