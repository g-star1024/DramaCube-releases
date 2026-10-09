import SwiftUI
import HongguoCore

/// 浏览分区配置：发现 / 排行榜 / 探索共用同一套网格 + 分页 + 芯片逻辑。
public struct BrowseConfig {
    public let title: String
    public let chips: [BrowseChip]
    public let defaultPath: String
    public let chipPath: (BrowseChip) -> String
    public let featuredPath: String?

    public init(title: String,
                chips: [BrowseChip] = [],
                defaultPath: String,
                chipPath: @escaping (BrowseChip) -> String = { _ in "/" },
                featuredPath: String? = nil) {
        self.title = title
        self.chips = chips
        self.defaultPath = defaultPath
        self.chipPath = chipPath
        self.featuredPath = featuredPath
    }
}

/// 通用浏览视图：顶部可选分类芯片 + 顶部可选「热播」横滑 + 自适应网格 + 分页加载。
public struct BrowseView: View {
    let config: BrowseConfig
    let onSelect: (Drama) -> Void

    @State private var selectedChip: BrowseChip?
    @State private var items: [Drama] = []
    @State private var page = 1
    @State private var isLoading = false
    @State private var error: String?
    @State private var hasMore = true
    @State private var featured: [Drama] = []

    public init(config: BrowseConfig, onSelect: @escaping (Drama) -> Void) {
        self.config = config
        self.onSelect = onSelect
    }

    private var currentPath: String {
        if let chip = selectedChip { return config.chipPath(chip) }
        return config.defaultPath
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !config.chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(config.chips) { chip in
                            CategoryChip(chip.title, isSelected: selectedChip?.id == chip.id) {
                                selectedChip = (selectedChip?.id == chip.id) ? nil : chip
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                }
            }
            Divider()
            content
        }
        .navigationTitle(config.title)
        .task { await initialLoad() }
        .onChange(of: selectedChip) { _, _ in Task { await load(reset: true) } }
    }

    @ViewBuilder
    private var content: some View {
        if let error, items.isEmpty {
            ErrorView(error, retry: { Task { await load(reset: true) } })
        } else if items.isEmpty && !isLoading {
            EmptyState("暂无内容", systemImage: "tray", description: "换个分类或稍后再试")
        } else {
            ScrollView {
                if !featured.isEmpty {
                    // Hero 轮播：大图 + 自动轮换，与网格保持充足留白
                    HeroCarousel(items: Array(featured.prefix(6)), onSelect: onSelect)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.md)
                        .padding(.bottom, Spacing.lg)
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 180), spacing: Spacing.md)],
                    spacing: Spacing.lg
                ) {
                    ForEach(items) { drama in
                        PosterCard(drama)
                            .onTapGesture { onSelect(drama) }
                            .contextMenu {
                                Button("查看详情") { onSelect(drama) }
                            }
                    }
                }
                .padding(.horizontal, Spacing.lg)

                if isLoading {
                    ProgressView().controlSize(.small).padding(Spacing.md)
                } else if hasMore {
                    Button("加载更多") { Task { await load(reset: false) } }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .padding(.bottom, Spacing.lg)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func initialLoad() async {
        if let fp = config.featuredPath {
            featured = (try? await CatalogService.shared.catalog(path: fp)) ?? []
        }
        await load(reset: true)
    }

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        let target = reset ? 1 : page
        isLoading = true
        if reset { error = nil }
        do {
            let fresh = try await CatalogService.shared.catalog(path: currentPath, page: target)
            if reset { items = fresh } else { items.append(contentsOf: fresh) }
            page = target + 1
            hasMore = fresh.count >= 12
        } catch {
            if reset { self.error = "加载失败：\(error.localizedDescription)" }
        }
        isLoading = false
    }
}
