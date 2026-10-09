import SwiftUI
import HongguoCore

/// 剧集海报卡片。
public struct PosterCard: View {
    let drama: Drama
    public init(_ drama: Drama) { self.drama = drama }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Group {
                if let urlStr = drama.coverURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        case .failure: Color.gray
                        default: ProgressView()
                        }
                    }
                } else {
                    Color.gray
                }
            }
            .frame(width: 150, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Brand.separator, lineWidth: 0.5))

            Text(drama.title)
                .font(Typography.caption)
                .lineLimit(1)
                .foregroundStyle(Brand.label)
            if let cnt = drama.episodeCount {
                Text("\(cnt) 集")
                    .font(.caption2)
                    .foregroundStyle(Brand.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
