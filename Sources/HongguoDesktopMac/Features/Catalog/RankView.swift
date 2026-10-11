import SwiftUI
import HongguoCore

/// 发现页（客户端首页，对标 MoonTV 首页样式）：多分区 + 换行网格。
///
/// 布局（对齐参考站首页，不含其左侧导航）：
///  - 顶部 Hero 轮播（热门电影 Top5 大背景图 + 标题/评分，自动轮播）；
///  - 下方多个分区（热门电影 / 热门剧集 / 热门综艺 / 热门短剧 / 热门动漫），
///    每区一张「换行网格」（不左右滑动，放不下直接换行）；
///  - 每区默认展示 18 条，点「展开全部」追加到 54 条；
///  - 豆瓣卡片点击 → 弹「搜索详情」浮层（搜索中 → TVBox 聚合结果 → 可切源播放）。
///
/// 数据源：豆瓣 recent_hot（网关 /api/douban/hot），图片经 image-proxy 防盗链；
/// 短剧区用首个可用 TVBox 源的最新短剧（真实可播）。
public struct RankView: View {
    let onSelect: (Drama) -> Void

    public init(onSelect: @escaping (Drama) -> Void) { self.onSelect = onSelect }

    /// 点击搜索详情浮层的请求（用标题去 TVBox 聚合搜索）。
    @State private var searchRequest: SearchRequest?
    /// Hero 轮播当前下标。
    @State private var heroIndex = 0

    // 各分区数据
    @State private var movies: [CatalogService.DoubanHotItem] = []
    @State private var tvs: [CatalogService.DoubanHotItem] = []
    @State private var varieties: [CatalogService.DoubanHotItem] = []
    @State private var animes: [CatalogService.DoubanHotItem] = []
    @State private var duanjus: [Drama] = []
    @State private var loaded = false

    // 每区「展开全部」
    @State private var expandMovies = false
    @State private var expandTVs = false
    @State private var expandVarieties = false
    @State private var expandAnimes = false
    @State private var heroTimer: Timer?

