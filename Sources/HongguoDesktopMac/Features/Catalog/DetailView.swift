import SwiftUI
import HongguoCore

/// 剧集详情页（真实渲染）：封面、标题、状态、选集、收藏、相关推荐。
///
/// 由 `CatalogView` 以 sheet 形式弹出；点击播放 / 选集回调给上层打开播放器。
public struct DetailView: View {
    let drama: Drama
    let onPlay: (DramaDetail, Int) -> Void

    @State private var detail: DramaDetail?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isFav = false
    @State private var related: [Drama] = []
    @State private var playedEpisodeIds: Set<String> = []

    public init(drama: Drama, onPlay: @escaping (DramaDetail, Int) -> Void) {
        self.drama = drama
        self.onPlay = onPlay
    }

    public var body: some View {
        ScrollView {
            if let error = loadError {
                ErrorView(error, retry: { Task { await load() } })
                    .frame(maxHeight: .infinity)
            } else if isLoading && detail == nil {
                LoadingView("加载详情…").frame(maxHeight: .infinity)
            } else {
                bodyContent
            }
        }
        .navigationTitle(drama.title)
        .frame(minWidth: 560, minHeight: 480)
        .task { await load() }
    }

    @ViewBuilder
    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            episodesSection
            if !related.isEmpty { relatedSection }
        }
        .padding(Spacing.lg)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Group {
                if let urlStr = drama.coverURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        case .failure: Color.gray
                        default: ProgressView()
                        }
                    }
                } else { Color.gray }
            }
            .frame(width: 180, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Brand.separator, lineWidth: 0.5))

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(drama.title).font(Typography.title)
                if let status = detail?.drama.updateStatus {
                    Label(status, systemImage: "arrow.triangle.2.circlepath")
                        .font(Typography.caption)
                        .foregroundStyle(Brand.secondaryLabel)
                }
                if let desc = detail?.drama.description, !desc.isEmpty {
                    Text(desc)
                        .font(Typography.body)
                        .foregroundStyle(Brand.secondaryLabel)
                        .lineLimit(6)
                }
                Spacer(minLength: Spacing.md)
                HStack(spacing: Spacing.sm) {
                    Button {
                        onPlay(detail ?? DramaDetail(drama: drama, episodes: []), resumeIndex())
                    } label: {
                        Label("立即播放", systemImage: "play.fill")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.pink)

                    Button {
                        toggleFav()
                    } label: {
                        Label(isFav ? "已收藏" : "收藏", systemImage: isFav ? "heart.fill" : "heart")
                    }
                    .buttonStyle(.bordered)
                    .tint(isFav ? Brand.pink : .secondary)
                }
            }
        }
    }

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("选集").font(Typography.headline)
            if let eps = detail?.episodes, !eps.isEmpty {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(eps.enumerated()), id: \.element.id) { idx, ep in
                        EpisodeRow(
                            episode: ep,
                            isCurrent: idx == resumeIndex(),
                            isPlayed: playedEpisodeIds.contains(ep.id)
                        ) {
                            onPlay(detail ?? DramaDetail(drama: drama, episodes: eps), idx)
                        }
                    }
                }
            } else {
                Text("暂无分集信息").font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
            }
        }
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("猜你喜欢").font(Typography.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(related) { d in
                        PosterCard(d)
                            .frame(width: 130)
                            .onTapGesture {
                                // 相关推荐点击：直接替换本页（由上层处理）
                                NotificationCenter.default.post(name: .hongguoOpenDrama, object: d)
                            }
                    }
                }
                .padding(.horizontal, Spacing.xs)
            }
        }
    }

    /// 续播起点：第一个未看过的集，否则第 0 集。
    private func resumeIndex() -> Int {
        guard let eps = detail?.episodes, !eps.isEmpty else { return 0 }
        for (i, ep) in eps.enumerated() where !playedEpisodeIds.contains(ep.id) {
            return i
        }
        return 0
    }

    private func toggleFav() {
        Repository.shared.toggleFavorite(dramaId: drama.id, title: drama.title, coverURL: drama.coverURL)
        isFav = Repository.shared.isFavorite(dramaId: drama.id)
        NotificationCenter.default.post(name: .hongguoLibraryChanged, object: nil)
    }

    private func load() async {
        isLoading = true; loadError = nil
        do {
            let d = try await CatalogService.shared.detail(id: drama.id)
            detail = d
            // 已播标记
            let played = Repository.shared.history().filter { $0.dramaId == drama.id }.map(\.episodeId)
            playedEpisodeIds = Set(played)
            isFav = Repository.shared.isFavorite(dramaId: drama.id)
            // 相关推荐
            related = (try? await CatalogService.shared.catalog(path: "/")) ?? []
        } catch {
            loadError = "详情加载失败：\(error.localizedDescription)"
        }
        isLoading = false
    }
}

extension Notification.Name {
    static let hongguoOpenDrama = Notification.Name("hongguoOpenDrama")
}
