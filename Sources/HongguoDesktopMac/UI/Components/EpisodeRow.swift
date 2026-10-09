import SwiftUI
import HongguoCore

/// 选集胶囊网格：每行多个胶囊，适配长剧（250+ 集不再是一条望不到头的列表）。
///  - 当前播放集：品牌色实底 + 白字
///  - 已看集：品牌色淡底 + 品牌色字
///  - 未看集：中性底
public struct EpisodeGrid: View {
    let episodes: [Episode]
    let currentIndex: Int
    let playedIds: Set<String>
    let action: (_ index: Int, _ episode: Episode) -> Void

    public init(episodes: [Episode],
                currentIndex: Int = -1,
                playedIds: Set<String> = [],
                action: @escaping (_ index: Int, _ episode: Episode) -> Void) {
        self.episodes = episodes
        self.currentIndex = currentIndex
        self.playedIds = playedIds
        self.action = action
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 76, maximum: 110), spacing: Spacing.sm)]
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.sm) {
            ForEach(Array(episodes.enumerated()), id: \.element.id) { idx, ep in
                chip(for: ep, index: idx)
            }
        }
    }

    @ViewBuilder
    private func chip(for episode: Episode, index: Int) -> some View {
        let isCurrent = index == currentIndex
        let isPlayed = playedIds.contains(episode.id)
        Button {
            action(index, episode)
        } label: {
            Text("\(episode.index)")
                .font(isCurrent ? Typography.caption.bold() : Typography.caption)
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 30)
                .padding(.horizontal, 6)
                .background(chipBackground(isCurrent: isCurrent, isPlayed: isPlayed))
                .foregroundStyle(chipForeground(isCurrent: isCurrent, isPlayed: isPlayed))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(isCurrent ? Color.clear : Brand.separator.opacity(0.6), lineWidth: 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .id(index)
        .help("第 \(episode.index) 集\(isPlayed ? "（已看）" : "")")
    }

    private func chipBackground(isCurrent: Bool, isPlayed: Bool) -> Color {
        if isCurrent { return Brand.accent }
        if isPlayed { return Brand.accent.opacity(0.12) }
        return Brand.secondaryBackground
    }

    private func chipForeground(isCurrent: Bool, isPlayed: Bool) -> Color {
        if isCurrent { return .white }
        if isPlayed { return Brand.accent }
        return Brand.label
    }
}

/// 选集面板头部：标题 + 总集数 + 可选收起按钮。
public struct EpisodePanelHeader: View {
    let count: Int
    var onClose: (() -> Void)?

    public init(count: Int, onClose: (() -> Void)? = nil) {
        self.count = count
        self.onClose = onClose
    }

    public var body: some View {
        HStack {
            Text("选集")
                .font(Typography.headline)
            Text("\(count) 集")
                .font(Typography.caption)
                .foregroundStyle(Brand.secondaryLabel)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Brand.secondaryBackground))
            Spacer()
            if let onClose {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.secondaryLabel)
                .help("收起选集")
            }
        }
    }
}
