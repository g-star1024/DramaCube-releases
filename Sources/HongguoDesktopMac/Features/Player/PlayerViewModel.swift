import Foundation
import AVKit
import SwiftUI
import HongguoCore

/// 把 CDN 直链包成网关代理地址（网关负责剥离 Referer）。
func hongguoGatewayMediaURL(_ cdnURL: String) -> URL {
    let encoded = cdnURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cdnURL
    return URL(string: "\(AppConfig.gatewayBaseURL)/api/play?url=\(encoded)")!
}

/// 当前播放器对外暴露的最小接口（供系统媒体控制 / 老板键调用）。
@MainActor
public protocol ActivePlayer: AnyObject {
    var title: String { get }
    var episodeTitle: String { get }
    var duration: Double { get }
    var currentTime: Double { get }
    var isPlaying: Bool { get }
    func play()
    func pause()
    func togglePlayPause()
    func playNext()
    func playPrevious()
}

/// 播放器状态机 + 业务逻辑。
///
/// 负责：AVPlayer 管理、倍速 / 连播 / 断点续播（按秒持久化）、选集、查找其他季、
/// 以及向系统媒体中心推送 Now Playing 信息。所有 UI 通过 `@Published` 字段订阅。
@MainActor
public final class PlayerViewModel: ObservableObject, ActivePlayer {
    // MARK: 数据
    @Published public private(set) var detail: DramaDetail
    public var episodes: [Episode] { detail.episodes }

    @Published public private(set) var currentIndex: Int
    @Published public var isPlaying = false
    @Published public var isBuffering = false
    @Published public var currentTime: Double = 0
    @Published public var duration: Double = 0
    @Published public var error: String?
    @Published public var rate: Double
    @Published public var volume: Float = 1.0
    @Published public var showEpisodes = false
    @Published public var showOtherSeasons = false
    @Published public var otherSeasons: [Drama] = []
    @Published public var isResuming = false
    /// 视频画面是否为竖版（高 > 宽），窗口自适应用。
    @Published public private(set) var isPortraitVideo = false

    public var dramaId: String { detail.drama.id }
    public var currentEpisode: Episode? { episodes.indices.contains(currentIndex) ? episodes[currentIndex] : nil }

    public var title: String { detail.drama.title }
    public var episodeTitle: String { currentEpisode?.title ?? "" }

    public let player: AVPlayer

    nonisolated(unsafe) private var timeObserverToken: Any?
    nonisolated(unsafe) private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var tracksObserver: NSKeyValueObservation?
    private var pendingSeek: Double?
    private var episodeLoadStart: Date?
    private var lastSaved = Date.distantPast
    nonisolated(unsafe) private var notifObservers: [NSObjectProtocol] = []
    private var wasPlayingBeforeBoss = false

    public init(detail: DramaDetail, startIndex: Int = 0) {
        self.detail = detail
        let idx = detail.episodes.isEmpty ? 0 : min(max(startIndex, 0), detail.episodes.count - 1)
        self.currentIndex = idx
        self.rate = AppSettings.shared.defaultPlaybackRate
        self.player = AVPlayer()
        self.player.volume = 1.0
        AppLog.log(.player, "打开播放器《\(detail.drama.title)》共\(detail.episodes.count)集，从第\(idx + 1)集起播")
        setupPeriodicObserver()
        loadEpisode(idx, autoplay: true)
        NowPlayingManager.shared.bind(self)
        observeRemoteAndBoss()
    }

    deinit {
        if let token = timeObserverToken { player.removeTimeObserver(token) }
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        statusObserver?.invalidate()
        tracksObserver?.invalidate()
        player.pause()
        player.replaceCurrentItem(with: nil)
        for o in notifObservers { NotificationCenter.default.removeObserver(o) }
        NowPlayingManager.clearNowPlaying()
        AppLog.log(.player, "播放器已销毁（资源释放：observer/item/AVPlayer 全部清理）")
    }

