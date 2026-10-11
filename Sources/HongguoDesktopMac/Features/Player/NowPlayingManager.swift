import MediaPlayer
import AppKit

/// 系统媒体控制（Now Playing + 遥控命令）。
///
/// 遥控命令通过 Notification 转发给当前播放器（@MainActor 接收），避免在非 Sendable 回调里
/// 直接持有跨 actor 引用。Now Playing 信息在主线程更新。
@MainActor
final class NowPlayingManager {
    static let shared = NowPlayingManager()
    private var bound = false

    func bind(_: ActivePlayer) {
        guard !bound else { return }
        bound = true
        let rc = MPRemoteCommandCenter.shared()
        rc.playCommand.addTarget { _ in NotificationCenter.default.post(name: .hongguoRemotePlay, object: nil); return .success }
        rc.pauseCommand.addTarget { _ in NotificationCenter.default.post(name: .hongguoRemotePause, object: nil); return .success }
        rc.togglePlayPauseCommand.addTarget { _ in NotificationCenter.default.post(name: .hongguoRemoteToggle, object: nil); return .success }
        rc.nextTrackCommand.addTarget { _ in NotificationCenter.default.post(name: .hongguoRemoteNext, object: nil); return .success }
        rc.previousTrackCommand.addTarget { _ in NotificationCenter.default.post(name: .hongguoRemotePrev, object: nil); return .success }
    }

    func unbind(_: ActivePlayer) {
        DispatchQueue.main.async { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
    }

    /// 非隔离清理（供播放器 deinit 调用）。
    nonisolated static func clearNowPlaying() {
        DispatchQueue.main.async { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
    }

    func updatePlayback(title: String, episodeTitle: String, duration: Double, currentTime: Double, isPlaying: Bool) {
        DispatchQueue.main.async {
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyTitle] = title
            info[MPMediaItemPropertyAlbumTitle] = episodeTitle
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
            info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
}

extension Notification.Name {
    static let hongguoRemotePlay = Notification.Name("hongguoRemotePlay")
    static let hongguoRemotePause = Notification.Name("hongguoRemotePause")
    static let hongguoRemoteToggle = Notification.Name("hongguoRemoteToggle")
    static let hongguoRemoteNext = Notification.Name("hongguoRemoteNext")
    static let hongguoRemotePrev = Notification.Name("hongguoRemotePrev")
    /// mpv 链路切源/切换其他季：用新 detail 重建播放窗口（userInfo: detail / startIndex）
    static let hongguoSwitchSource = Notification.Name("hongguoSwitchSource")
}
