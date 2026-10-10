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
    /// 下集预缓冲：本集是否已触发过预热（每集只预热一次）。
    private var prefetchedNext = false
    /// 预热的下一集资源（保留引用防释放，切换时可直接用）。
    private var prefetchedAsset: AVURLAsset?

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
        // 全局默认外部播放器：选集播放时自动用外部播放器打开，无需每次手动切换
        if maybeOpenInDefaultExternalPlayer(index: index) { return }
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
        // 应用缓冲策略：preferredForwardBufferDuration（参考 MoonTVPlus maxBufferLength 15/30/60/120s）
        let bufferSecs = AppSettings.shared.forwardBufferSeconds
        item.preferredForwardBufferDuration = bufferSecs

        player.replaceCurrentItem(with: item)
        currentTime = 0
        duration = 0
        isBuffering = true
        error = nil
        isResuming = false
        prefetchedNext = false

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
                    let msg: String
                    if raw.localizedCaseInsensitiveContains("resource unavailable") {
                        msg = "该集暂无播放资源：可能是源站尚未上线本集，或已被下线/拦截。可换一集（部分剧仅前几集可看），或到「视频源」换源观看"
                    } else if raw.contains("-1013") {
                        msg = "资源库鉴权失败：请检查设置中 NAS 的账号密码是否正确"
                    } else if raw.contains("-1012") || raw.contains("-1003") || raw.contains("-1001") {
                        msg = "无法连接资源库：请确认 NAS 在线且网络可达"
                    } else {
                        msg = raw
                    }
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

    /// 下载当前集（用可分享地址，经网关代理可直接访问）。
    public func downloadCurrentEpisode() {
        guard let ep = currentEpisode, let url = shareablePlayURL else { return }
        DownloadManager.shared.addDownload(
            dramaId: dramaId, episodeId: ep.id,
            dramaTitle: title, episodeTitle: ep.title,
            sourceURL: url.absoluteString
        )
    }

    /// 批量下载指定下标的集（选集面板勾选多集批量缓存）。
    /// 逐集构造可分享地址交给 DownloadManager 排队（并发由下载管理器限流）。
    public func downloadEpisodes(indices: [Int]) {
        for index in indices where episodes.indices.contains(index) {
            let ep = episodes[index]
            var url: URL?
            if let u = ep.playURL, !u.isEmpty {
                if u.hasPrefix("file://") || u.lowercased().contains(".m3u8") || detail.drama.id.hasPrefix("nas|") {
                    url = URL(string: u)
                } else {
                    url = hongguoGatewayMediaURL(u)
                }
            } else {
                url = URL(string: "\(AppConfig.gatewayBaseURL)/api/stream/\(detail.drama.id)/\(ep.id)")
            }
            guard let playURL = url else { continue }
            DownloadManager.shared.addDownload(
                dramaId: dramaId, episodeId: ep.id,
                dramaTitle: title, episodeTitle: ep.title,
                sourceURL: playURL.absoluteString
            )
        }
        AppLog.log(.app, "批量缓存：已加入 \(indices.count) 集到下载队列")
    }

    /// 当前集下载状态（供按钮显示）。
    public var currentDownloadState: DownloadState? {
        guard let ep = currentEpisode else { return nil }
        return DownloadManager.shared.status(for: dramaId, episodeId: ep.id)
    }

    // MARK: - 外部播放器打开

    /// 当前集的可播放地址（经网关代理，外部播放器可直接访问，无需 Referer）。
    /// 返回 nil 表示当前集无可分享地址。
    public var shareablePlayURL: URL? {
        guard let ep = currentEpisode else { return nil }
        if let url = ep.playURL, !url.isEmpty {
            if url.hasPrefix("file://") { return URL(string: url) }
            if url.lowercased().contains(".m3u8") { return URL(string: url) }
            if detail.drama.id.hasPrefix("nas|") { return URL(string: url) }
            return hongguoGatewayMediaURL(url)
        }
        // 新站点：经网关 stream 代理
        return URL(string: "\(AppConfig.gatewayBaseURL)/api/stream/\(detail.drama.id)/\(ep.id)")
    }

    /// 用系统已安装的外部播放器打开当前集（IINA / VLC / 默认）。
    public func openInExternalPlayer(_ app: ExternalPlayerApp) {
        guard let url = shareablePlayURL else { return }
        ExternalPlayerOpener.open(url: url, app: app)
    }

    /// 若设置中心配置了默认外部播放器，选集播放时自动用其打开该集（返回 true 表示已接管，不再走内置播放器）。
    private func maybeOpenInDefaultExternalPlayer(index: Int) -> Bool {
        let pref = AppSettings.shared.defaultExternalPlayer
        guard pref != "builtin",
              let app = ExternalPlayerApp(rawValue: pref),
              ExternalPlayerOpener.isInstalled(app) else { return false }
        // 构造该集的可分享地址（与 shareablePlayURL 同逻辑，但针对任意 index）
        guard episodes.indices.contains(index) else { return false }
        let ep = episodes[index]
        var url: URL?
        if let u = ep.playURL, !u.isEmpty {
            if u.hasPrefix("file://") || u.lowercased().contains(".m3u8") || detail.drama.id.hasPrefix("nas|") {
                url = URL(string: u)
            } else {
                url = hongguoGatewayMediaURL(u)
            }
        } else {
            url = URL(string: "\(AppConfig.gatewayBaseURL)/api/stream/\(detail.drama.id)/\(ep.id)")
        }
        guard let playURL = url else { return false }
        currentIndex = index
        ExternalPlayerOpener.open(url: playURL, app: app)
        AppLog.log(.player, "第\(ep.index)集已用默认外部播放器 \(app.displayName) 打开")
        return true
    }

    // MARK: - 下集预缓冲

    /// 播放进度达 90% 时预热下一集资源（预创建 AVURLAsset 并异步加载关键属性，
    /// 让 CDN 连接/TLS 握手/码率协商提前完成，切下集时秒开）。
    private func maybePrefetchNext(currentSeconds: Double) {
        guard AppSettings.shared.prefetchNextEpisode, !prefetchedNext else { return }
        guard duration > 0, currentSeconds / duration >= 0.9 else { return }
        let next = currentIndex + 1
        guard episodes.indices.contains(next) else { return }
        prefetchedNext = true
        let ep = episodes[next]
        guard let urlString = ep.playURL, !urlString.isEmpty,
              let url = URL(string: urlString) else { return }
        let asset = AVURLAsset(url: url)
        prefetchedAsset = asset
        Task.detached(priority: .utility) {
            // 异步预加载关键属性，触发网络预热（连接 + 首个分片）。
            _ = try? await asset.load(.duration, .tracks)
            AppLog.log(.player, "下集预缓冲完成：第\(ep.index)集")
        }
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
                self.maybePrefetchNext(currentSeconds: self.currentTime)
                NowPlayingManager.shared.updatePlayback(title: self.title, episodeTitle: self.episodeTitle,
                                                       duration: self.duration, currentTime: self.currentTime, isPlaying: self.isPlaying)
            }
        }
    }
}