    private func observeRemoteAndBoss() {
        let nc = NotificationCenter.default
        notifObservers = [
            nc.addObserver(forName: .hongguoRemotePlay, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.play() } },
            nc.addObserver(forName: .hongguoRemotePause, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.pause() } },
            nc.addObserver(forName: .hongguoRemoteToggle, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.togglePlayPause() } },
            nc.addObserver(forName: .hongguoRemoteNext, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.playNext() } },
            nc.addObserver(forName: .hongguoRemotePrev, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.playPrevious() } },
            nc.addObserver(forName: .hongguoBossKeyHide, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.pauseForBoss() } },
            nc.addObserver(forName: .hongguoBossKeyShow, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resumeFromBoss() } },
        ]
    }

    private func pauseForBoss() {
        wasPlayingBeforeBoss = isPlaying
        if isPlaying { pause() }
    }

    private func resumeFromBoss() {
        if wasPlayingBeforeBoss { play() }
    }

    // MARK: - 集数加载

    public func loadEpisode(_ index: Int, autoplay: Bool = true) {
        guard episodes.indices.contains(index) else { return }
        saveProgress(force: true)
        currentIndex = index
        let ep = episodes[index]
        AppLog.log(.player, "选集 第\(ep.index)集(\(ep.id)) autoplay=\(autoplay)")
        episodeLoadStart = Date()
        let item: AVPlayerItem
        if let url = ep.playURL, !url.isEmpty {
            if url.lowercased().contains(".m3u8") {
                // m3u8（TVBox 源主流）：AVPlayer 原生 HLS 直接播，不走网关。
                // 原因：部分资源 CDN（lz-cdn 等）按 TLS/HTTP2 指纹拦截裸 URLSession
                // （实测 curl 200 而 URLSession 404），网关代理会 404；
                // AVPlayer 走 AppleCoreMedia 栈，是播放器标准指纹，CDN 全部放行。
                item = AVPlayerItem(url: URL(string: url)!)
            } else if url.hasPrefix("file://") {
                // NAS 本机挂载目录：file:// 直读，AVPlayer 原生支持 Range。
                item = AVPlayerItem(url: URL(fileURLWithPath: String(url.dropFirst("file://".count))))
            } else if detail.drama.id.hasPrefix("nas|") {
                // NAS WebDAV 直链：http(s) 原样直连（带 Basic 鉴权的 AVURLAsset 在 DetailView 已拼好凭据到 URL 或无需鉴权）。
                item = AVPlayerItem(url: URL(string: url)!)
            } else {
                // mp4 等直链（红果源）：经网关剥离 Referer + Range 透传。
                item = AVPlayerItem(url: hongguoGatewayMediaURL(url))
            }
        } else {
            // 新站点选集无预置直链：经网关 /api/stream/<sid>/<vid> 即时解析 main_url 并代理。
            let stream = URL(string: "\(AppConfig.gatewayBaseURL)/api/stream/\(detail.drama.id)/\(ep.id)")!
            item = AVPlayerItem(url: stream)
        }
        player.replaceCurrentItem(with: item)
        currentTime = 0
        duration = 0
        isBuffering = true
        error = nil
        isResuming = false

        // 断点续播：读取本集已存进度，待就绪后 seek。
        if let prog = Repository.shared.progress(dramaId: dramaId, episodeId: ep.id) {
            pendingSeek = prog.position
        } else {
            pendingSeek = 0
        }

        observeItemStatus()
        observeTracks(item)
        observeEnd()

        if autoplay {
            player.play()
            isPlaying = true
            player.rate = Float(rate)
        } else {
            isPlaying = false
        }
    }

    private func observeItemStatus() {
        statusObserver?.invalidate()
        guard let item = player.currentItem else { return }
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            guard let self else { return }
            Task { @MainActor in
                if observed.status == .readyToPlay {
                    if let t0 = self.episodeLoadStart {
                        AppLog.log(.player, "第\(self.currentEpisode?.index ?? 0)集就绪，起播耗时 \(Int(Date().timeIntervalSince(t0) * 1000))ms")
                        self.episodeLoadStart = nil
                    }
                    if let seek = self.pendingSeek, seek > 0.5 {
                        self.isResuming = true
                        self.player.seek(to: CMTime(seconds: seek, preferredTimescale: 600)) { _ in
                            Task { @MainActor in self.isResuming = false }
                        }
                    }
                    self.pendingSeek = nil
                    if observed.duration.seconds.isFinite { self.duration = observed.duration.seconds }
                    self.isBuffering = false
                    // 竖版检测统一交给 observeTracks（tracks 就绪后），此处不再调用
                } else if observed.status == .failed {
                    let raw = observed.error?.localizedDescription ?? "该集无法播放"
                    // resource unavailable = 源站/CDN 资源失效或拦截（常见于 TVBox 采集源过期）
                    let msg = raw.localizedCaseInsensitiveContains("resource unavailable")
                        ? "该集资源已失效（源站可能已下线或被拦截），请换源或换集"
                        : raw
                    AppLog.log(.error, "第\(self.currentEpisode?.index ?? 0)集播放失败：\(raw)")
                    self.error = msg
                    self.isBuffering = false
                }
            }
        }
    }

    private func observeEnd() {
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        guard let item = player.currentItem else { return }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.playNext() }
        }
    }

    /// 监听视频轨道异步就绪：HLS/m3u8 的 tracks 在 .readyToPlay 时常未加载完成，
    /// 此时 detectVideoOrientation 会因取不到 track 直接返回（竖版 9:16 收窄失效的根因）。
    /// 改为监听 tracks 变化，就绪后再检测横竖版。
    private func observeTracks(_ item: AVPlayerItem) {
        tracksObserver?.invalidate()
        tracksObserver = item.observe(\.tracks, options: [.initial, .new]) { [weak self] observed, _ in
            guard let self else { return }
            Task { @MainActor in
                if !observed.tracks.isEmpty {
                    self.detectVideoOrientation(observed)
                }
            }
        }
    }

    /// 读取视频轨道 naturalSize（应用 display transform 后），判断竖版并通知窗口自适应。
    /// 竖版短剧（9:16）用横版窗口播放会留两条大黑边 —— 窗口自动收窄到竖屏比例。
    private func detectVideoOrientation(_ item: AVPlayerItem) {
        guard let track = item.tracks.first(where: { $0.assetTrack?.mediaType == .video })?.assetTrack else { return }
        let raw = track.naturalSize.applying(track.preferredTransform)
        let size = CGSize(width: abs(raw.width), height: abs(raw.height))
        guard size.width > 0, size.height > 0 else { return }
        let portrait = size.height > size.width
        if portrait != isPortraitVideo {
            isPortraitVideo = portrait
            AppLog.log(.player, "视频画面 \(Int(size.width))x\(Int(size.height)) → \(portrait ? "竖版，窗口自适应" : "横版")")
            PlayerWindowManager.shared.adaptToVideo(portrait: portrait)
        }
    }

    // MARK: - 控制

    public func play() {
        if player.currentItem == nil { loadEpisode(currentIndex, autoplay: true); return }
        player.play()
        player.rate = Float(rate)
        isPlaying = true
    }

    public func pause() {
        player.pause()
        isPlaying = false
        saveProgress(force: true)
    }

    public func togglePlayPause() { isPlaying ? pause() : play() }

    public func playNext() {
        guard AppSettings.shared.autoPlayNext else { isPlaying = false; return }
        let next = currentIndex + 1
        guard episodes.indices.contains(next) else { isPlaying = false; return }
        loadEpisode(next, autoplay: true)
    }

    public func playPrevious() {
        let prev = currentIndex - 1
        guard episodes.indices.contains(prev) else { seek(to: 0); return }
        loadEpisode(prev, autoplay: true)
    }

    public func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600)) { _ in }
        currentTime = clamped
    }

    public func setRate(_ newRate: Double) {
        rate = newRate
        player.rate = Float(newRate)
        AppSettings.shared.defaultPlaybackRate = newRate
    }

    public func setVolume(_ v: Float) {
        volume = v
        player.volume = v
    }

    // MARK: - 进度持久化（秒级）

    private func currentProgressTuple() -> (episodeId: String, episodeTitle: String, pos: Double, dur: Double)? {
        guard let ep = currentEpisode else { return nil }
        return (ep.id, ep.title, currentTime, duration)
    }

    /// 进度持久化。
    ///
    /// 节流 5 秒（v1.0.5 卡死修复）：周期观察器每 0.5s 触发一次，此前每次都走
    /// SwiftData fetch + save（主线程 SQLite 事务），播放期间持续打断主线程；
    /// UI 的 currentTime 仍然 0.5s 刷新（纯内存赋值，开销可忽略），仅落盘节流。
    public func saveProgress(force: Bool = false) {
        guard let t = currentProgressTuple() else { return }
        // 未开播（尚未拿到时长）不写，避免写垃圾行
        guard t.dur > 0 else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastSaved) < 5.0 { return }
        lastSaved = now
        Repository.shared.saveProgress(
            dramaId: dramaId, episodeId: t.episodeId,
            title: detail.drama.title, episodeTitle: t.episodeTitle,
            coverURL: detail.drama.coverURL,
            position: t.pos, duration: t.dur
        )
    }

    // MARK: - 查找其他季

    public func findOtherSeasons() async {
        otherSeasons = []
        showOtherSeasons = true
        do {
            let results = try await CatalogService.shared.search(query: detail.drama.title)
            let base = normalize(detail.drama.title)
            otherSeasons = results.filter {
                $0.id != dramaId && similarity(base, normalize($0.title)) > 0.3
            }
        } catch {
            otherSeasons = []
        }
    }

    public func switchTo(_ drama: Drama) async {
        do {
            let newDetail = try await CatalogService.shared.detail(id: drama.id)
            detail = newDetail
            showOtherSeasons = false
            loadEpisode(0, autoplay: true)
        } catch {
            self.error = "切换失败：\(error.localizedDescription)"
        }
    }

    private func normalize(_ s: String) -> String {
        s.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s*\d+\s*[季部集话]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^\p{Han}a-z0-9]"#, with: "", options: .regularExpression)
    }

    private func similarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a.contains(b) || b.contains(a) { return 0.8 }
        let setA = Set(a.map { String($0) })
        let setB = Set(b.map { String($0) })
        let inter = setA.intersection(setB).count
        let union = setA.union(setB).count
        return union == 0 ? 0 : Double(inter) / Double(union)
    }

    // MARK: - 周期观察

    private func setupPeriodicObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let sec = time.seconds
                if sec.isFinite {
                    if sec > 0 { self.isBuffering = false }
                    self.currentTime = sec
                }
                self.saveProgress()
                NowPlayingManager.shared.updatePlayback(title: self.title, episodeTitle: self.episodeTitle,
                                                       duration: self.duration, currentTime: self.currentTime, isPlaying: self.isPlaying)
            }
        }
    }
}
