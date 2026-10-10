import Foundation
import HongguoGatewayCore

// MARK: - 播放引擎抽象（M2）
// 统一 mpv / AVPlayer 两种内核，UI 只面对它。默认 mpv，异常可回退 AVPlayer。

/// 引擎类型。
public enum PlaybackEngineKind: String, Codable, Sendable, CaseIterable {
    case mpv        // libmpv（默认）：全格式 / ASS 字幕 / 多音轨 / 倍速 / 硬解 / HDR
    case avplayer   // 系统 AVPlayer（回退）
}

/// 播放引擎统一接口。@MainActor 因为驱动 UI。
@MainActor
public protocol PlaybackEngine: AnyObject, ObservableObject {
    var kind: PlaybackEngineKind { get }

    // 状态
    var isPlaying: Bool { get }
    var isBuffering: Bool { get }
    var currentTime: Double { get }     // 秒
    var duration: Double { get }        // 秒
    var rate: Double { get set }        // 倍速 0.25~4.0
    var volume: Float { get set }       // 0~1
    var error: String? { get }

    // 轨道
    var subtitleTracks: [SubtitleTrack] { get }
    var audioTracks: [AudioTrack] { get }
    var currentSubtitleID: String? { get }
    var currentAudioID: String? { get }

    // 控制
    func load(source: PlaybackSource)
    func play()
    func pause()
    func togglePlayPause()
    func seek(to seconds: Double)
    func seek(by delta: Double)
    func stop()
    func selectSubtitle(id: String?)
    func selectAudio(id: String)
}

/// 引擎工厂：按设置或回退创建。
@MainActor
public enum PlaybackEngineFactory {
    /// 当前应使用的引擎类型（读全局设置，默认 mpv）。
    public static var preferredKind: PlaybackEngineKind {
        get { PlaybackEngineKind(rawValue: UserDefaults.standard.string(forKey: "player.engine") ?? "mpv") ?? .mpv }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "player.engine") }
    }

    /// 创建引擎实例。
    public static func make(kind: PlaybackEngineKind? = nil) -> any PlaybackEngine {
        let k = kind ?? preferredKind
        switch k {
        case .mpv:
            return MpvEngine()
        case .avplayer:
            return AVPlayerEngine()
        }
    }
}
