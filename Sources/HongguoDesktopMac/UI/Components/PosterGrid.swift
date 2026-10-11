import SwiftUI
import HongguoCore

/// 自适应海报网格（发现 / 榜单 / 探索 / 搜索结果 / 相关推荐复用）。
public struct PosterGrid: View {
    let items: [Drama]
    let onSelect: (Drama) -> Void

    public init(_ items: [Drama], onSelect: @escaping (Drama) -> Void) {
        self.items = items
        self.onSelect = onSelect
    }

    @Environment(\.uiCardScale) private var cardScale

    public var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150 * cardScale, maximum: 180 * cardScale), spacing: Spacing.md)],
                spacing: Spacing.md
            ) {
                ForEach(items) { drama in
                    PosterCard(drama)
                        .onTapGesture { onSelect(drama) }
                        .contextMenu {
                            Button("查看详情") { onSelect(drama) }
                            Button("复制标题") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(drama.title, forType: .string)
                            }
                        }
                }
            }
            .padding(Spacing.md)
        }
    }
}
