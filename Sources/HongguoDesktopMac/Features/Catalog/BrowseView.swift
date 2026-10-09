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

/// 通用浏览视图：分类芯片 + Hero 轮播 + 海报网格。
///
///  - 触底自动加载下一页（不再需要「加载更多」按钮）；
///  - 网格使用非 Lazy 分行布局，修复「向上滚动内容空白」的 LazyVGrid 回收 bug；
///  - cache-then-network：启动先读本地缓存秒开，再后台刷新并回写。
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
    /// 每行固定 6 个大卡片（用户拍板）。
    @State private var columnCount = 6
    /// 渐进渲染数量：先渲首批，触底再扩，避免大列表一次性渲染卡死主线程。
    @State private var renderCount = 36

    private let renderChunk = 36

    private var currentPath: String {
        if let chip = selectedChip { return config.chipPath(chip) }
        return config.defaultPath
    }

    private var cacheKey: String { "catalog:\(config.title):\(currentPath)" }

    public init(config: BrowseConfig, onSelect: @escaping (Drama) -> Void) {
        self.config = config
        self.onSelect = onSelect
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
                .background(Brand.background)
            }
            Divider()
            content
        }
        .background(Brand.background)
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
                VStack(spacing: Spacing.lg) {
                    if !featured.isEmpty {
                        HeroCarousel(items: Array(featured.prefix(6)), onSelect: onSelect)
                    }
                    posterGrid
                    bottomTrigger
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.lg)
            }
        }
    }

    // MARK: 非 Lazy 网格（分行 HStack，杜绝 LazyVGrid 上滚空白；配合渐进渲染控制开销）
    @ViewBuilder
    private var posterGrid: some View {
        let visible = Array(items.prefix(renderCount))
        let rows = chunked(visible, by: columnCount)
        VStack(alignment: .leading, spacing: Spacing.lg) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(alignment: .top, spacing: Spacing.md) {
                    ForEach(rows[r]) { drama in
                        PosterCard(drama)
                            .onTapGesture { onSelect(drama) }
                            .contextMenu {
                                Button("查看详情") { onSelect(drama) }
                            }
                    }
                }
            }
        }
    }

    /// 触底触发器：先扩渲染窗口，全部渲完后再拉下一页。
    @ViewBuilder
    private var bottomTrigger: some View {
        if isLoading {
            HStack(spacing: Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("正在加载更多…").font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.md)
        } else if renderCount < items.count {
            Color.clear
                .frame(height: 1)
                .onAppear { Task { await renderMore() } }
        } else if hasMore {
            Color.clear
                .frame(height: 1)
                .onAppear { Task { await load(reset: false) } }
        } else if !items.isEmpty {
            Text("已经到底啦 · 共 \(items.count) 部")
                .font(Typography.caption)
                .foregroundStyle(Brand.secondaryLabel)
                .frame(maxWidth: .infinity)
                .padding(Spacing.md)
        }
    }

    private func renderMore() async {
        guard renderCount < items.count else { return }
        try? await Task.sleep(nanoseconds: 100_000_000) // 让一帧先落地
        renderCount = min(items.count, renderCount + renderChunk)
    }

    // MARK: 数据加载

    private func initialLoad() async {
        // 进入加载态：避免缓存未命中时闪「暂无内容」
        isLoading = true
        // 1) 先展示本地缓存（秒开，封面走磁盘图缓）
        if let cached: [Drama] = await DiskCache.shared.read([Drama].self, key: cacheKey), !cached.isEmpty {
            items = cached
        }
        // 2) 轮播：缓存优先，再刷新回写（冷启动失败也不至于空白）
        if let fp = config.featuredPath {
            let fkey = "featured:\(config.title)"
            if let cf: [Drama] = await DiskCache.shared.read([Drama].self, key: fkey), !cf.isEmpty {
                featured = cf
            }
            if let f = try? await CatalogService.shared.catalog(path: fp), !f.isEmpty {
                featured = f
                await DiskCache.shared.write(f, key: fkey)
            }
        }
        // 3) 列表刷新并回写（force：initialLoad 已置 isLoading，避免被并发守卫拦掉）
        await load(reset: true, force: true)
    }

    private func load(reset: Bool, force: Bool = false) async {
        guard force || !isLoading else { return }
        let target = reset ? 1 : page
        isLoading = true
        if reset { error = nil }
        do {
            let fresh = try await CatalogService.shared.catalog(path: currentPath, page: target)
            if reset {
                items = fresh
                renderCount = renderChunk
            } else {
                items.append(contentsOf: fresh)
            }
            page = target + 1
            hasMore = fresh.count >= 12
            await DiskCache.shared.write(items, key: cacheKey)
        } catch {
            if reset { self.error = "加载失败：\(error.localizedDescription)" }
        }
        isLoading = false
    }

    private func chunked(_ list: [Drama], by n: Int) -> [[Drama]] {
        guard n > 0 else { return [list] }
        return stride(from: 0, to: list.count, by: n).map { Array(list[$0..<min($0 + n, list.count)]) }
    }
}