    private let sectionLimit = 18      // 每区默认条数（多展示一些）
    private let sectionLimitFull = 54  // 展开后条数
    private let columns = [GridItem(.adaptive(minimum: 128, maximum: 150), spacing: Spacing.md)]

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                if !movies.isEmpty { heroSection }
                doubanSection("热门电影", items: movies, expanded: $expandMovies, kind: .movie)
                doubanSection("热门剧集", items: tvs, expanded: $expandTVs, kind: .tv)
                doubanSection("热门综艺", items: varieties, expanded: $expandVarieties, kind: .variety)
                duanjuSection
                doubanSection("热门动漫", items: animes, expanded: $expandAnimes, kind: .anime)
            }
            .padding(.bottom, Spacing.xl)
        }
        .background(Brand.background)
        .task { await loadAll() }
        .sheet(item: $searchRequest) { req in
            SearchDetailSheet(request: req, onPlay: { drama in
                searchRequest = nil
                onSelect(drama)
            }, onClose: { searchRequest = nil })
        }
    }

    // MARK: - Hero 轮播（热门电影 Top5，自动轮播）
    private var heroSection: some View {
        let items = Array(movies.prefix(5))
        return TabView(selection: $heroIndex) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                ZStack(alignment: .bottomLeading) {
                    // 大背景海报
                    if let url = proxied(item.poster) {
                        CoverImage(url, title: item.title)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    } else {
                        Brand.placeholder
                    }
                    // 渐变 + 文案
                    LinearGradient(colors: [.clear, .black.opacity(0.75)],
                                   startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 6) {
                        Spacer()
                        Text(item.title)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        HStack(spacing: 10) {
                            if !item.rate.isEmpty {
                                Label(item.rate, systemImage: "star.fill")
                                    .foregroundStyle(.yellow)
                            }
                            if !item.year.isEmpty { Text(item.year) }
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        Button {
                            openDouban(item)
                        } label: {
                            Label("搜索播放", systemImage: "play.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 16).padding(.vertical, 7)
                                .background(Capsule().fill(.white))
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .padding(Spacing.xl)
                }
                .contentShape(Rectangle())
                .onTapGesture { openDouban(item) }
                .tag(idx)
            }
        }
        .tabViewStyle(.automatic)
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
        .onAppear { startHeroTimer(count: items.count) }
    }

    private func startHeroTimer(count: Int) {
        guard count > 1, heroTimer == nil else { return }
        heroTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in
                withAnimation { heroIndex = (heroIndex + 1) % count }
            }
        }
    }

    // MARK: - 豆瓣分区（换行网格，不横滑）
    private enum DoubanKind { case movie, tv, variety, anime }

    private func doubanSection(_ title: String,
                               items: [CatalogService.DoubanHotItem],
                               expanded: Binding<Bool>,
                               kind: DoubanKind) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(Brand.label)
                Spacer()
                if items.count > sectionLimit {
                    Button(expanded.wrappedValue ? "收起" : "展开全部") {
                        withAnimation { expanded.wrappedValue.toggle() }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.accent)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.lg)

            if items.isEmpty {
                Text(loaded ? "暂无数据" : "加载中…")
                    .font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                let shown = expanded.wrappedValue ? items : Array(items.prefix(sectionLimit))
                LazyVGrid(columns: columns, spacing: Spacing.lg) {
                    ForEach(shown) { item in
                        doubanCard(item)
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
        }
    }

    private func doubanCard(_ item: CatalogService.DoubanHotItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay { CoverImage(proxied(item.poster), title: item.title) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Brand.separator.opacity(0.6), lineWidth: 0.5))
                .overlay(alignment: .bottomTrailing) {
                    if !item.rate.isEmpty {
                        Text(item.rate)
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.black.opacity(0.6)).clipShape(Capsule()).padding(6)
                    }
                }
            Text(item.title)
                .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                .foregroundStyle(Brand.label).help(item.title)
            Text(item.year.isEmpty ? " " : item.year)
                .font(.system(size: 12)).foregroundStyle(Brand.secondaryLabel)
        }
        .contentShape(Rectangle())
        .onTapGesture { openDouban(item) }
        .help("\(item.title)（点击搜索可播放源）")
    }

    // MARK: - 短剧分区（真实可播 Drama）
    private var duanjuSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("热门短剧").font(.system(size: 20, weight: .bold)).foregroundStyle(Brand.label)
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)

            if duanjus.isEmpty {
                Text(loaded ? "暂无数据" : "加载中…")
                    .font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVGrid(columns: columns, spacing: Spacing.lg) {
                    ForEach(duanjus) { d in
                        PosterCard(d)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(d) }   // 短剧直接可播，走详情
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
        }
    }

    // MARK: - 数据加载
    private func loadAll() async {
        let svc = CatalogService.shared
        async let m = (try? svc.doubanHot(kind: "movie", category: "热门", type: "全部", limit: sectionLimitFull, start: 0)) ?? []
        async let t = (try? svc.doubanHot(kind: "tv", category: "tv", type: "tv", limit: sectionLimitFull, start: 0)) ?? []
        async let v = (try? svc.doubanHot(kind: "tv", category: "show", type: "show", limit: sectionLimitFull, start: 0)) ?? []
        async let a = (try? svc.doubanHot(kind: "tv", category: "tv", type: "动画", limit: sectionLimitFull, start: 0)) ?? []
        async let d = SourceManager.shared.duanjuRecommends(limit: sectionLimit)
        let (mm, tt, vv, aa, dd) = await (m, t, v, a, d)
        movies = dedup(mm); tvs = dedup(tt); varieties = dedup(vv); animes = dedup(aa); duanjus = dd
        loaded = true
    }

    private func dedup(_ list: [CatalogService.DoubanHotItem]) -> [CatalogService.DoubanHotItem] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.id).inserted }
    }

    private func proxied(_ poster: String) -> URL? {
        guard !poster.isEmpty else { return nil }
        let enc = poster.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? poster
        return URL(string: "\(AppConfig.gatewayBaseURL)/api/image-proxy?url=\(enc)")
    }

    /// 豆瓣卡片点击：弹「搜索详情」浮层，用标题去 TVBox 聚合搜索可播放源。
    private func openDouban(_ item: CatalogService.DoubanHotItem) {
        searchRequest = SearchRequest(title: item.title, year: item.year, poster: item.poster, rate: item.rate)
    }
}

// MARK: - 搜索详情请求模型
struct SearchRequest: Identifiable {
    let id = UUID()
    let title: String
    let year: String
    let poster: String
    let rate: String
}
