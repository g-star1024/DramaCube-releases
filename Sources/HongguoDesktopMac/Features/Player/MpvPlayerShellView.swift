import SwiftUI
import HongguoCore
import HongguoGatewayCore

/// mpv 内核播放壳（M2 接线）：独立窗口内复用 MpvEngine，
/// 自带选集条 / 自动连播 / 断点续播 / 进度保存 / 弹幕层 / 竖版自适应，
/// 功能对齐 AVPlayer 链路的 PlayerView，供「播放内核 = mpv」时启用。
struct MpvPlayerShellView: View {
    let detail: DramaDetail
    let startIndex: Int
    var onClose: (() -> Void)?

    @StateObject private var engine = MpvEngine()
    @StateObject private var danmaku = DanmakuEngine()
    @State private var currentIndex: Int
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @State private var danmakuEnabled = false
    /// 底部面板显示/隐藏（控制条按钮切换，默认关闭）
    @State private var showEpisodeBar = false
    /// 底部面板 tab：选集 / 切换源（同一面板内切换，不弹窗）
    private enum PanelTab { case episodes, sources }
    @State private var panelTab: PanelTab = .episodes
    /// 本集是否已触发过连播（每集只触发一次）
    @State private var advancedThisEpisode = false
    /// 上次保存进度时间（节流）
    @State private var lastSaved = Date.distantPast

    private let rateOptions: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    init(detail: DramaDetail, startIndex: Int = 0, onClose: (() -> Void)? = nil) {
        self.detail = detail
        self.startIndex = startIndex
        self.onClose = onClose
        _currentIndex = State(initialValue: detail.episodes.isEmpty ? 0 : min(max(startIndex, 0), detail.episodes.count - 1))
    }

