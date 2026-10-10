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
    /// 发现页大类分段（真人剧/漫剧/AI剧）；传 nil 表示无分段（排行/探索沿用）。
    var segments: [DiscoverSegment]? = nil

    @State private var selectedSegment: DiscoverSegment = .real
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

    /// 当前生效的 chips：漫剧/AI剧分段下隐藏 tag 标签栏（站点无 tag 子路由）。
    private var effectiveChips: [BrowseChip] {
        guard segments != nil else { return config.chips }
        return selectedSegment == .real ? config.chips : []
    }

    private var currentPath: String {
        if let segs = segments, segs.count > 1 {
            switch selectedSegment {
            case .real:
                if let chip = selectedChip { return config.chipPath(chip) }
                return config.defaultPath
            case .comic: return "/category/comic-drama"
            case .ai: return "/category/ai-drama"
            }
        }
        if let chip = selectedChip { return config.chipPath(chip) }
        return config.defaultPath
    }

    private var cacheKey: String {
        let seg = segments != nil ? ":\(selectedSegment.rawValue)" : ""
        return "catalog:\(config.title)\(seg):\(currentPath)"
    }

    public init(config: BrowseConfig, segments: [DiscoverSegment]? = nil, onSelect: @escaping (Drama) -> Void) {
        self.config = config
        self.segments = segments
        self.onSelect = onSelect
        // 默认选中第一个芯片（发现页 tag 分类直接展示，不再停留「全部」）
        _selectedChip = State(initialValue: config.chips.first)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let segs = segments, segs.count > 1 {
                // 大类分段胶囊（真人剧 / 漫剧 / AI剧）
                HStack(spacing: 0) {
                    ForEach(segs) { seg in
                        Button {
                            if selectedSegment != seg { selectedSegment = seg }
                        } label: {
                            Text(seg.title)
                                .font(.system(size: 13, weight: selectedSegment == seg ? .semibold : .regular))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule().fill(selectedSegment == seg ? Color.black.opacity(0.85) : Color.clear)
                                )
                                .foregroundStyle(selectedSegment == seg ? .white : Brand.secondaryLabel)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Capsule().fill(Brand.chipFill))
                .overlay(Capsule().strokeBorder(Brand.separator.opacity(0.5), lineWidth: 0.5))
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            if !effectiveChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(effectiveChips) { chip in
                            CategoryChip(chip.title, isSelected: selectedChip?.id == chip.id) {
                                // 发现页 tag 分类：始终选中其一，不允许取消回「全部」
                                if selectedChip?.id != chip.id { selectedChip = chip }
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
        // 集数懒回填：渲染窗口扩大时补当前可见卡片缺失的集数（榜单/搜索/首页精选源数据无集数）
        .task(id: renderCount) { await backfillCounts() }
        .onChange(of: selectedChip) { _, _ in Task { await load(reset: true) } }
        .onChange(of: selectedSegment) { _, _ in Task { await load(reset: true) } }
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
    //
    // ⚠️ 硬上限：非 Lazy 布局会把全部行都建进视图树，卡片无限增长 = 内存/布局爆炸。
    // v1.0.5 实测无人操作自动连刷 31 页（1100+ 卡）直接卡死。因此 items 最多保留
    // 240 部（40 行）；更早的被裁掉后如需回看，靠「回到顶部」重新加载第一页即可
    //（CoverImage 走磁盘缓存，重载图片毫秒级出图）。
    private let maxWindowItems = 240

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
    /// 注意：非 Lazy 网格会把「已经到底啦」等尾部元素也提前排版，
    /// 仅用 onAppear 会在首屏就连续触发（v1.0.5 无人操作自动连刷 31 页的根因），
    /// 因此必须用 GeometryReader 判断哨兵真正进入可视区才触发。
    @ViewBuilder
    private var bottomTrigger: some View {
        if isLoading {
            HStack(spacing: Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("正在加载更多…").font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.md)
        } else if renderCount < items.count || hasMore {
            GeometryReader { geo in
                Color.clear
                    .onAppear { checkSentinel(geo) }
                    .onChange(of: geo.frame(in: .global).minY) { _, _ in checkSentinel(geo) }
            }
            .frame(height: 1)
        } else if !items.isEmpty {
            Text("已经到底啦 · 共 \(items.count) 部")
                .font(Typography.caption)
                .foregroundStyle(Brand.secondaryLabel)
                .frame(maxWidth: .infinity)
                .padding(Spacing.md)
        }
    }

    /// 哨兵进入可视区（屏幕高度 + 600pt 预取余量）才推进渲染/加载。
    private func checkSentinel(_ geo: GeometryProxy) {
        let y = geo.frame(in: .global).minY
        let screenH = NSScreen.main?.visibleFrame.height ?? 900
        guard y < screenH + 600, y > -2000 else { return }
        Task {
            if renderCount < items.count {
                await renderMore()
            } else if hasMore {
                await load(reset: false)
            }
        }
    }

    private func renderMore() async {
        guard renderCount < items.count else { return }
        try? await Task.sleep(nanoseconds: 100_000_000) // 让一帧先落地
        renderCount = min(items.count, renderCount + renderChunk)
    }

    /// 集数回填：只补当前渲染窗口 + 轮播（不回填未加载的条目，控制流量）。
    private func backfillCounts() async {
        var candidates = Array(items.prefix(max(renderCount, renderChunk)))
        candidates.append(contentsOf: featured.prefix(6))
        await CountBackfiller.shared.backfill(candidates) { id, count in
            if let i = items.firstIndex(where: { $0.id == id }) {
                items[i] = items[i].withEpisodeCount(count)
            }
            if let i = featured.firstIndex(where: { $0.id == id }) {
                featured[i] = featured[i].withEpisodeCount(count)
            }
        }
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
                .filter { !HongguoClient.isActorCard($0) } // 兜底过滤演员卡（缓存/旧路径也可能混入）
            if reset {
                items = fresh
                renderCount = renderChunk
            } else {
                items.append(contentsOf: fresh)
                // 窗口硬上限：超出后从顶部裁掉最旧的，保证视图树规模可控
                if items.count > maxWindowItems {
                    items.removeFirst(items.count - maxWindowItems)
                }
            }
            page = target + 1
            hasMore = fresh.count >= 12
            AppLog.log(.app, "列表[\(config.title)] 第\(target)页 +\(fresh.count)部，窗口 \(items.count) 部")
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
