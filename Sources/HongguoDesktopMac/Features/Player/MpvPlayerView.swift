import SwiftUI
import HongguoCore
import HongguoGatewayCore

// MARK: - libmpv 播放器界面（M2）
// 完整 mpv 播放体验：播放/暂停/进度/倍速/字幕/音轨/硬解/HDR。
// 独立于现有 AVPlayer 链路，由「播放内核=mpv」设置启用。

public struct MpvPlayerView: View {
    let source: PlaybackSource
    let title: String
    /// 当前集数（弹幕在线匹配用）。
    var episode: Int?
    /// 本地视频文件 URL（有则自动找同名 xml/ass 弹幕）。
    var localVideoURL: URL?
    var onClose: (() -> Void)?

    @StateObject private var engine = MpvEngine()
    @StateObject private var danmaku = DanmakuEngine()
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @State private var showTracks = false
    @State private var danmakuEnabled = true
    private let rateOptions: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    public init(source: PlaybackSource, title: String, episode: Int? = nil,
                localVideoURL: URL? = nil, onClose: (() -> Void)? = nil) {
        self.source = source; self.title = title; self.episode = episode
        self.localVideoURL = localVideoURL; self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .center) {
                MpvVideoSurface(engine: engine)
                    .frame(minHeight: 360)
                // 弹幕渲染层（视频之上、控制之下）
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
        }
        .background(.black)
        .onAppear {
            engine.rate = AppSettings.shared.defaultPlaybackRate
            danmakuEnabled = AppSettings.shared.danmakuEnabled
            engine.load(source: source)
            engine.play()
            loadDanmaku()
        }
        .onDisappear { engine.stop() }
        .onChange(of: engine.currentTime) { _, t in danmaku.tick(time: t) }
    }

    // MARK: 弹幕加载
    private func loadDanmaku() {
        Task {
            // ① 本地同名弹幕文件优先
            if let lv = localVideoURL {
                let local = DanmakuSource.localDanmaku(near: lv)
                if !local.isEmpty { danmaku.load(entries: local); return }
            }
            // ② 在线：弹弹play 中文内容匹配
            guard AppSettings.shared.danmakuOnline else { return }
            let candidates = await DanmakuSource.searchDandan(title: title, episode: episode)
            if let hit = DanmakuSource.pickDandan(candidates: candidates, title: title, episode: episode) {
                let list = await DanmakuSource.fetchDandan(episodeId: hit.episodeId)
                if !list.isEmpty { danmaku.load(entries: list) }
            }
        }
    }

    private var controlBar: some View {
        VStack(spacing: 8) {
            // 进度条
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
                // 播放/暂停
                Button { engine.togglePlayPause() } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                }
                .buttonStyle(.plain).foregroundStyle(.white)

                // 倍速
                Menu {
                    ForEach(rateOptions, id: \.self) { r in
                        Button("\(r, specifier: "%.2g")×") { engine.rate = r }
                    }
                } label: {
                    Text("\(engine.rate, specifier: "%.2g")×").font(.callout).foregroundStyle(.white)
                }

                // 硬解标识
                Text(engine.hwDecoder).font(.caption).foregroundStyle(.white.opacity(0.5))

                Spacer()

                // 弹幕开关
                Button {
                    danmakuEnabled.toggle()
                    AppSettings.shared.danmakuEnabled = danmakuEnabled
                } label: {
                    Image(systemName: danmakuEnabled ? "text.bubble.fill" : "text.bubble")
                        .foregroundStyle(danmakuEnabled ? .cyan : .white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help(danmakuEnabled ? "关闭弹幕" : "开启弹幕")

                // 字幕
                if !engine.subtitleTracks.isEmpty {
                    Menu {
                        Button("关闭字幕") { engine.selectSubtitle(id: nil) }
                        ForEach(engine.subtitleTracks) { t in
                            Button(t.title) { engine.selectSubtitle(id: t.id) }
                        }
                    } label: {
                        Image(systemName: "captions.bubble").foregroundStyle(.white)
                    }
                }

                // 音轨
                if engine.audioTracks.count > 1 {
                    Menu {
                        ForEach(engine.audioTracks) { t in
                            Button(t.title) { engine.selectAudio(id: t.id) }
                        }
                    } label: {
                        Image(systemName: "speaker.wave.2").foregroundStyle(.white)
                    }
                }

                if let onClose {
                    Button { engine.stop(); onClose() } label: {
                        Image(systemName: "xmark.circle").foregroundStyle(.white)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.black.opacity(0.85))
    }

    private func fmt(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "00:00" }
        let i = Int(s)
        return String(format: "%02d:%02d:%02d", i / 3600, (i % 3600) / 60, i % 60)
            .dropFirst(i >= 3600 ? 0 : 3).description
    }
}
