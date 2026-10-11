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
            if episodes.count > 1 { episodeBar }
        }
        .background(.black)
        .onAppear {
            engine.rate = AppSettings.shared.defaultPlaybackRate
            danmakuEnabled = AppSettings.shared.danmakuEnabled
            loadEpisode(currentIndex, autoplay: true)
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

    // MARK: 选集条
    private var episodeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(Array(episodes.enumerated()), id: \.element.id) { idx, ep in
                    Button { loadEpisode(idx, autoplay: true) } label: {
                        Text("\(ep.index)")
                            .font(.system(size: 12, weight: idx == currentIndex ? .semibold : .regular))
                            .foregroundStyle(idx == currentIndex ? .white : .white.opacity(0.6))
                            .frame(minWidth: 34)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(idx == currentIndex ? Brand.accent : Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .background(.black.opacity(0.9))
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
            HStack(spacing: 16) {
                Button { playPrevious() } label: { Image(systemName: "backward.fill") }.buttonStyle(.plain).foregroundStyle(.white)
                    .disabled(currentIndex <= 0)
                Button { engine.togglePlayPause() } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                }
                .buttonStyle(.plain).foregroundStyle(.white)
                Button { playNext() } label: { Image(systemName: "forward.fill") }.buttonStyle(.plain).foregroundStyle(.white)
                    .disabled(currentIndex >= episodes.count - 1)

                Menu {
                    ForEach(rateOptions, id: \.self) { r in Button("\(r, specifier: "%.2g")×") { engine.rate = r } }
                } label: { Text("\(engine.rate, specifier: "%.2g")×").font(.callout).foregroundStyle(.white) }

                Text(engine.hwDecoder).font(.caption).foregroundStyle(.white.opacity(0.5))
                Spacer()

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

    private func fmt(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "00:00" }
        let i = Int(s)
        return String(format: "%02d:%02d:%02d", i / 3600, (i % 3600) / 60, i % 60)
            .dropFirst(i >= 3600 ? 0 : 3).description
    }
}
