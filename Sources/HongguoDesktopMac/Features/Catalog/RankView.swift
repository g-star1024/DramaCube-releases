import SwiftUI
import HongguoCore

/// 排行榜（MoonTVPlus 豆瓣热门形式）：分榜切换 + 网格海报 + 排名角标。
///
/// 数据源（对齐 MoonTVPlus 调研）：
///  - 热门电影/剧集/综艺：豆瓣 recent_hot 接口（网关 /api/douban/hot）；
///  - 热门短剧：采集源最新短剧（真实可播）；
///  - 图片：豆瓣海报经 image-proxy 防盗链；短剧用源站封面。
public struct RankView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case movie, tv, variety, duanju
        public var id: String { rawValue }
        var title: String {
            switch self {
            case .movie: return "热门电影"
            case .tv: return "热门剧集"
            case .variety: return "热门综艺"
            case .duanju: return "热门短剧"
            }
        }
    }

    let onSelect: (Drama) -> Void

    @State private var tab: Tab = .duanju
    @State private var doubanItems: [CatalogService.DoubanHotItem] = []
    @State private var duanjuItems: [Drama] = []
    @State private var isLoading = false

    public init(onSelect: @escaping (Drama) -> Void) { self.onSelect = onSelect }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // 分榜胶囊
            HStack(spacing: 0) {
                ForEach(Tab.allCases) { t in
                    Button { if tab != t { tab = t } } label: {
                        Text(t.title)
                            .font(.system(size: 13, weight: tab == t ? .semibold : .regular))
                            .padding(.horizontal, 18).padding(.vertical, 7)
                            .background(Capsule().fill(tab == t ? Color.black.opacity(0.85) : Color.clear))
                            .foregroundStyle(tab == t ? .white : Brand.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)

            if isLoading {
                ProgressView("加载中…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tab == .duanju {
                duanjuGrid
            } else {
                doubanGrid
            }
        }
        .task(id: tab) { await load() }
    }

    /// 豆瓣榜单网格（排名角标 + 评分）。
    private var doubanGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 160), spacing: Spacing.md)], spacing: Spacing.lg) {
                ForEach(Array(doubanItems.enumerated()), id: \.element.id) { idx, item in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Color.clear
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            .overlay { CoverImage(proxied(item.poster), title: item.title) }
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Brand.separator.opacity(0.6), lineWidth: 0.5))
                            .overlay(alignment: .topLeading) { rankBadge(idx + 1) }
                            .overlay(alignment: .bottomTrailing) {
                                if !item.rate.isEmpty {
                                    Text(item.rate).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(.black.opacity(0.6)).clipShape(Capsule()).padding(6)
                                }
                            }
                        Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1).foregroundStyle(Brand.label).help(item.title)
                        Text(item.year.isEmpty ? " " : item.year).font(.system(size: 12)).foregroundStyle(Brand.secondaryLabel)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { searchAndOpen(item.title) }
                    .help("\(item.title)（点击到视频源搜索播放）")
                }
            }
            .padding(Spacing.lg)
        }
    }

    /// 采集源短剧榜单网格（排名角标，真实可播）。
    private var duanjuGrid: some View {
        ScrollView {
            if duanjuItems.isEmpty {
                Text("暂无数据").font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 160), spacing: Spacing.md)], spacing: Spacing.lg) {
                    ForEach(Array(duanjuItems.enumerated()), id: \.element.id) { idx, d in
                        ZStack(alignment: .topLeading) {
                            PosterCard(d)
                            rankBadge(idx + 1).padding(6)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(d) }
                    }
                }
                .padding(Spacing.lg)
            }
        }
    }

    /// 排名角标（前三强色，其余中性）。
    private func rankBadge(_ n: Int) -> some View {
        let color: Color = n == 1 ? .red : (n == 2 ? .orange : (n == 3 ? .yellow : .gray))
        return Text("\(n)")
            .font(.system(size: 12, weight: .black)).italic()
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(color.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func proxied(_ poster: String) -> URL? {
        guard !poster.isEmpty else { return nil }
        let enc = poster.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? poster
        return URL(string: "\(AppConfig.gatewayBaseURL)/api/image-proxy?url=\(enc)")
    }

    private func searchAndOpen(_ title: String) {
        Task {
            let results = await SourceManager.shared.aggregateSearch(query: title)
            if let first = results.first { await MainActor.run { onSelect(first) } }
        }
    }

    private func load() async {
        isLoading = true
        let svc = CatalogService.shared
        switch tab {
        case .movie:
            doubanItems = (try? await svc.doubanHot(kind: "movie", category: "热门", type: "全部", limit: 24)) ?? []
        case .tv:
            doubanItems = (try? await svc.doubanHot(kind: "tv", category: "tv", type: "tv", limit: 24)) ?? []
        case .variety:
            doubanItems = (try? await svc.doubanHot(kind: "tv", category: "show", type: "show", limit: 24)) ?? []
        case .duanju:
            duanjuItems = await SourceManager.shared.duanjuRecommends(limit: 24)
        }
        isLoading = false
    }
}
