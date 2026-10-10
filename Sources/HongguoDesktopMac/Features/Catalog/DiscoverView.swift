import SwiftUI
import HongguoCore

/// 发现页（MoonTVPlus 首页形式）：豆瓣热门分类横排 + 采集源热播短剧横排。
///
/// 数据与图片策略（对齐 MoonTVPlus 调研结论）：
///  - 热门电影/剧集/综艺：豆瓣 `recent_hot` 接口（网关 /api/douban/hot 直连拉取）；
///  - 图片：豆瓣海报（doubanio.com），经网关 image-proxy 解决 Referer 防盗链；
///  - 热播短剧：采集源（maccms）最新短剧，真实可播，点击直接进详情播放；
///  - 缓存：1 小时进程内缓存（对齐 MoonTVPlus localStorage 1h）。
public struct DiscoverView: View {
    let onSelect: (Drama) -> Void

    @State private var hotMovies: [CatalogService.DoubanHotItem] = []
    @State private var hotTvShows: [CatalogService.DoubanHotItem] = []
    @State private var hotVariety: [CatalogService.DoubanHotItem] = []
    @State private var hotDuanju: [Drama] = []
    @State private var isLoading = true

    public init(onSelect: @escaping (Drama) -> Void) { self.onSelect = onSelect }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if isLoading && hotMovies.isEmpty && hotDuanju.isEmpty {
                    ProgressView("加载中…").frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    if !hotDuanju.isEmpty {
                        dramaRow(title: "热播短剧", items: hotDuanju)
                    }
                    doubanRow(title: "热门电影", items: hotMovies)
                    doubanRow(title: "热门剧集", items: hotTvShows)
                    doubanRow(title: "热门综艺", items: hotVariety)
                }
            }
            .padding(Spacing.lg)
        }
        .task { await load() }
        .refreshable { await load(force: true) }
    }

    /// 采集源短剧横排（真实可播）。
    private func dramaRow(title: String, items: [Drama]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).font(Typography.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    ForEach(items) { d in
                        PosterCard(d)
                            .frame(width: 130)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(d) }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// 豆瓣分类横排（海报 + 评分；点击提示去视频源搜索）。
    private func doubanRow(title: String, items: [CatalogService.DoubanHotItem]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).font(Typography.headline)
            if items.isEmpty {
                Text("暂无数据").font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        ForEach(items) { item in
                            doubanCard(item)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func doubanCard(_ item: CatalogService.DoubanHotItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    CoverImage(proxiedPosterURL(item.poster), title: item.title)
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Brand.separator.opacity(0.6), lineWidth: 0.5))
                .overlay(alignment: .topTrailing) {
                    if !item.rate.isEmpty {
                        Text(item.rate)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.black.opacity(0.6))
                            .clipShape(Capsule())
                            .padding(6)
                    }
                }
            Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1).foregroundStyle(Brand.label).help(item.title)
            Text(item.year.isEmpty ? " " : item.year).font(.system(size: 12)).foregroundStyle(Brand.secondaryLabel)
        }
        .frame(width: 130, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { searchAndOpen(item.title) }
        .help("\(item.title)（点击到视频源搜索播放）")
    }

    /// 豆瓣图经网关 image-proxy（解决 Referer 防盗链）。
    private func proxiedPosterURL(_ poster: String) -> URL? {
        guard !poster.isEmpty else { return nil }
        let enc = poster.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? poster
        return URL(string: "\(AppConfig.gatewayBaseURL)/api/image-proxy?url=\(enc)")
    }

    /// 豆瓣条目点击：聚合采集源搜同名，命中第一个可播结果直接打开。
    private func searchAndOpen(_ title: String) {
        Task {
            let results = await SourceManager.shared.aggregateSearch(query: title)
            if let first = results.first {
                await MainActor.run { onSelect(first) }
            } else {
                AppLog.log(.app, "发现页豆瓣条目《\(title)》在采集源未搜到可播资源")
            }
        }
    }

    private func load(force: Bool = false) async {
        isLoading = true
        let svc = CatalogService.shared
        async let movies = (try? svc.doubanHot(kind: "movie", category: "热门", type: "全部")) ?? []
        async let tv = (try? svc.doubanHot(kind: "tv", category: "tv", type: "tv")) ?? []
        async let show = (try? svc.doubanHot(kind: "tv", category: "show", type: "show")) ?? []
        async let duanju = SourceManager.shared.duanjuRecommends()
        let (m, t, s, d) = await (movies, tv, show, duanju)
        hotMovies = m; hotTvShows = t; hotVariety = s; hotDuanju = d
        isLoading = false
    }
}
