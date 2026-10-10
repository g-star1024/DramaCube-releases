import SwiftUI
import AVKit
import AppKit
import HongguoCore

/// 播放器界面（完整控制条 + 选集 + 倍速 + 画中画 + 全屏 + 查找其他季）。
///
/// 支持两种呈现方式：
///  - 独立窗口（PlayerWindowManager，支持全屏）：传 `onClose`；
///  - sheet 弹出（旧路径）：不传 `onClose`，走环境 dismiss。
public struct PlayerView: View {
    let detail: DramaDetail
    let startIndex: Int
    var onClose: (() -> Void)?

    @StateObject private var vm: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @State private var playedIds: Set<String> = []
    @State private var wasPlaying = false
    /// 鼠标悬停在视频区时显示左上角悬浮控制（默认隐藏，不挡画面）。
    @State private var isHoveringVideo = false
    /// 选集批量缓存选择模式
    @State private var isSelectingDownloads = false
    @State private var selectedDownloads: Set<Int> = []

    private let rateOptions: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    public init(detail: DramaDetail, startIndex: Int = 0, onClose: (() -> Void)? = nil) {
        self.detail = detail
        self.startIndex = startIndex
        self.onClose = onClose
        _vm = StateObject(wrappedValue: PlayerViewModel(detail: detail, startIndex: startIndex))
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                VideoSurface(player: vm.player)
                    .frame(minHeight: 360)
                if vm.isBuffering {
                    ProgressView().controlSize(.large).tint(.white)
                }
                if vm.isResuming {
                    Text("续播中…").font(Typography.caption).foregroundStyle(.white)
                        .padding(6).background(.black.opacity(0.5)).clipShape(RoundedRectangle(cornerRadius: 6))
                }
                if let err = vm.error {
                    errorOverlay(err)
                }
                // 左上角悬浮控制：关闭 / 标题（Esc 全屏中先退全屏，否则关闭）
                // 窗口已有系统红黄绿按钮，此悬浮层默认隐藏，鼠标悬停视频区时才淡入，不遮挡画面。
                if isHoveringVideo {
                    HStack(spacing: Spacing.sm) {
                        Button {
                            handleEsc()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(.black.opacity(0.45)))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.escape, modifiers: [])
                        .help(PlayerWindowManager.shared.isManuallyFullscreen ? "退出全屏 (Esc)" : "关闭播放器 (Esc)")

                        Text("\(detail.drama.title) · 第 \(vm.currentEpisode?.index ?? 0) 集")
                            .font(Typography.caption)
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.black.opacity(0.45)))
                    }
                    .padding(Spacing.md)
                    .transition(.opacity)
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) { isHoveringVideo = hovering }
            }
            .onTapGesture(count: 2) { toggleFullscreen() }
            .help("双击切换全屏")
            Divider()
            controlBar
            if vm.showEpisodes { episodePanel }
        }
        .frame(minWidth: 880, minHeight: 600)
        .navigationTitle(detail.drama.title)
        .onReceive(vm.$currentTime) { t in if !isScrubbing { scrubValue = t } }
        .onReceive(vm.$currentIndex) { _ in refreshPlayed() }
        .onReceive(NotificationCenter.default.publisher(for: .hongguoBossKeyHide)) { _ in
            wasPlaying = vm.isPlaying
            vm.pause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hongguoBossKeyShow)) { _ in
            if wasPlaying { vm.play() }
        }
        // 独立窗口被红 × / ⌘W 关闭时停播 + 存进度
        .onReceive(NotificationCenter.default.publisher(for: .hongguoPlayerWindowClosed)) { _ in
            vm.pause()
            vm.saveProgress(force: true)
        }
        .task { refreshPlayed() }
        .sheet(isPresented: $vm.showOtherSeasons) { otherSeasonsSheet }
    }

    /// 播放失败覆盖层：重试 / 换下一集 / 关闭，避免只能干瞪眼。
    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("播放失败：\(message)")
                .font(Typography.caption)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: Spacing.sm) {
                Button("重试") { vm.loadEpisode(vm.currentIndex) }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent)
                if vm.episodes.indices.contains(vm.currentIndex + 1) {
                    Button("换下一集") { vm.loadEpisode(vm.currentIndex + 1) }
                        .buttonStyle(.bordered)
                }
                Button("返回") { closePlayer() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(Spacing.lg)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(.black.opacity(0.65)))
    }

    /// 关闭播放器：暂停 + 保存进度 + 关窗口 / sheet。
    private func closePlayer() {
        vm.pause()
        vm.saveProgress(force: true)
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    /// Esc：手动全屏中先退全屏，否则关闭播放器。
    private func handleEsc() {
        if PlayerWindowManager.shared.isManuallyFullscreen {
            PlayerWindowManager.shared.toggleFullscreen()
        } else {
            closePlayer()
        }
    }

    // MARK: 下载按钮状态
    private var downloadButtonIcon: String {
        switch vm.currentDownloadState {
        case .downloading: return "arrow.down.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle"
        default: return "arrow.down.circle"
        }
    }
    private var downloadButtonHelp: String {
        switch vm.currentDownloadState {
        case .downloading: return "下载中…"
        case .completed: return "已下载"
        case .failed: return "下载失败，点击重试"
        default: return "下载当前集"
        }
    }

    // MARK: 控制条
    private var controlBar: some View {
        HStack(spacing: Spacing.sm) {
            Button { vm.playPrevious() } label: { Image(systemName: "backward.fill") }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .help("上一集 (⌘←)")
            Button { vm.togglePlayPause() } label: {
                Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
            }
            .frame(width: 28, height: 28)
            .keyboardShortcut(.space, modifiers: [])
            .help("播放/暂停 (空格)")
            Button { vm.playNext() } label: { Image(systemName: "forward.fill") }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .help("下一集 (⌘→)")

            Text(HongguoFormat.duration(scrubValue)).monospacedDigit().font(Typography.caption)
                .foregroundStyle(Brand.secondaryLabel)

            Slider(value: $scrubValue, in: 0...max(vm.duration, 1), onEditingChanged: { editing in
                isScrubbing = editing
                if !editing { vm.seek(to: scrubValue) }
            })

            Text(HongguoFormat.duration(vm.duration)).monospacedDigit().font(Typography.caption)
                .foregroundStyle(Brand.secondaryLabel)

            Menu {
                ForEach(rateOptions, id: \.self) { r in
                    Button { vm.setRate(r) } label: { Text("\(r, specifier: "%.2f")x") }
                }
            } label: {
                Text("\(vm.rate, specifier: "%.2f")x").monospacedDigit().frame(minWidth: 44)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 56)

            Image(systemName: "speaker.fill").foregroundStyle(Brand.secondaryLabel)
            Slider(value: Binding(get: { vm.volume }, set: { vm.setVolume($0) }), in: 0...1)
                .frame(width: 80)

            Button {
                Task { await vm.findOtherSeasons() }
            } label: { Image(systemName: "square.stack.2.1") }
            .help("查找其他季 / 相似剧")

            Menu {
                ForEach(ExternalPlayerOpener.installedApps) { app in
                    Button { vm.openInExternalPlayer(app) } label: {
                        Text("在 \(app.displayName) 中打开")
                    }
                }
            } label: {
                Image(systemName: "play.rectangle.on.rectangle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help("在外部播放器中打开当前集")

            Button { vm.downloadCurrentEpisode() } label: {
                Image(systemName: downloadButtonIcon)
            }
            .help(downloadButtonHelp)
            .disabled(vm.currentDownloadState == .downloading || vm.currentDownloadState == .completed)

            Button { vm.showEpisodes.toggle() } label: { Image(systemName: "list.bullet") }

            Button { PipCoordinator.shared.toggle() } label: { Image(systemName: "rectangle.on.rectangle") }
                .disabled(!PipCoordinator.shared.isPossible)

            Button { toggleFullscreen() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .keyboardShortcut(.return, modifiers: .command)
                .help("全屏 (⌘↩)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, Spacing.md)        .padding(.vertical, Spacing.sm)
        .controlSize(.regular)
    }

    // MARK: 选集面板（全宽底部面板，随窗口宽度铺满）
    private var episodePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EpisodePanelHeader(count: vm.episodes.count) {
                    vm.showEpisodes = false
                }
                // 批量缓存切换
                Button(isSelectingDownloads ? "完成" : "批量缓存") {
                    isSelectingDownloads.toggle()
                    if !isSelectingDownloads { selectedDownloads.removeAll() }
                }
                .controlSize(.small)
                .font(.system(size: 11))
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            // 批量缓存操作条
            if isSelectingDownloads {
                HStack(spacing: Spacing.md) {
                    Button(selectedDownloads.count == vm.episodes.count ? "取消全选" : "全选") {
                        selectedDownloads = selectedDownloads.count == vm.episodes.count
                            ? [] : Set(vm.episodes.indices)
                    }
                    .controlSize(.small)
                    Text("已选 \(selectedDownloads.count) 集")
                        .font(Typography.caption)
                        .foregroundStyle(Brand.secondaryLabel)
                    Spacer()
                    Button("缓存选中", role: .destructive) {
                        vm.downloadEpisodes(indices: Array(selectedDownloads).sorted())
                        selectedDownloads.removeAll()
                        isSelectingDownloads = false
                    }
                    .controlSize(.small)
                    .disabled(selectedDownloads.isEmpty)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.xs)
                .background(Brand.chipFill)
            }
            Divider()
            ScrollView {
                ScrollViewReader { proxy in
                    EpisodeGrid(
                        episodes: vm.episodes,
                        currentIndex: vm.currentIndex,
                        playedIds: playedIds,
                        selectedIndices: isSelectingDownloads ? selectedDownloads : nil
                    ) { idx, _ in
                        if isSelectingDownloads {
                            if selectedDownloads.contains(idx) { selectedDownloads.remove(idx) }
                            else { selectedDownloads.insert(idx) }
                        } else {
                            vm.loadEpisode(idx)
                        }
                    }
                    .padding(Spacing.lg)
                    .onAppear {
                        proxy.scrollTo(vm.currentIndex, anchor: .center)
                    }
                    .onChange(of: vm.currentIndex) { _, new in
                        withAnimation { proxy.scrollTo(new, anchor: .center) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .background(Brand.secondaryBackground)
    }

    // MARK: 其他季
    private var otherSeasonsSheet: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("其他季 / 相似剧").font(Typography.title)
                Spacer()
                Button("关闭") { vm.showOtherSeasons = false }
            }
            if vm.otherSeasons.isEmpty {
                EmptyState("未找到相似剧集", systemImage: "magnifyingglass")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Spacing.md)], spacing: Spacing.md) {
                        ForEach(vm.otherSeasons) { d in
                            PosterCard(d)
                                .onTapGesture { Task { await vm.switchTo(d) } }
                        }
                    }
                    .padding(Spacing.md)
                }
            }
        }
        .padding(Spacing.lg)
        .frame(width: 640, height: 520)
    }

    private func refreshPlayed() {
        playedIds = Set(Repository.shared.history().filter { $0.dramaId == vm.dramaId }.map(\.episodeId))
    }

    private func toggleFullscreen() {
        // 独立窗口路径：直接用 PlayerWindowManager 持有的窗口引用（最可靠）
        if PlayerWindowManager.shared.hasWindow {
            PlayerWindowManager.shared.toggleFullscreen()
            return
        }
        // sheet 兜底路径
        if let w = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            w.toggleFullScreen(nil)
        }
    }
}
