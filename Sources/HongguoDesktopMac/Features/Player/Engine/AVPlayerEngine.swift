import Foundation
import AVKit
@preconcurrency import AVFoundation
import HongguoGatewayCore

// MARK: - AVPlayer 回退引擎
// 当 libmpv 异常或用户手动切换时使用。复用系统 AVPlayer，能力有限但稳定。

@MainActor
public final class AVPlayerEngine: NSObject, PlaybackEngine, ObservableObject {
    public let kind: PlaybackEngineKind = .avplayer

    @Published public private(set) var isPlaying = false
    @Published public private(set) var isBuffering = false
    @Published public private(set) var currentTime: Double = 0
    @Published public private(set) var duration: Double = 0
    @Published public var rate: Double = 1.0 { didSet { player?.rate = Float(rate) } }
    @Published public var volume: Float = 1.0 { didSet { player?.volume = volume } }
    @Published public private(set) var error: String?
    @Published public private(set) var subtitleTracks: [SubtitleTrack] = []
    @Published public private(set) var audioTracks: [AudioTrack] = []
    @Published public private(set) var currentSubtitleID: String?
    @Published public private(set) var currentAudioID: String?

    public private(set) var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?

    public override init() { super.init() }

    // 周期观察者由 player 释放时一并失效；不在 deinit 跨域访问非 Sendable 成员。

    public func load(source: PlaybackSource) {
        error = nil
        let item = AVPlayerItem(url: source.url)
        let p = AVPlayer(playerItem: item)
        p.rate = Float(rate)
        p.volume = volume
        player = p

        if let start = source.startPosition, start > 0 {
            p.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        }

        // 周期时间观察
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = t.seconds
                self.duration = p.currentItem?.duration.seconds ?? 0
            }
        }
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            Task { @MainActor in
                if it.status == .failed { self?.error = it.error?.localizedDescription ?? "播放失败" }
            }
        }
        loadTracks(item: item)
    }

    private func loadTracks(item: AVPlayerItem) {
        Task { @MainActor in
            var subs: [SubtitleTrack] = []
            var auds: [AudioTrack] = []
            if let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
                for (i, opt) in group.options.enumerated() {
                    subs.append(SubtitleTrack(id: "\(i)", title: opt.displayName,
                                              language: opt.extendedLanguageTag, isEmbedded: true))
                }
            }
            if let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) {
                for (i, opt) in group.options.enumerated() {
                    auds.append(AudioTrack(id: "\(i)", title: opt.displayName,
                                           language: opt.extendedLanguageTag))
                }
            }
            self.subtitleTracks = subs
            self.audioTracks = auds
        }
    }

    public func play() { isPlaying = true; player?.play() }
    public func pause() { isPlaying = false; player?.pause() }
    public func togglePlayPause() { isPlaying ? pause() : play() }
    public func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }
    public func seek(by delta: Double) { seek(to: currentTime + delta) }
    public func stop() { player?.pause(); player?.seek(to: .zero) }

    public func selectSubtitle(id: String?) {
        currentSubtitleID = id
        // AVPlayer 字幕选择通过 mediaSelectionGroup（简化：这里只记录）
    }
    public func selectAudio(id: String) {
        currentAudioID = id
    }
}
