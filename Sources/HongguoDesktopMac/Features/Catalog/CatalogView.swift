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
}

public struct CatalogView: View {
    @StateObject private var service = CatalogService.shared
    @State private var selection: SidebarItem = .discover
    @State private var query = ""
    @State private var searchResults: [Drama]?
    @State private var isSearching = false
    @State private var searchError: String?

    @State private var selected: Drama?
    @State private var playerDetail: PlayerPayload?

    public init() {}

    // 各分区浏览配置
    private var discoverConfig: BrowseConfig {
        BrowseConfig(
            title: "发现",
            chips: BrowseCategory.allCases.map { BrowseChip(id: $0.id, title: $0.title) },
            defaultPath: "/",
            chipPath: { BrowseCategory(rawValue: $0.id)?.path ?? "/" },
            featuredPath: "/hot"
        )
    }
    private var rankConfig: BrowseConfig {
        BrowseConfig(
            title: "排行榜",
            chips: RankTab.allCases.map { BrowseChip(id: $0.id, title: $0.title) },
            defaultPath: RankTab.hot.path,
            chipPath: { RankTab(rawValue: $0.id)?.path ?? "/rank" }
        )
    }
    private var exploreConfig: BrowseConfig {
        BrowseConfig(
            title: "探索",
            chips: BrowseCategory.allCases.map { BrowseChip(id: $0.id, title: $0.title) },
            defaultPath: "/explore",
            chipPath: { BrowseCategory(rawValue: $0.id)?.path ?? "/explore" }
        )
    }

    public var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .navigationTitle("红果短剧")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            Group {
                if searchResults != nil || isSearching {
                    searchContent
                } else {
                    sectionContent
                }
            }
            .frame(minWidth: 640, minHeight: 480)
            .searchable(text: $query, prompt: "搜索短剧、剧名")
            .onSubmit(of: .search) { Task { await runSearch() } }
            .onChange(of: query) { _, new in if new.isEmpty { searchResults = nil } }
            .navigationTitle(showTitle)
        }
        .task {
            GatewayController.shared.start()
            BossKeyManager.shared.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hongguoOpenDrama)) { note in
            if let d = note.object as? Drama { selected = d }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hongguoPlayDetail)) { note in
            if let payload = note.object as? PlayerPayload {
                selected = nil
                playerDetail = payload
            }
        }
        .sheet(item: $selected) { drama in
            DetailView(drama: drama) { detail, idx in
                selected = nil
                playerDetail = PlayerPayload(id: detail.drama.id, detail: detail, index: idx)
            }
        }
        .sheet(item: $playerDetail) { payload in
            PlayerView(detail: payload.detail, startIndex: payload.index)
        }
    }

    private var showTitle: String {
        if searchResults != nil || isSearching { return "搜索" }
        return selection.title
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selection {
        case .discover:
            BrowseView(config: discoverConfig, onSelect: openDetail)
        case .rank:
            BrowseView(config: rankConfig, onSelect: openDetail)
        case .explore:
            BrowseView(config: exploreConfig, onSelect: openDetail)
        case .favorite:
            LibraryView(initial: .favorite)
        case .history:
            LibraryView(initial: .history)
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if isSearching {
            LoadingView("搜索中…")
        } else if let error = searchError {
            ErrorView(error, retry: { Task { await runSearch() } })
        } else if let results = searchResults, results.isEmpty {
            EmptyState("未找到相关短剧", systemImage: "magnifyingglass", description: "换个关键词试试")
        } else if let results = searchResults {
            PosterGrid(results, onSelect: openDetail)
        }
    }

    private func openDetail(_ drama: Drama) { selected = drama }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { searchResults = nil; return }
        isSearching = true; searchError = nil
        do {
            searchResults = try await service.search(query: q)
        } catch {
            searchError = "搜索失败：\(error.localizedDescription)"
        }
        isSearching = false
    }
}

/// 播放器入参包装（Identifiable 以便 sheet）。
struct PlayerPayload: Identifiable {
    let id: String
    let detail: DramaDetail
    let index: Int
}
