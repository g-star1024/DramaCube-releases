import SwiftUI
import HongguoCore

/// 剧集详情弹窗：标题栏（含关闭按钮）+ 头部信息 + 选集网格 + 相关推荐。
///
/// 由 `CatalogView` 以 sheet 形式弹出；点击播放 / 选集回调给上层打开播放器。
/// 关闭方式：右上角 × 按钮 / Esc 键（macOS sheet 自带 Esc 关闭，按钮兜底）。
public struct DetailView: View {
    let drama: Drama
    let onPlay: (DramaDetail, Int) -> Void

    @Environment(\.dismiss) private var dismiss
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
        VStack(spacing: 0) {
            titleBar
            Divider()
            content
        }
        .background(Brand.background)
        .frame(minWidth: 680, minHeight: 520)
        .task { await load() }
    }

    // MARK: 标题栏（可关闭）
    private var titleBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "play.rectangle.fill")
                .foregroundStyle(Brand.accent)
            Text(drama.title)
                .font(Typography.headline)
                .lineLimit(1)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Brand.secondaryLabel)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("关闭 (Esc)")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Brand.secondaryBackground)
    }

    // MARK: 内容
    @ViewBuilder
    private var content: some View {
        if let error = loadError {
            ErrorView(error, retry: { Task { await load() } })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoading && detail == nil {
            LoadingView("加载详情…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detail {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header(detail)
                    episodesSection(detail)
                    if !related.isEmpty { relatedSection }
                }
                .padding(Spacing.lg)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: 头部：封面 + 信息 + 操作
    private func header(_ detail: DramaDetail) -> some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            Group {
                if let urlStr = drama.coverURL, let url = URL(string: urlStr) {
                    CoverImage(url)
                } else { Brand.placeholder }
            }
            .frame(width: 150, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Brand.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(drama.title)
                    .font(Typography.title)
                    .lineLimit(2)
                HStack(spacing: Spacing.sm) {
                    if let cnt = detail.drama.episodeCount {
                        Label("\(cnt) 集", systemImage: "collection.playback")
                    }
                    if let status = detail.drama.updateStatus, !status.isEmpty {
                        Label(status, systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .font(Typography.caption)
                .foregroundStyle(Brand.secondaryLabel)

                if !detail.drama.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.xs) {
                            ForEach(detail.drama.tags.prefix(6), id: \.self) { tag in
                                Text(tag)
                                    .font(Typography.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Brand.accent.opacity(0.1)))
                                    .foregroundStyle(Brand.accent)
                            }
                        }
                    }
                }

                if let desc = detail.drama.description, !desc.isEmpty {
                    Text(desc)
                        .font(Typography.body)
                        .foregroundStyle(Brand.secondaryLabel)
                        .lineLimit(4)
                }

                Spacer(minLength: Spacing.md)
                HStack(spacing: Spacing.sm) {
                    Button {
                        onPlay(detail, resumeIndex())
                    } label: {
                        Label("立即播放", systemImage: "play.fill")
                            .frame(minWidth: 130)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent)

                    Button {
                        toggleFav()
                    } label: {
                        Label(isFav ? "已收藏" : "收藏", systemImage: isFav ? "heart.fill" : "heart")
                    }
                    .buttonStyle(.bordered)
                    .tint(isFav ? Brand.accent : .secondary)
                }
            }
        }
    }

    // MARK: 选集（胶囊网格）
    private func episodesSection(_ detail: DramaDetail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("选集").font(Typography.headline)
                Text("\(detail.episodes.count) 集")
                    .font(Typography.caption)
                    .foregroundStyle(Brand.secondaryLabel)
                Spacer()
                if detail.episodes.count > 60 {
                    Text("已看 \(playedEpisodeIds.count) 集")
                        .font(Typography.caption)
                        .foregroundStyle(Brand.secondaryLabel)
                }
            }
            if !detail.episodes.isEmpty {
                EpisodeGrid(
                    episodes: detail.episodes,
                    currentIndex: -1,
                    playedIds: playedEpisodeIds
                ) { idx, _ in
                    onPlay(detail, idx)
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
        let cacheKey = "detail:\(drama.id)"
        // 1) 先用本地缓存秒开（封面走磁盘图缓）
        if let cached: DramaDetail = await DiskCache.shared.read(DramaDetail.self, key: cacheKey) {
            apply(cached)
        }
        // 2) 网络刷新并回写
        do {
            let d: DramaDetail
            if drama.id.hasPrefix("tvbox|") {
                // TVBox 源：id = tvbox|<siteKey>|<vodId>
                let parts = drama.id.split(separator: "|").map(String.init)
                guard parts.count == 3 else { throw HongguoParseError.fieldMissing("tvbox id") }
                d = try await SourceManager.shared.tvboxDetail(siteKey: parts[1], vodId: parts[2])
            } else if drama.id.hasPrefix("nas|") {
                // NAS 源：id = nas|<libId>|dir|<dirPath> 或 nas|<libId>|file|<filePath>
                let parts = drama.id.split(separator: "|", maxSplits: 3).map(String.init)
                guard parts.count == 4 else { throw HongguoParseError.fieldMissing("nas id") }
                if parts[2] == "dir" {
                    d = try await NASManager.shared.detail(id: parts[1], dirPath: parts[3])
                } else {
                    // 单文件：详情即一集
                    let url = try await NASManager.shared.playURLString(id: parts[1], path: parts[3])
                    d = DramaDetail(
                        drama: drama,
                        episodes: [Episode(id: "1", index: 1, title: drama.title, playURL: url)]
                    )
                }
            } else {
                d = try await CatalogService.shared.detail(id: drama.id)
            }
            apply(d)
            await DiskCache.shared.write(d, key: cacheKey)
        } catch {
            // 已有缓存展示时不打断用户，仅无缓存才报错
            if detail == nil {
                loadError = "详情加载失败：\(error.localizedDescription)"
            }
        }
        isLoading = false
    }

    private func apply(_ d: DramaDetail) {
        detail = d
        // 已播标记
        let played = Repository.shared.history().filter { $0.dramaId == drama.id }.map(\.episodeId)
        playedEpisodeIds = Set(played)
        isFav = Repository.shared.isFavorite(dramaId: drama.id)
        // 相关推荐：详情数据自带；站点未返回时回退到首页热播（排除自身）
        // TVBox 源不做回退（跨源推荐意义不大且流量浪费）
        if let rel = d.related, !rel.isEmpty {
            related = rel
        } else if related.isEmpty, !drama.id.hasPrefix("tvbox|"), !drama.id.hasPrefix("nas|") {
            Task { await loadRelatedFallback() }
        }
    }

    /// 猜你喜欢回退：用首页热播列表顶替（排除当前剧）。
    private func loadRelatedFallback() async {
        if let home = try? await CatalogService.shared.catalog(path: "/") {
            related = Array(home.filter { $0.id != drama.id }.prefix(12))
        }
    }
}

extension Notification.Name {
    static let hongguoOpenDrama = Notification.Name("hongguoOpenDrama")
}
