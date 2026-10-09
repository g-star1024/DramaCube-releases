import SwiftUI
import HongguoCore

/// 剧集海报卡片：宽度随容器自适应（网格/横滑/详情推荐共用）。
public struct PosterCard: View {
    let drama: Drama
    public init(_ drama: Drama) { self.drama = drama }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // 用 Color.clear 撑出稳定 3:4 框，封面 overlay 填充后裁切，
            // 避免在弹性宽度容器里 scaledToFill 高度失控挤乱列表。
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    CoverImage(drama.coverURL.flatMap { URL(string: $0) })
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Brand.separator.opacity(0.6), lineWidth: 0.5))

            Text(drama.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(Brand.label)
                .help(drama.title)
            if let cnt = drama.episodeCount {
                Text("\(cnt) 集")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
