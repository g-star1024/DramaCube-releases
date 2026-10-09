import SwiftUI
import HongguoCore

/// 单集列表行。展示序号、标题、时长，以及「当前播放 / 已播」视觉标记。
public struct EpisodeRow: View {
    let episode: Episode
    let isCurrent: Bool
    let isPlayed: Bool
    let action: () -> Void

    public init(episode: Episode, isCurrent: Bool = false, isPlayed: Bool = false, action: @escaping () -> Void) {
        self.episode = episode
        self.isCurrent = isCurrent
        self.isPlayed = isPlayed
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: isPlayed ? "checkmark.circle.fill" : (isCurrent ? "play.circle.fill" : "circle"))
                    .foregroundStyle(isCurrent ? Brand.pink : .secondary)
                    .frame(width: 22, height: 22)
                Text("第 \(episode.index) 集")
                    .font(Typography.body)
                    .foregroundStyle(isCurrent ? Brand.pink : Brand.label)
                Spacer()
                if let d = episode.duration, d > 0 {
                    Text(HongguoFormat.duration(Double(d)))
                        .font(Typography.caption)
                        .foregroundStyle(Brand.secondaryLabel)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isCurrent ? Brand.secondaryBackground : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}
