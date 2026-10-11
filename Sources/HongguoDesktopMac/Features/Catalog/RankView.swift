import SwiftUI
import HongguoCore

/// 发现页（客户端首页，对标 MoonTV 首页样式）：Hero 轮播 + 多分区换行网格。
///
/// 样式与视频源页统一：轮播用 HeroCarousel、卡片用 PosterCard（封面 3:4 + 标题 + 集数/年份）。
///
/// 分区（真实有数据的才展示）：
///  - 热门电影 / 热门剧集 / 热门综艺：豆瓣 recent_hot（网关 /api/douban/hot）；
///  - 热门动漫：哔哩哔哩番剧榜（网关 /api/bilibili/bangumi）。
///  - 短剧区：豆瓣/B站均无真实短剧榜，已移除。
///
/// 缓存：各分区 cache-then-network（先秒显缓存 → 后台静默刷新 → 回写），
/// TTL 取设置中心 cacheMaxAgeMinutes（默认 6 小时），不再每次打开转圈。
///
/// 豆瓣卡片点击 → 弹详情浮层（详情秒开，源后台异步流式补）。
public struct RankView: View {
    let onSelect: (Drama) -> Void

    public init(onSelect: @escaping (Drama) -> Void) { self.onSelect = onSelect }

    @State private var searchRequest: SearchRequest?

    @State private var movies: [CatalogService.DoubanHotItem] = []
    @State private var tvs: [CatalogService.DoubanHotItem] = []
    @State private var varieties: [CatalogService.DoubanHotItem] = []
    @State private var animes: [CatalogService.DoubanHotItem] = []
    @State private var loaded = false

    @State private var expandMovies = false
    @State private var expandTVs = false
    @State private var expandVarieties = false
    @State private var expandAnimes = false

