import SwiftUI
import AppKit

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
/// 替代裸 AsyncImage（无并发控制、无重试、失败即灰）。
public struct CoverImage: View {
    let url: URL?

    @State private var image: NSImage?
    @State private var failed = false

    public init(_ url: URL?) {
        self.url = url
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
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(LinearGradient(colors: [Brand.placeholder, Brand.secondaryBackground],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            ProgressView().controlSize(.small)
        }
    }

    private var failureView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(LinearGradient(colors: [Brand.placeholder, Brand.secondaryBackground],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "film")
                .font(.system(size: 24))
                .foregroundStyle(Brand.separator)
        }
    }

    private func load() async {
        failed = false
        image = nil
        guard let url else { failed = true; return }
        let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        // 1) 命中磁盘/内存缓存直接出图（不占并发名额）
        if let cached = URLCache.shared.cachedResponse(for: req),
           let img = Self.decode(cached.data) {
            image = img
            return
        }
        // 2) 过闸门再联网（最多 5 并发）
        await CoverGate.shared.acquire()
        defer { Task { await CoverGate.shared.release() } }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                URLCache.shared.storeCachedResponse(CachedURLResponse(response: http, data: data), for: req)
            }
            guard let img = Self.decode(data) else {
                failed = true
                return
            }
            image = img
        } catch {
            failed = true
        }
    }

    /// 位图解码放后台线程，避免批量封面解码阻塞主线程。
    nonisolated private static func decode(_ data: Data) -> NSImage? {
        guard !data.isEmpty else { return nil }
        return NSImage(data: data)
    }
}
