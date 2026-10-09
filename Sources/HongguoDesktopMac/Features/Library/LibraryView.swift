import SwiftUI
import HongguoCore

/// 个人库：收藏 + 历史（含播放进度 / 秒级续播入口）。
public struct LibraryView: View {
    public enum Segment: String, CaseIterable, Identifiable {
        case favorite, history
        public var id: String { rawValue }
        var title: String {
            switch self { case .favorite: return "收藏"; case .history: return "历史" }
        }
    }

    let initial: Segment
    @State private var segment: Segment

    public init(initial: Segment = .favorite) {
        self.initial = initial
        _segment = State(initialValue: initial)
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            Divider()
            if segment == .favorite {
                FavoriteListView()
            } else {
                HistoryListView()
            }
        }
        .navigationTitle(segment.title)
        .frame(minWidth: 640, minHeight: 480)
    }
}

/// 收藏列表。
struct FavoriteListView: View {
    @State private var items: [FavoriteItem] = []

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                EmptyState("还没有收藏", systemImage: "heart",
                           description: "在详情页点击「收藏」，喜欢的内容会在这里")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150, maximum: 180), spacing: Spacing.md)],
                        spacing: Spacing.md
                    ) {
                        ForEach(items) { item in
                            PosterCard(Drama(id: item.dramaId, title: item.title, coverURL: item.coverURL))
                                .onTapGesture { open(item) }
                                .contextMenu {
                                    Button("查看详情") { open(item) }
                                    Button("取消收藏", role: .destructive) { remove(item) }
                                }
                        }
                    }
                    .padding(Spacing.md)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .hongguoLibraryChanged)) { _ in reload() }
    }

    private func reload() { items = Repository.shared.favorites() }

    private func open(_ item: FavoriteItem) {
        NotificationCenter.default.post(
            name: .hongguoOpenDrama,
            object: Drama(id: item.dramaId, title: item.title, coverURL: item.coverURL)
        )
    }

    private func remove(_ item: FavoriteItem) {
        Repository.shared.removeFavorite(dramaId: item.dramaId)
        reload()
    }
}

/// 历史 / 播放进度列表。
struct HistoryListView: View {
    @State private var items: [HistoryItem] = []

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                EmptyState("还没有观看记录", systemImage: "clock",
                           description: "播放过的短剧会自动记录进度，可从此续播")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(items) { item in
                        HistoryRow(item: item)
                    }
                    .onDelete { offsets in
                        for i in offsets { Repository.shared.removeHistory(items[i]) }
                        reload()
                    }
                }
                .toolbar {
                    ToolbarItem {
                        Button("清空") { Repository.shared.clearHistory(); reload() }
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .hongguoLibraryChanged)) { _ in reload() }
    }

    private func reload() { items = Repository.shared.history() }
}

/// 单条历史行：封面 + 标题 + 集数 + 进度 + 续播。
struct HistoryRow: View {
    let item: HistoryItem

    var body: some View {
        Button { resume() } label: {
            HStack(spacing: Spacing.md) {
                Group {
                    if let urlStr = item.coverURL, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            case .failure: Color.gray
                            default: ProgressView()
                            }
                        }
                    } else { Color.gray }
                }
                .frame(width: 60, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(item.title).font(Typography.body).foregroundStyle(Brand.label).lineLimit(1)
                    Text(item.episodeTitle).font(Typography.caption).foregroundStyle(Brand.secondaryLabel).lineLimit(1)
                    if item.duration > 0 {
                        ProgressView(value: min(item.position, item.duration), total: item.duration)
                            .tint(Brand.pink)
                        Text("看到 \(HongguoFormat.duration(item.position)) / \(HongguoFormat.duration(item.duration))")
                            .font(.caption2).foregroundStyle(Brand.secondaryLabel)
                    } else {
                        Text("已观看").font(.caption2).foregroundStyle(Brand.secondaryLabel)
                    }
                    Text(HongguoFormat.relative(item.updatedAt))
                        .font(.caption2).foregroundStyle(Brand.secondaryLabel)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Brand.pink)
            }
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func resume() {
        Task {
            guard let detail = try? await CatalogService.shared.detail(id: item.dramaId) else { return }
            let idx = detail.episodes.firstIndex(where: { $0.id == item.episodeId }) ?? 0
            NotificationCenter.default.post(name: .hongguoPlayDetail, object: PlayerPayload(id: detail.drama.id, detail: detail, index: idx))
        }
    }
}

extension Notification.Name {
    static let hongguoLibraryChanged = Notification.Name("hongguoLibraryChanged")
    static let hongguoPlayDetail = Notification.Name("hongguoPlayDetail")
}
