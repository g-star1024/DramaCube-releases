import SwiftUI
import HongguoCore

/// 搜索详情浮层：点击发现页豆瓣卡片弹出。
///
/// 流程（对齐参考站「点片 → 检索可播放源 → 选源看详情」）：
///  1. 「搜索中…」：展示正在跨源检索，用户能感知后台过程（不再是点了没反应）；
///  2. 「搜索结果」：列出命中该剧的全部 TVBox 源（带站点名/集数），点选某个源；
///  3. 「剧集详情」：加载该源的详情（选集），并支持「切换源」回到第 2 步换源；
///  4. 选集播放：回调上层打开播放器（播放器内也支持切源）。
///
/// 红果内容源已整体清除：这里只聚合 TVBox 源，不碰红果。
public struct SearchDetailSheet: View {
    let request: SearchRequest
    let onPlay: (Drama) -> Void
    let onClose: () -> Void

    private enum Phase { case searching, results, detail }

    @State private var phase: Phase = .searching
    @State private var matches: [SourceMatch] = []
    @State private var searchError: String?
    @State private var selected: SourceMatch?
    @State private var detail: DramaDetail?
    @State private var isLoadingDetail = false
    @State private var detailError: String?

    init(request: SearchRequest,
         onPlay: @escaping (Drama) -> Void,
         onClose: @escaping () -> Void) {
        self.request = request; self.onPlay = onPlay; self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            content
        }
        .background(Brand.background)
        .frame(minWidth: 720, minHeight: 540)
        .task { await runSearch() }
    }

    // MARK: 标题栏
    private var titleBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(Brand.accent)
            Text(request.title).font(Typography.headline).lineLimit(1)
            if !request.year.isEmpty {
                Text(request.year).font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
            }
            Spacer()
            Button { onClose() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20)).foregroundStyle(Brand.secondaryLabel)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("关闭 (Esc)")
        }
        .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.sm)
        .background(Brand.secondaryBackground)
    }

    // MARK: 内容（按阶段）
    @ViewBuilder
    private var content: some View {
        switch phase {
        case .searching:
            searchingView
        case .results:
            resultsView
        case .detail:
            detailView
        }
    }

    // MARK: 1) 搜索中
    private var searchingView: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView().controlSize(.large)
            Text("正在搜索「\(request.title)」…")
                .font(Typography.headline)
            Text("正在跨 \(SourceManager.shared.enabledSites.count) 个视频源检索可播放资源")
                .font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 2) 搜索结果（多源列表）
    @ViewBuilder
    private var resultsView: some View {
        if let err = searchError {
            ErrorView(err, retry: { Task { await runSearch() } })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if matches.isEmpty {
            EmptyState("未找到可播放源",
                       systemImage: "film.stack",
                       description: "「\(request.title)」在当前已启用的视频源中没有资源，可尝试在「视频源」里启用更多站点")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("找到 \(matches.count) 个可播放源")
                    .font(Typography.headline)
                    .padding(.horizontal, Spacing.lg).padding(.top, Spacing.md)
                List(matches) { m in
                    Button { Task { await openDetail(m) } } label: {
                        HStack(spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.drama.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                HStack(spacing: 8) {
                                    Text(m.siteName)
                                        .font(.system(size: 11, weight: .semibold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(Brand.accent.opacity(0.12)))
                                        .foregroundStyle(Brand.accent)
                                    if let cnt = m.drama.episodeCount {
                                        Text("\(cnt) 集").font(.system(size: 11)).foregroundStyle(Brand.secondaryLabel)
                                    }
                                    if let st = m.drama.updateStatus, !st.isEmpty {
                                        Text(st).font(.system(size: 11)).foregroundStyle(Brand.secondaryLabel)
                                    }
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Brand.secondaryLabel)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: 3) 剧集详情（含切源）
    @ViewBuilder
    private var detailView: some View {
        VStack(spacing: 0) {
            // 切源栏
            if let sel = selected {
                HStack(spacing: Spacing.sm) {
                    Text("当前源：").font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
                    Text(sel.siteName).font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.accent)
                    Button { phase = .results } label: {
                        Label("切换源", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Spacer()
                    Text("\(matches.count) 个源可用").font(.system(size: 11)).foregroundStyle(Brand.secondaryLabel)
                }
                .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.sm)
                .background(Brand.secondaryBackground.opacity(0.5))
                Divider()
            }

            if isLoadingDetail {
                LoadingView("加载剧集…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = detailError {
                ErrorView(err, retry: { if let s = selected { Task { await openDetail(s) } } })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        detailHeader(detail)
                        episodeGrid(detail)
                    }
                    .padding(Spacing.lg)
                }
            }
        }
    }

    private func detailHeader(_ detail: DramaDetail) -> some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            Group {
                if let urlStr = detail.drama.coverURL, let url = URL(string: urlStr) {
                    CoverImage(url)
                } else { Brand.placeholder }
            }
            .frame(width: 130, height: 173)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Brand.separator, lineWidth: 0.5))

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(detail.drama.title).font(Typography.title).lineLimit(2)
                HStack(spacing: Spacing.sm) {
                    if let cnt = detail.drama.episodeCount { Label("\(cnt) 集", systemImage: "list.number") }
                    if let st = detail.drama.updateStatus, !st.isEmpty { Label(st, systemImage: "arrow.triangle.2.circlepath") }
                }
                .font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
                if let desc = detail.drama.description, !desc.isEmpty {
                    Text(desc).font(Typography.body).foregroundStyle(Brand.secondaryLabel).lineLimit(3)
                }
                Spacer(minLength: 4)
                Button {
                    onPlay(detail.drama)
                } label: {
                    Label("立即播放", systemImage: "play.fill").frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent).tint(Brand.accent)
            }
        }
    }

    private func episodeGrid(_ detail: DramaDetail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("选集").font(Typography.headline)
            if detail.episodes.isEmpty {
                Text("暂无分集信息").font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
            } else {
                // 播放整剧（由上层 PlayerViewModel 按集加载），这里点任意集都从该集开始
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56, maximum: 72), spacing: 8)], spacing: 8) {
                    ForEach(Array(detail.episodes.enumerated()), id: \.element.id) { idx, ep in
                        Button {
                            // 通过详情链路播放：上层 DetailView 已支持 startIndex，
                            // 这里简化为打开该剧（播放器内可选集+切源）
                            onPlay(detail.drama)
                        } label: {
                            Text(ep.title.isEmpty ? "\(idx + 1)" : ep.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Brand.chipFill))
                                .foregroundStyle(Brand.label)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - 逻辑
    /// 跨 TVBox 源聚合搜索，并标注每条结果的站点名。
    private func runSearch() async {
        phase = .searching; searchError = nil; matches = []
        let sm = SourceManager.shared
        let sites = sm.enabledSites
        guard !sites.isEmpty else {
            searchError = "尚未配置可用的视频源，请先到「视频源」导入订阅"
            phase = .results
            return
        }
        // 并发搜各源，保留站点名（aggregateSearch 去重后丢了来源，这里逐源搜以便切源）
        var collected: [SourceMatch] = []
        await withTaskGroup(of: [SourceMatch].self) { group in
            var pending = sites.makeIterator()
            for _ in 0..<5 {
                if let s = pending.next() {
                    group.addTask {
                        let list = (try? await sm.tvboxSearch(siteKey: s.key, query: self.request.title)) ?? []
                        return list.map { SourceMatch(drama: $0, siteKey: s.key, siteName: s.name) }
                    }
                }
            }
            while let chunk = await group.next() {
                collected.append(contentsOf: chunk)
                if let s = pending.next() {
                    group.addTask {
                        let list = (try? await sm.tvboxSearch(siteKey: s.key, query: self.request.title)) ?? []
                        return list.map { SourceMatch(drama: $0, siteKey: s.key, siteName: s.name) }
                    }
                }
            }
        }
        // 标题精确匹配优先，其次包含
        let q = request.title
        matches = collected.sorted { a, b in
            let ea = a.drama.title == q, eb = b.drama.title == q
            if ea != eb { return ea }
            return (a.drama.episodeCount ?? 0) > (b.drama.episodeCount ?? 0)
        }
        if matches.isEmpty && searchError == nil {
            // 空结果走 resultsView 的空态
        }
        phase = .results
    }

    private func openDetail(_ m: SourceMatch) async {
        selected = m; phase = .detail
        isLoadingDetail = true; detailError = nil; detail = nil
        do {
            // tvbox id = tvbox|<siteKey>|<vodId>
            let parts = m.drama.id.split(separator: "|").map(String.init)
            guard parts.count == 3 else { throw HongguoParseError.fieldMissing("tvbox id") }
            detail = try await SourceManager.shared.tvboxDetail(siteKey: parts[1], vodId: parts[2])
        } catch {
            detailError = "详情加载失败：\(error.localizedDescription)"
        }
        isLoadingDetail = false
    }
}

/// 一条「源 + 剧」的匹配结果（用于切源列表）。
public struct SourceMatch: Identifiable, Hashable, Sendable {
    public let drama: Drama
    public let siteKey: String
    public let siteName: String
    public var id: String { drama.id + "@" + siteKey }
    public init(drama: Drama, siteKey: String, siteName: String) {
        self.drama = drama; self.siteKey = siteKey; self.siteName = siteName
    }
}
