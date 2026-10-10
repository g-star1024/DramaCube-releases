import Foundation
import AVFoundation
import AppKit

/// NAS 视频首帧封面生成器：AVAssetImageGenerator 抽第 2 秒首帧，磁盘缓存到
/// Application Support/DramaCube/nas-covers/。原生方案独有（Web 跨域无法截首帧）。
///
/// 缓存键 = 视频播放地址的 SHA256 前 16 位（同一文件地址稳定）。
/// 并发限流 2，避免批量生成时 CPU/IO 打满。
public actor NASCoverGenerator {
    public static let shared = NASCoverGenerator()
    private init() {}

    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let limit = 2
    /// 生成失败的黑名单（避免对损坏/无视频轨文件反复尝试）。
    private var failed: Set<String> = []
    /// 正在生成中的 key（防止懒加载重复触发同一视频的并发生成）。
    private var inFlight: Set<String> = []

    private static var cacheDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DramaCube/nas-covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cacheURL(for key: String) -> URL {
        cacheDir.appendingPathComponent("\(key).jpg")
    }

    /// 取封面：命中缓存直接返回本地文件 URL；否则后台生成并缓存，返回文件 URL；失败返回 nil。
    public func cover(forVideoPlayURL playURL: String) async -> URL? {
        let key = Self.key(for: playURL)
        let dest = Self.cacheURL(for: key)
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        if failed.contains(key) { return nil }
        // 已在生成队列中的同一视频不重复排队（懒加载卡片滚回可见区会重复触发）
        if inFlight.contains(key) { return nil }

        await acquire()
        defer { Task { await release() } }
        // 双重检查（等闸门期间可能已被别的任务生成）
        if FileManager.default.fileExists(atPath: dest.path) { return dest }

        inFlight.insert(key)
        defer { inFlight.remove(key) }
        guard let url = Self.videoURL(from: playURL) else { failed.insert(key); return nil }
        let ok = await Self.generateThumbnail(videoURL: url, to: dest)
        if !ok { failed.insert(key); return nil }
        return dest
    }

    /// 同步查缓存（已生成过才返回，不触发网络/解码）。
    public func cachedCover(forVideoPlayURL playURL: String) -> URL? {
        let dest = Self.cacheURL(for: Self.key(for: playURL))
        return FileManager.default.fileExists(atPath: dest.path) ? dest : nil
    }

    // MARK: - 内部

    private static func key(for playURL: String) -> String {
        // 简单稳定 hash（FNV-1a 64bit），避免引入 CryptoKit 也能用
        var hash: UInt64 = 0xcbf29ce484222325
        for b in playURL.utf8 {
            hash ^= UInt64(b)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    /// 播放地址还原成本地/远程视频 URL。file:// 直读，http 走 AVURLAsset（带鉴权的 URL 已含凭据）。
    private static func videoURL(from playURL: String) -> URL? {
        if playURL.hasPrefix("file://") {
            return URL(fileURLWithPath: String(playURL.dropFirst("file://".count)))
        }
        return URL(string: playURL)
    }

    private static func generateThumbnail(videoURL: URL, to dest: URL) async -> Bool {
        let asset = AVURLAsset(url: videoURL)
        // 校验有视频轨
        guard let tracks = try? await asset.load(.tracks),
              tracks.contains(where: { $0.mediaType == .video }) else { return false }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 480)  // 缩略图上限，省内存
        gen.requestedTimeToleranceBefore = .init(seconds: 2, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = .init(seconds: 2, preferredTimescale: 600)
        let time = CMTime(seconds: 2, preferredTimescale: 600)
        do {
            let result = try await gen.image(at: time)
            let cg = result.image
            // 裁剪为 2:3 竖版封面比例（中心裁剪），与卡片占位一致，避免拉伸变形
            guard let cropped = Self.cropToPoster(cg) else { return false }
            let img = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
            guard let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return false }
            try jpg.write(to: dest, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// 中心裁剪为 2:3 竖版封面（宽:高 = 2:3）。竖屏短剧直接取中；横屏视频取中间竖条。
    private static func cropToPoster(_ cg: CGImage) -> CGImage? {
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let targetRatio: CGFloat = 2.0 / 3.0  // 宽/高
        let currentRatio = w / h
        var rect: CGRect
        if currentRatio > targetRatio {
            // 太宽（横屏）：收窄宽度
            let newW = h * targetRatio
            rect = CGRect(x: (w - newW) / 2, y: 0, width: newW, height: h)
        } else {
            // 太高（竖屏超过 2:3）：收短高度
            let newH = w / targetRatio
            rect = CGRect(x: 0, y: (h - newH) / 2, width: w, height: newH)
        }
        return cg.cropping(to: rect.integral)
    }

    // MARK: - 并发闸门
    private func acquire() async {
        if running < limit { running += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if let next = waiters.first { waiters.removeFirst(); next.resume() }
        else { running -= 1 }
    }
}