    private var episodes: [Episode] { detail.episodes }
    private var currentEpisode: Episode? { episodes.indices.contains(currentIndex) ? episodes[currentIndex] : nil }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .center) {
                MpvVideoSurface(engine: engine)
                    .frame(minHeight: 360)
                if danmakuEnabled {
                    DanmakuOverlay(engine: danmaku,
                                   fontScale: AppSettings.shared.danmakuFontScale,
                                   opacity: AppSettings.shared.danmakuOpacity)
                }
                if engine.isBuffering {
                    ProgressView().controlSize(.large).tint(.white)
                }
                if let err = engine.error {
                    Text(err).font(.callout).foregroundStyle(.white)
                        .padding(10).background(.red.opacity(0.8)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .background(.black)

            controlBar
            if showEpisodeBar { bottomPanel }
        }
        .background(.black)
        .sheet(isPresented: $showOtherSeasons) {
            otherSeasonsSheet
        }
        .confirmationDialog("在外部播放器中打开", isPresented: $showExternalPlayerDialog, titleVisibility: .visible) {
            ForEach(ExternalPlayerOpener.installedApps) { app in
                Button("在 \(app.displayName) 中打开") { openInExternalPlayer(app) }
            }
            Button("取消", role: .cancel) {}
        }
        .onAppear {
            engine.rate = AppSettings.shared.defaultPlaybackRate
            danmakuEnabled = AppSettings.shared.danmakuEnabled
            loadEpisode(currentIndex, autoplay: true)
            // 后台预搜可切换源（不阻塞起播），点「切换源」时直接用缓存秒显
            Task { await searchSources() }
        }
        .onDisappear { saveProgress(); engine.stop() }
        .onChange(of: engine.currentTime) { _, t in
            danmaku.tick(time: t)
            maybePrefetchOrAdvance()
            maybeSaveProgress()
        }
        .onChange(of: engine.videoIsPortrait) { _, portrait in
            MpvWindowManager.shared.adaptToVideo(portrait: portrait)
        }
        .onReceive(NotificationCenter.default.publisher(for: .hongguoRemoteToggle)) { _ in engine.togglePlayPause() }
        .onReceive(NotificationCenter.default.publisher(for: .hongguoRemoteNext)) { _ in playNext() }
        .onReceive(NotificationCenter.default.publisher(for: .hongguoRemotePrev)) { _ in playPrevious() }
        .onReceive(NotificationCenter.default.publisher(for: .hongguoPlayerWindowClosed)) { _ in
            saveProgress(); engine.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hongguoBossKeyHide)) { _ in engine.pause() }
    }

    // MARK: 底部面板（选集 / 切换源 tab，全宽底部打开不弹窗）
    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.md) {
                // 选集 / 切换源 分段切换（同一面板）
                HStack(spacing: 0) {
                    panelTabButton("选集", tab: .episodes)
                    panelTabButton("切换源", tab: .sources)
                }
                if panelTab == .episodes {
                    Text("\(episodes.count) 集").font(Typography.caption).foregroundStyle(.white.opacity(0.6))
                } else {
                    Text("正在播放第 \(currentIndex + 1) 集，选源从该集续播")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Button { showEpisodeBar = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider().background(.white.opacity(0.2))

            if panelTab == .episodes {
                episodeGridView
            } else {
                sourceListPane
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .background(.black.opacity(0.95))
    }

    private func panelTabButton(_ title: String, tab: PanelTab) -> some View {
        Button { panelTab = tab } label: {
            Text(title)
                .font(.system(size: 13, weight: panelTab == tab ? .semibold : .regular))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(panelTab == tab ? Brand.accent : Color.clear))
                .foregroundStyle(panelTab == tab ? .white : .white.opacity(0.6))
        }
        .buttonStyle(.plain)
    }

    /// 选集网格（换行，不左右滑动）。
    private var episodeGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 60), spacing: Spacing.sm)], spacing: Spacing.sm) {
                ForEach(Array(episodes.enumerated()), id: \.element.id) { idx, ep in
                    Button { loadEpisode(idx, autoplay: true) } label: {
                        Text("\(ep.index)")
                            .font(.system(size: 12, weight: idx == currentIndex ? .semibold : .regular))
                            .foregroundStyle(idx == currentIndex ? .white : .white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(idx == currentIndex ? Brand.accent : Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
    }

    /// 切换源列表（底部面板内展示，不弹窗）。
    private var sourceListPane: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if isSearchingSources && sourceCandidates.isEmpty {
                HStack(spacing: Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text(searchingSiteName.isEmpty
                         ? "正在跨在线源检索「\(detail.drama.title)」…"
                         : "正在检索：\(searchingSiteName) …")
                        .font(Typography.caption).foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sourceCandidates.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.white.opacity(0.4))
                    Text("未找到可切换的源").font(Typography.body).foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sourceCandidates) { m in
                    Button {
                        Task { await switchToSource(m) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.drama.title).foregroundStyle(.white)
                                Text(m.siteName).font(Typography.caption).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            Text("\(m.drama.episodeCount ?? 0) 集").font(Typography.caption).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: 控制条
    private var controlBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(fmt(engine.currentTime)).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
                Slider(value: $scrubValue, in: 0...max(engine.duration, 1)) { editing in
                    isScrubbing = editing
                    if !editing { engine.seek(to: scrubValue) }
                }
                .onChange(of: engine.currentTime) { _, v in if !isScrubbing { scrubValue = v } }
                Text(fmt(engine.duration)).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
            }
            HStack(spacing: 14) {
                Button { playPrevious() } label: { Image(systemName: "backward.fill") }.buttonStyle(.plain).foregroundStyle(.white)
                    .disabled(currentIndex <= 0)
                    .help("上一集")
                Button { engine.togglePlayPause() } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                }
                .buttonStyle(.plain).foregroundStyle(.white)
                .help("播放/暂停")
                Button { playNext() } label: { Image(systemName: "forward.fill") }.buttonStyle(.plain).foregroundStyle(.white)
                    .disabled(currentIndex >= episodes.count - 1)
                    .help("下一集")

                // 倍速：限宽防拉很长（对齐 AVPlayer 链路的 56pt）
                Menu {
                    ForEach(rateOptions, id: \.self) { r in Button("\(r, specifier: "%.2g")×") { engine.rate = r } }
                } label: { Text("\(engine.rate, specifier: "%.2g")×").font(.callout).foregroundStyle(.white) }
                    .frame(width: 56)

                Image(systemName: "speaker.fill").foregroundStyle(.white.opacity(0.6))
                Slider(value: Binding(get: { engine.volume }, set: { engine.volume = $0 }), in: 0...1)
                    .frame(width: 80)

                Spacer()

                // 查找其他季
                Button {
                    Task { await findOtherSeasons() }
                } label: { Image(systemName: "square.stack.2.1") }
                .buttonStyle(.plain).foregroundStyle(.white)
                .help("查找其他季 / 相似剧")

                // 切换视频源：切到底部面板的 sources tab 并展开（不弹窗）
                Button {
                    panelTab = .sources
                    showEpisodeBar = true
                    Task { await openSourceSwitcher() }
                } label: { Image(systemName: "arrow.triangle.2.circlepath.circle") }
                .buttonStyle(.plain).foregroundStyle(.white)
                .help("切换视频源（换源续播当前集）")

                // 外部播放器打开：Button + 点击弹 NSMenu（Menu+menuIndicator(.hidden) 在 mpv 窗口不渲染图标）
                Button {
                    showExternalPlayerMenu()
                } label: {
                    Image(systemName: "play.rectangle.on.rectangle")
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .help("在外部播放器中打开当前集")

                // 下载当前集
                Button { downloadCurrentEpisode() } label: {
                    Image(systemName: downloadButtonIcon)
                }
                .buttonStyle(.plain).foregroundStyle(.white)
                .help(downloadButtonHelp)
                .disabled(currentDownloadState == .downloading || currentDownloadState == .completed)

                // 选集面板切换（切到 episodes tab）
                Button {
                    if showEpisodeBar && panelTab == .episodes {
                        showEpisodeBar = false
                    } else {
                        panelTab = .episodes
                        showEpisodeBar = true
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(showEpisodeBar && panelTab == .episodes ? Brand.accent : .white)
                }
                .buttonStyle(.plain)
                .help("选集")

                // 弹幕
                Button {
                    danmakuEnabled.toggle()
                    AppSettings.shared.danmakuEnabled = danmakuEnabled
                } label: {
                    Image(systemName: danmakuEnabled ? "text.bubble.fill" : "text.bubble")
                        .foregroundStyle(danmakuEnabled ? .cyan : .white.opacity(0.6))
                }
                .buttonStyle(.plain).help(danmakuEnabled ? "关闭弹幕" : "开启弹幕")

                if !engine.subtitleTracks.isEmpty {
                    Menu {
                        Button("关闭字幕") { engine.selectSubtitle(id: nil) }
                        ForEach(engine.subtitleTracks) { t in Button(t.title) { engine.selectSubtitle(id: t.id) } }
                    } label: { Image(systemName: "captions.bubble").foregroundStyle(.white) }
                }
                if engine.audioTracks.count > 1 {
                    Menu {
                        ForEach(engine.audioTracks) { t in Button(t.title) { engine.selectAudio(id: t.id) } }
                    } label: { Image(systemName: "speaker.wave.2").foregroundStyle(.white) }
                }
                if let onClose {
                    Button { saveProgress(); engine.stop(); onClose() } label: {
                        Image(systemName: "xmark.circle").foregroundStyle(.white)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.black.opacity(0.85))
    }

    // MARK: 加载与连播
    private func loadEpisode(_ index: Int, autoplay: Bool) {
        guard episodes.indices.contains(index) else { return }
        saveProgress()
        currentIndex = index
        advancedThisEpisode = false
        let ep = episodes[index]
        guard let url = resolvePlayURL(dramaId: detail.drama.id, episode: ep, forMpv: true) else {
            engine.stop(); return
        }
        // 续播：有进度从进度起播；无进度按设置跳片头
        var start: TimeInterval? = nil
        if let prog = Repository.shared.progress(dramaId: detail.drama.id, episodeId: ep.id) {
            start = prog.position
        } else {
            let skip = AppSettings.shared.introSkipSeconds
            if skip > 0 { start = skip }
        }
        // mpv 直连采集站 m3u8：注入浏览器 UA/Referer 防盗链（FFmpeg 默认 UA Lavf/... 易被拒）。
        var headers: [String: String] = [:]
        if url.absoluteString.contains(".m3u8"), let scheme = URL(string: url.absoluteString) {
            headers["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
            headers["Referer"] = "\(scheme.scheme ?? "https")://\(scheme.host ?? "")/"
        }
        let source = PlaybackSource(delivery: .direct, url: url, headers: headers, startPosition: start)
        engine.load(source: source)
        if autoplay { engine.play() }
        AppLog.log(.player, "[mpv] 选集 第\(ep.index)集(\(ep.id)) start=\(start ?? 0)")
    }

    private func playNext() {
        guard currentIndex < episodes.count - 1 else { return }
        loadEpisode(currentIndex + 1, autoplay: true)
    }
    private func playPrevious() {
        guard currentIndex > 0 else { return }
        loadEpisode(currentIndex - 1, autoplay: true)
    }

    /// 进度≥99% 且开了自动连播 → 下一集（每集一次）。
    private func maybePrefetchOrAdvance() {
        guard !advancedThisEpisode, engine.duration > 0 else { return }
        if engine.currentTime >= engine.duration * 0.99 {
            advancedThisEpisode = true
            saveProgress()
            if AppSettings.shared.autoPlayNext, currentIndex < episodes.count - 1 {
                playNext()
            }
        }
    }

    // MARK: 进度保存（节流 5s）
    private func maybeSaveProgress() {
        if Date().timeIntervalSince(lastSaved) > 5 { saveProgress() }
    }
    private func saveProgress() {
        guard let ep = currentEpisode, engine.duration > 0 else { return }
        lastSaved = Date()
        Repository.shared.saveProgress(dramaId: detail.drama.id, episodeId: ep.id,
                                       title: detail.drama.title, episodeTitle: ep.title,
                                       coverURL: detail.drama.coverURL,
                                       position: engine.currentTime, duration: engine.duration)
    }

    // MARK: - 查找其他季 / 切换源 / 外部播放器 / 下载（对齐 AVPlayer 链路 PlayerView）

    @State private var showOtherSeasons = false
    @State private var otherSeasons: [Drama] = []
    @State private var showSourceSwitcher = false
    /// 源搜索结果缓存（按剧名 key 的静态字典，view 重建不丢——切源后 MpvWindowManager 重建窗口，@State 会重置）
    private static var sourceCache: [String: [SourceMatch]] = [:]
    @State private var sourceCandidates: [SourceMatch] = []
    @State private var isSearchingSources = false
    @State private var searchingSiteName = ""

    private func findOtherSeasons() async {
        otherSeasons = []
        showOtherSeasons = true
        do {
            let results = try await CatalogService.shared.search(query: detail.drama.title)
            let base = normalize(detail.drama.title)
            otherSeasons = results.filter {
                $0.id != detail.drama.id && similarity(base, normalize($0.title)) > 0.3
            }
        } catch {
            otherSeasons = []
        }
    }

    private func openSourceSwitcher() async {
        showSourceSwitcher = true
        if !sourceCandidates.isEmpty || isSearchingSources { return }
        await searchSources()
    }

    private func searchSources() async {
        if isSearchingSources { return }
        isSearchingSources = true
        sourceCandidates = []
        let keyword = detail.drama.title
        // 有缓存先用缓存（view 重建后秒显），同时后台刷新
        if let cached = Self.sourceCache[keyword], !cached.isEmpty {
            sourceCandidates = cached
        }
        let sm = SourceManager.shared
        let sites = sm.enabledSites.filter { site in
            guard let r = sm.testResults[site.key] else { return true }
            return r.ok || !sm.disabled.contains(site.key)
        }
        await withTaskGroup(of: (String, [SourceMatch]).self) { group in
            var pending = sites.makeIterator()
            func enqueue() {
                if let s = pending.next() {
                    group.addTask {
                        let list = await Self.searchOneSite(sm: sm, site: s, query: keyword)
                        return (s.name, list)
                    }
                }
            }
            for _ in 0..<5 { enqueue() }
            while let (siteName, chunk) = await group.next() {
                searchingSiteName = siteName
                if !chunk.isEmpty {
                    sourceCandidates.append(contentsOf: chunk)
                    var seen = Set<String>()
                    let q = keyword
                    sourceCandidates = sourceCandidates.filter { seen.insert($0.id).inserted }.sorted { a, b in
                        let ea = a.drama.title == q, eb = b.drama.title == q
                        if ea != eb { return ea }
                        return (a.drama.episodeCount ?? 0) > (b.drama.episodeCount ?? 0)
                    }
                    // 写静态缓存（view 重建不丢）
                    Self.sourceCache[keyword] = sourceCandidates
                }
                enqueue()
            }
        }
        searchingSiteName = ""
        isSearchingSources = false
    }

    private static func searchOneSite(sm: SourceManager, site: SourceManager.TVBoxSite, query: String) async -> [SourceMatch] {
        await withTaskGroup(of: [SourceMatch]?.self) { g in
            g.addTask {
                let list = (try? await sm.tvboxSearch(siteKey: site.key, query: query)) ?? []
                return list.map { SourceMatch(drama: $0, siteKey: site.key, siteName: site.name) }
            }
            g.addTask { try? await Task.sleep(nanoseconds: 8_000_000_000); return nil }
            let first = await g.next() ?? nil
            g.cancelAll()
            return first ?? []
        }
    }

    private func switchToSource(_ match: SourceMatch) async {
        let targetEp = currentIndex
        showSourceSwitcher = false
        do {
            let parts = match.drama.id.split(separator: "|").map(String.init)
            guard parts.count == 3 else { return }
            let newDetail = try await SourceManager.shared.tvboxDetail(siteKey: parts[1], vodId: parts[2])
            guard !newDetail.episodes.isEmpty else { return }
            // 换源后重建 detail，从当前集续播
            let idx = min(targetEp, newDetail.episodes.count - 1)
            AppLog.log(.player, "[mpv] 手动切源 → \(match.siteName)《\(newDetail.drama.title)》续播第\(idx + 1)集")
            // MpvPlayerShellView 的 detail 是 let，无法直接换——需要重建整个 view。
            // 方案：发通知让 MpvWindowManager 用新 detail 重建窗口。
            NotificationCenter.default.post(name: .hongguoSwitchSource, object: nil, userInfo: [
                "detail": newDetail, "startIndex": idx
            ])
        } catch {
            AppLog.log(.error, "[mpv] 切源失败：\(error.localizedDescription)")
        }
    }

    private func switchTo(_ drama: Drama) async {
        do {
            let newDetail = try await CatalogService.shared.detail(id: drama.id)
            showOtherSeasons = false
            NotificationCenter.default.post(name: .hongguoSwitchSource, object: nil, userInfo: [
                "detail": newDetail, "startIndex": 0
            ])
        } catch {
            AppLog.log(.error, "[mpv] 切换其他季失败：\(error.localizedDescription)")
        }
    }

    /// 当前集的可播放地址（经网关代理，外部播放器可直接访问）。
    private var shareablePlayURL: URL? {
        guard let ep = currentEpisode else { return nil }
        if let url = ep.playURL, !url.isEmpty {
            if url.hasPrefix("file://") { return URL(string: url) }
            if url.lowercased().contains(".m3u8") { return hongguoGatewayM3U8URL(url) }
            if detail.drama.id.hasPrefix("nas|") { return URL(string: url) }
            return hongguoGatewayMediaURL(url)
        }
        return URL(string: "\(AppConfig.gatewayBaseURL)/api/stream/\(detail.drama.id)/\(ep.id)")
    }

    private func openInExternalPlayer(_ app: ExternalPlayerApp) {
        guard let url = shareablePlayURL else { return }
        ExternalPlayerOpener.open(url: url, app: app)
    }

    /// 弹外部播放器选择框（SwiftUI confirmationDialog，Menu+menuIndicator(.hidden) 在 mpv 窗口不渲染图标）。
    @State private var showExternalPlayerDialog = false
    private func showExternalPlayerMenu() {
        showExternalPlayerDialog = true
    }

    private func downloadCurrentEpisode() {
        guard let ep = currentEpisode, let url = shareablePlayURL else { return }
        DownloadManager.shared.addDownload(
            dramaId: detail.drama.id, episodeId: ep.id,
            dramaTitle: detail.drama.title, episodeTitle: ep.title,
            sourceURL: url.absoluteString
        )
    }

    private var currentDownloadState: DownloadState? {
        guard let ep = currentEpisode else { return nil }
        return DownloadManager.shared.status(for: detail.drama.id, episodeId: ep.id)
    }

    private var downloadButtonIcon: String {
        switch currentDownloadState {
        case .downloading: return "arrow.down.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle"
        default: return "arrow.down.circle"
        }
    }
    private var downloadButtonHelp: String {
        switch currentDownloadState {
        case .downloading: return "下载中…"
        case .completed: return "已下载"
        case .failed: return "下载失败，点击重试"
        default: return "下载当前集"
        }
    }

    // 标题归一化 / 相似度（从 PlayerViewModel 抄来，查找其他季用）
    private func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "第", with: "")
            .replacingOccurrences(of: "季", with: "")
            .replacingOccurrences(of: "部", with: "")
    }
    private func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        let longer = a.count > b.count ? a : b
        let shorter = a.count > b.count ? b : a
        if longer.contains(shorter) { return Double(shorter.count) / Double(longer.count) }
        let setA = Set(a), setB = Set(b)
        return Double(setA.intersection(setB).count) / Double(setA.union(setB).count)
    }

    // MARK: - 其他季 / 切换源 弹窗（sheet）
    private var otherSeasonsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("其他季 / 相似剧").font(.headline)
                Spacer()
                Button { showOtherSeasons = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.secondaryLabel)
                }
                .buttonStyle(.plain)
            }
            .padding()
            Divider()
            if otherSeasons.isEmpty {
                VStack(spacing: Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("正在检索…").font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(otherSeasons) { d in
                    Button {
                        Task { await switchTo(d) }
                    } label: {
                        HStack {
                            Text(d.title).foregroundStyle(Brand.label)
                            Spacer()
                            Text("\(d.episodeCount ?? 0) 集").font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 420, height: 480)
    }

    private func fmt(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "00:00" }
        let i = Int(s)
        return String(format: "%02d:%02d:%02d", i / 3600, (i % 3600) / 60, i % 60)
            .dropFirst(i >= 3600 ? 0 : 3).description
    }
}
