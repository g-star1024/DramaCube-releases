import SwiftUI
import AVKit
import AppKit
import HongguoCore

/// 播放器界面（完整控制条 + 选集 + 倍速 + 画中画 + 全屏 + 查找其他季）。
public struct PlayerView: View {
    let detail: DramaDetail
    let startIndex: Int

    @StateObject private var vm: PlayerViewModel
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @State private var playedIds: Set<String> = []
    @State private var wasPlaying = false

    private let rateOptions: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    public init(detail: DramaDetail, startIndex: Int = 0) {
        self.detail = detail
        self.startIndex = startIndex
        _vm = StateObject(wrappedValue: PlayerViewModel(detail: detail, startIndex: startIndex))
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
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
                    ErrorView(err) { vm.loadEpisode(vm.currentIndex) }
                }
            }
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
        .task { refreshPlayed() }
        .sheet(isPresented: $vm.showOtherSeasons) { otherSeasonsSheet }
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

            Button { vm.showEpisodes.toggle() } label: { Image(systemName: "list.bullet") }

            Button { PipCoordinator.shared.toggle() } label: { Image(systemName: "rectangle.on.rectangle") }
                .disabled(!PipCoordinator.shared.isPossible)

            Button { toggleFullscreen() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .keyboardShortcut(.return, modifiers: .command)
                .help("全屏 (⌘↩)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .controlSize(.regular)
    }

    // MARK: 选集面板
    private var episodePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("选集（共 \(vm.episodes.count) 集）")
                .font(Typography.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.md)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(vm.episodes.enumerated()), id: \.element.id) { idx, ep in
                        EpisodeRow(
                            episode: ep,
                            isCurrent: idx == vm.currentIndex,
                            isPlayed: playedIds.contains(ep.id)
                        ) {
                            vm.loadEpisode(idx)
                        }
                    }
                }
                .padding(Spacing.sm)
            }
        }
        .frame(width: 300)
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
        if let w = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            w.toggleFullScreen(nil)
        }
    }
}
