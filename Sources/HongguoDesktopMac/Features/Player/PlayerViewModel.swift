import Foundation
import AVKit
import SwiftUI
import HongguoCore

/// 把 CDN 直链包成网关代理地址（网关负责剥离 Referer）。
func hongguoGatewayMediaURL(_ cdnURL: String) -> URL {
    let encoded = cdnURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cdnURL
    return URL(string: "\(AppConfig.gatewayBaseURL)/api/play?url=\(encoded)")!
}

/// 把 m3u8 直链包成网关直播代理地址（强制直连绕系统代理 + 浏览器 UA + 重写分片走本网关）。
/// 采集站 CDN 锁中国大陆 IP，AVPlayer 直连走系统代理（VPN 境外出口）会被区域拦截 403。
func hongguoGatewayM3U8URL(_ m3u8URL: String) -> URL {
    let encoded = m3u8URL.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? m3u8URL
    return URL(string: "\(AppConfig.gatewayBaseURL)/api/live/stream?url=\(encoded)")!
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
                // m3u8（TVBox/采集站主流）：经网关 /api/live/stream 代理。
                // 关键原因（v1.2.2 修复）：采集站 CDN 锁中国大陆 IP，AVPlayer 直连走系统代理
                // （VPN 境外出口）会被区域拦截 403「请使用国内网络访问」；且分片域名对
                // AVPlayer 的 AppleCoreMedia UA 防盗链。网关代理强制直连（绕系统代理）+
                // 浏览器 UA 拉流 + 重写 m3u8 把分片/子列表也走本网关，三重保障可播。
                item = AVPlayerItem(url: hongguoGatewayM3U8URL(url))
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
                    // 红果源第 4 集起不可播（IAA 仅前 3 集免费）：自动从内置采集源找同名剧切换全集
                    if raw.localizedCaseInsensitiveContains("resource unavailable"),
                       !self.detail.drama.id.hasPrefix("tvbox|"), !self.detail.drama.id.hasPrefix("nas|"),
                       !self.detail.drama.id.hasPrefix("live|") {
                        Task { await self.tryFallbackToCollectionSource() }
                        return
                    }
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

    // MARK: - 手动切换视频源（播放中换源续播）

    /// 候选源列表（跨 TVBox 源搜同名剧，用于「切换源」面板展示）。
    @Published public var sourceCandidates: [SourceMatch] = []
    @Published public var isSearchingSources = false
    @Published public var showSourceSwitcher = false

    /// 打开切源面板：跨 TVBox 源搜同名剧（红果内容源已清除，只在 TVBox 里找）。
    public func openSourceSwitcher() async {
        showSourceSwitcher = true
        isSearchingSources = true
        sourceCandidates = []
        defer { isSearchingSources = false }
        let keyword = title
        let sites = SourceManager.shared.enabledSites
        await withTaskGroup(of: [SourceMatch].self) { group in
            var pending = sites.makeIterator()
            for _ in 0..<5 {
                if let s = pending.next() {
                    group.addTask {
                        let list = (try? await SourceManager.shared.tvboxSearch(siteKey: s.key, query: keyword)) ?? []
                        return list.map { SourceMatch(drama: $0, siteKey: s.key, siteName: s.name) }
                    }
                }
            }
            while let chunk = await group.next() {
                sourceCandidates.append(contentsOf: chunk)
                if let s = pending.next() {
                    group.addTask {
                        let list = (try? await SourceManager.shared.tvboxSearch(siteKey: s.key, query: keyword)) ?? []
                        return list.map { SourceMatch(drama: $0, siteKey: s.key, siteName: s.name) }
                    }
                }
            }
        }
        // 标题精确优先、集数多优先
        let q = title
        sourceCandidates.sort { a, b in
            let ea = a.drama.title == q, eb = b.drama.title == q
            if ea != eb { return ea }
            return (a.drama.episodeCount ?? 0) > (b.drama.episodeCount ?? 0)
        }
    }

    /// 切到指定源：加载该源详情，从当前集续播。
    public func switchToSource(_ match: SourceMatch) async {
        let targetEp = currentIndex
        showSourceSwitcher = false
        isBuffering = true; error = nil
        do {
            let parts = match.drama.id.split(separator: "|").map(String.init)
            guard parts.count == 3 else { throw HongguoParseError.fieldMissing("tvbox id") }
            let newDetail = try await SourceManager.shared.tvboxDetail(siteKey: parts[1], vodId: parts[2])
            guard !newDetail.episodes.isEmpty else {
                self.error = "「\(match.siteName)」该剧暂无分集资源"
                self.isBuffering = false
                return
            }
            detail = newDetail
            let idx = min(targetEp, newDetail.episodes.count - 1)
            AppLog.log(.player, "手动切源 → \(match.siteName)《\(newDetail.drama.title)》续播第\(idx + 1)集")
            loadEpisode(idx, autoplay: true)
        } catch {
            self.error = "切源失败：\(error.localizedDescription)"
            self.isBuffering = false
        }
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

    // MARK: - 红果 → 采集源回退（IAA 前 3 集限制兜底）

    /// 红果源某集不可播时：从内置采集源搜同名剧，找到则切换到采集源全集继续播当前集。
    /// 这是「红果仅前 3 集免费、采集站爬 App 端有全集」的打通：让用户无感续播而非报错。
    private var isFallingBack = false
    private func tryFallbackToCollectionSource() async {
        guard !isFallingBack else { return }
        isFallingBack = true
        defer { isFallingBack = false }
        isBuffering = true
        error = nil
        let targetEpIndex = currentIndex  // 记住当前想看的集
        let keyword = title
        AppLog.log(.player, "红果《\(keyword)》第\(targetEpIndex + 1)集不可播，尝试从采集源找全集…")

        // 在采集源里搜同名剧（限前 3 个可用源，避免太慢）
        let sites = SourceManager.shared.enabledSites
        var matched: DramaDetail?
        for site in sites.prefix(3) {
            guard let results = try? await SourceManager.shared.tvboxSearch(siteKey: site.key, query: keyword) else { continue }
            // 按标题相似度找最佳匹配
            let best = results
                .map { ($0, similarity(normalize($0.title), normalize(keyword))) }
                .filter { $0.1 >= 0.5 }
                .max { $0.1 < $1.1 }
            guard let (drama, _) = best else { continue }
            // 取详情（含全集 vod_play_url）
            let vodId = drama.id.components(separatedBy: "|").last ?? drama.id
            if let det = try? await SourceManager.shared.tvboxDetail(siteKey: site.key, vodId: vodId),
               !det.episodes.isEmpty, det.episodes.count > targetEpIndex {
                matched = det
                AppLog.log(.player, "采集源命中：《\(det.drama.title)》\(det.episodes.count) 集（源 \(site.name)）")
                break
            }
        }

        guard let det = matched else {
            AppLog.log(.error, "采集源未找到《\(keyword)》全集，保持报错")
            self.error = "该集暂无播放资源：红果仅前 3 集免费，采集源也未收录本剧全集。可换一集或稍后再试"
            self.isBuffering = false
            return
        }

        // 切换到采集源详情继续播当前集（episode id 换成采集源的 index 字符串）
        self.detail = det
        self.currentIndex = targetEpIndex
        AppLog.log(.player, "已切换采集源《\(det.drama.title)》续播第\(targetEpIndex + 1)集")
        loadEpisode(targetEpIndex, autoplay: true)
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
                if u.hasPrefix("file://") || detail.drama.id.hasPrefix("nas|") {
                    url = URL(string: u)
                } else if u.lowercased().contains(".m3u8") {
                    url = hongguoGatewayM3U8URL(u)
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
            if url.lowercased().contains(".m3u8") { return hongguoGatewayM3U8URL(url) }
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
            if u.hasPrefix("file://") || detail.drama.id.hasPrefix("nas|") {
                url = URL(string: u)
            } else if u.lowercased().contains(".m3u8") {
                url = hongguoGatewayM3U8URL(u)
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

    /// 静态：若设置了默认外部播放器，直接用其打开指定集并返回 true（不创建内置播放器窗口）。
    /// 供打开播放器的入口在创建窗口前调用，实现「直接跳外部播放器、不起播内置」。
    @MainActor
    public static func openInDefaultExternalPlayerIfSet(detail: DramaDetail, index: Int) -> Bool {
        let pref = AppSettings.shared.defaultExternalPlayer
        guard pref != "builtin",
              let app = ExternalPlayerApp(rawValue: pref),
              ExternalPlayerOpener.isInstalled(app),
              detail.episodes.indices.contains(index) else { return false }
        let ep = detail.episodes[index]
        var url: URL?
        if let u = ep.playURL, !u.isEmpty {
            if u.hasPrefix("file://") || detail.drama.id.hasPrefix("nas|") {
                url = URL(string: u)
            } else if u.lowercased().contains(".m3u8") {
                url = hongguoGatewayM3U8URL(u)
            } else {
                url = hongguoGatewayMediaURL(u)
            }
        } else {
            url = URL(string: "\(AppConfig.gatewayBaseURL)/api/stream/\(detail.drama.id)/\(ep.id)")
        }
        guard let playURL = url else { return false }
        ExternalPlayerOpener.open(url: playURL, app: app)
        AppLog.log(.player, "已直接用默认外部播放器 \(app.displayName) 打开第\(ep.index)集（未起内置播放器）")
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
