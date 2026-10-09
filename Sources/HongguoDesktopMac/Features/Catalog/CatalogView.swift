import SwiftUI
import HongguoCore

public enum SidebarItem: String, CaseIterable, Identifiable {
    case discover, rank, explore, favorite, history, settings
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .discover: return "发现"
        case .rank: return "排行榜"
        case .explore: return "探索"
        case .favorite: return "收藏"
        case .history: return "历史"
        case .settings: return "设置"
        }
    }
    public var icon: String {
        switch self {
        case .discover: return "sparkles"
        case .rank: return "chart.bar.fill"
        case .explore: return "compass"
        case .favorite: return "heart"
        case .history: return "clock"
        case .settings: return "gearshape"
        }
    }
    /// 对应网关 catalog 路径（收藏/历史在 M4 接入本地库，此处先走 Web 列表）。
    var catalogPath: String? {
        switch self {
        case .discover: return "/"
        case .rank: return "/rank"
        case .explore: return "/explore"
        default: return nil
        }
    }
}

public struct CatalogView: View {
    @StateObject private var service = CatalogService.shared
    @State private var selection: SidebarItem = .discover
    @State private var query = ""
    @State private var selected: Drama?
    @State private var detail: DramaDetail?
    @State private var showPlayer = false

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .navigationTitle("红果短剧")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                searchBar
                content
            }
            .navigationTitle(selection.title)
            .frame(minWidth: 640, minHeight: 480)
        }
        .onChange(of: selection) { _, _ in Task { await reload() } }
        .task { await reload() }
        .sheet(item: $selected) { drama in
            DetailSheet(drama: drama, onPlay: { d in
                selected = nil
                Task { detail = await service.detail(id: d.id) }
                showPlayer = true
            })
        }
        .sheet(isPresented: $showPlayer) {
            if let detail { PlayerView(detail: detail) }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("搜索短剧", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await service.search(query) } }
            Button("搜索") { Task { await service.search(query) } }
            if service.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    @ViewBuilder
    private var content: some View {
        if let err = service.errorMessage {
            VStack { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange); Text(err) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if service.items.isEmpty && !service.isLoading {
            ContentUnavailableView("暂无内容", systemImage: "tray", description: Text("换个分类或搜索试试"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: Spacing.md)], spacing: Spacing.md) {
                    ForEach(service.items) { drama in
                        PosterCard(drama)
                            .onTapGesture { selected = drama }
                            .contextMenu { Button("详情") { selected = drama } }
                    }
                }
                .padding(Spacing.md)
            }
        }
    }

    private func reload() async {
        if let path = selection.catalogPath {
            await service.loadCatalog(path: path)
        }
    }
}

/// 详情弹窗（M5 接入播放器）。
struct DetailSheet: View {
    let drama: Drama
    let onPlay: (Drama) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text(drama.title).font(Typography.title)
                Spacer()
                Button("关闭") { /* sheet 由父级控制 */ }
            }
            if let desc = drama.description {
                Text(desc).font(Typography.body).foregroundStyle(Brand.secondaryLabel)
            }
            if let cnt = drama.episodeCount { Text("共 \(cnt) 集").font(Typography.caption) }
            Button { onPlay(drama) } label: {
                Label("立即播放", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.pink)
            Spacer()
        }
        .padding(Spacing.lg)
        .frame(width: 480, height: 360)
    }
}
