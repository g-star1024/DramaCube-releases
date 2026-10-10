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

        await acquire()
        defer { Task { await release() } }
        // 双重检查（等闸门期间可能已被别的任务生成）
        if FileManager.default.fileExists(atPath: dest.path) { return dest }

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
            let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            guard let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return false }
            try jpg.write(to: dest, options: .atomic)
            return true
        } catch {
            return false
        }
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