    private let sectionLimit = 18
    private let sectionLimitFull = 54
    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 160), spacing: Spacing.md)]

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                if !heroItems.isEmpty {
                    HeroCarousel(items: heroItems, onSelect: heroSelect)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.md)
                }
                doubanSection("热门电影", items: movies, expanded: $expandMovies, kind: .movie)
                doubanSection("热门剧集", items: tvs, expanded: $expandTVs, kind: .tv)
                doubanSection("热门综艺", items: varieties, expanded: $expandVarieties, kind: .variety)
                doubanSection("热门动漫", items: animes, expanded: $expandAnimes, kind: .anime)
            }
            .padding(.bottom, Spacing.xl)
        }
        .background(Brand.background)
        .task { await loadAll() }
        .sheet(item: $searchRequest) { req in
            // 详情浮层自管播放（点源即播，发播放通知开播放器，不再回调详情页）
            SearchDetailSheet(request: req, onClose: { searchRequest = nil })
        }
    }

    // MARK: - Hero 轮播（取热门电影 Top6，复用视频源页 HeroCarousel）
    private var heroItems: [Drama] {
        Array(movies.prefix(6)).map { $0.toDrama() }
    }
    private func heroSelect(_ drama: Drama) {
        // Hero 卡片点击也走「详情秒开」浮层（豆瓣 id 已编进 Drama.id）
        if let item = movies.first(where: { "douban|movie|\($0.id)" == drama.id }) {
            openDouban(item, kind: .movie)
        }
    }

    // MARK: - 分区（换行网格，不横滑）
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
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(shown) { item in
                        // 复用视频源页 PosterCard 样式：封面 3:4 + 标题 + 副信息
                        PosterCard(item.toDrama())
                            .overlay(alignment: .bottomTrailing) { rateBadge(item.rate) }
                            .contentShape(Rectangle())
                            .onTapGesture { openDouban(item, kind: kind) }
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
        }
    }

    private func rateBadge(_ rate: String) -> some View {
        Group {
            if !rate.isEmpty {
                Text(rate)
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.black.opacity(0.6)).clipShape(Capsule())
                    .padding(6)
            }
        }
    }

    // MARK: - 数据加载（cache-then-network：先秒显缓存，后台静默刷新）
    private func loadAll() async {
        // 1) 先读缓存秒显（不转圈）
        let ttl = AppSettings.shared.cacheMaxAgeSeconds
        async let cm = readCache("rank.movie", ttl: ttl)
        async let ct = readCache("rank.tv", ttl: ttl)
        async let cv = readCache("rank.variety", ttl: ttl)
        async let ca = readCache("rank.anime", ttl: ttl)
        let (cmv, ctv, cvv, cav) = await (cm, ct, cv, ca)
        if let v = cmv { movies = v }
        if let v = ctv { tvs = v }
        if let v = cvv { varieties = v }
        if let v = cav { animes = v }
        loaded = true   // 有缓存即认为已展示，无缓存分区下面网络补

        // 2) 后台静默刷新（网络），回写缓存
        async let m = fetchMovie()
        async let t = fetchTV()
        async let v = fetchVariety()
        async let a = fetchAnime()
        let (mm, tt, vv, aa) = await (m, t, v, a)
        if !mm.isEmpty { movies = dedup(mm); await writeCache(mm, "rank.movie") }
        if !tt.isEmpty { tvs = dedup(tt); await writeCache(tt, "rank.tv") }
        if !vv.isEmpty { varieties = dedup(vv); await writeCache(vv, "rank.variety") }
        if !aa.isEmpty { animes = dedup(aa); await writeCache(aa, "rank.anime") }
        loaded = true
    }

    private func fetchMovie() async -> [CatalogService.DoubanHotItem] {
        (try? await CatalogService.shared.doubanHot(kind: "movie", category: "热门", type: "全部", limit: sectionLimitFull, start: 0)) ?? []
    }
    private func fetchTV() async -> [CatalogService.DoubanHotItem] {
        (try? await CatalogService.shared.doubanHot(kind: "tv", category: "tv", type: "tv", limit: sectionLimitFull, start: 0)) ?? []
    }
    private func fetchVariety() async -> [CatalogService.DoubanHotItem] {
        (try? await CatalogService.shared.doubanHot(kind: "tv", category: "show", type: "show", limit: sectionLimitFull, start: 0)) ?? []
    }
    private func fetchAnime() async -> [CatalogService.DoubanHotItem] {
        (try? await CatalogService.shared.bilibiliBangumi(limit: sectionLimitFull)) ?? []
    }

    private func readCache(_ key: String, ttl: TimeInterval) async -> [CatalogService.DoubanHotItem]? {
        // 读缓存：新鲜或过期都先返回用于秒显（过期由后台网络刷新覆盖）
        let (value, _) = await DiskCache.shared.readFresh([CatalogService.DoubanHotItem].self, key: key, maxAge: ttl)
        return value
    }
    private func writeCache(_ items: [CatalogService.DoubanHotItem], _ key: String) async {
        await DiskCache.shared.write(items, key: key)
    }

    private func dedup(_ list: [CatalogService.DoubanHotItem]) -> [CatalogService.DoubanHotItem] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.id).inserted }
    }

    /// 豆瓣卡片点击：弹详情浮层（详情秒开 + 源后台异步流式补 + 简介异步）。
    private func openDouban(_ item: CatalogService.DoubanHotItem, kind: DoubanKind) {
        let kindStr: String
        switch kind {
        case .movie: kindStr = "movie"
        case .tv, .variety: kindStr = "tv"
        case .anime: kindStr = "anime"   // B站番剧，无豆瓣简介
        }
        searchRequest = SearchRequest(
            doubanId: item.id, kind: kindStr,
            title: item.title, year: item.year, poster: item.poster, rate: item.rate
        )
    }
}

// MARK: - 搜索详情请求模型
struct SearchRequest: Identifiable {
    let id = UUID()
    let doubanId: String   // 豆瓣条目 id（拉简介用）；anime 时为 B站 season_id
    let kind: String       // movie / tv / anime
    let title: String
    let year: String
    let poster: String
    let rate: String
}

// MARK: - DoubanHotItem → Drama（复用 PosterCard/HeroCarousel）
extension CatalogService.DoubanHotItem {
    /// 包成 Drama 以复用 PosterCard/HeroCarousel。id 带 douban|<kind>|<id> 前缀（Hero 点击回查用）。
    func toDrama(kind: String = "movie") -> Drama {
        Drama(
            id: "douban|\(kind)|\(id)",
            title: title,
            coverURL: proxiedPoster,
            episodeCount: nil,
            updateStatus: year.isEmpty ? nil : year
        )
    }
    /// 封面经网关 image-proxy 防盗链。
    var proxiedPoster: String? {
        guard !poster.isEmpty else { return nil }
        let enc = poster.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? poster
        return "\(AppConfig.gatewayBaseURL)/api/image-proxy?url=\(enc)"
    }
}
