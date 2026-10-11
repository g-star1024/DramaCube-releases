import SwiftUI
import HongguoCore

/// 详情浮层：点击发现页豆瓣/B站卡片弹出。
///
/// 关键体验（对齐「详情秒开」要求）：
///  - **秒开**：标题/评分/年份/海报用榜单数据立即渲染，不等任何网络；
///  - **简介异步补**：豆瓣条目简介（rexxar /movie|tv/<id>）后台拉，到了就地填充；
///  - **源后台流式补**：可播放源搜索放后台，**搜到一个立即显示一个**（不整页转圈、
///    不等全部源轮巡完）；**只搜已测通的在线源**（testResults.ok），失效源直接跳过；
///  - **选源看剧**：点某个源加载该剧详情（选集）→ 播放；支持「换源」。
///
/// 与「视频源打开详情」完全解耦：这里走的是「豆瓣卡片 → 找可播放源」链路；
/// 视频源页详情仍走 tvboxDetail 秒开，互不影响。
public struct SearchDetailSheet: View {
    let request: SearchRequest
    let onPlay: (Drama) -> Void
    let onClose: () -> Void

    @State private var intro: String = ""          // 剧情简介（异步补）
    @State private var cardSubtitle: String = ""   // 年代/地区/类型/演职员
    @State private var matches: [SourceMatch] = []
    @State private var isSearchingSources = true
    @State private var sourcesDone = false
    @State private var selected: SourceMatch?
    @State private var detail: DramaDetail?
    @State private var isLoadingDetail = false
    @State private var detailError: String?
    @State private var searchTask: Task<Void, Never>?

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
        .frame(minWidth: 720, minHeight: 560)
        .task {
            // 简介与源搜索并行启动，互不阻塞
            async let i: () = loadIntro()
            async let s: () = streamSearchSources()
            _ = await (i, s)
        }
        .onDisappear { searchTask?.cancel() }
    }

    // MARK: 标题栏
    private var titleBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "play.rectangle.fill").foregroundStyle(Brand.accent)
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

    // MARK: 内容：左海报+信息（秒开）｜右源列表/选集
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header           // 秒开（榜单数据）
                sourceSection    // 源列表（流式补）或选集
            }
            .padding(Spacing.lg)
        }
    }

    // MARK: 头部：海报 + 标题/评分/简介（立即渲染，简介异步填）
    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            Group {
                if let url = request.proxiedPosterURL {
                    CoverImage(url)
                } else { Brand.placeholder }
            }
            .frame(width: 150, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Brand.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(request.title).font(Typography.title).lineLimit(2)
                HStack(spacing: Spacing.sm) {
                    if !request.rate.isEmpty {
                        Label(request.rate, systemImage: "star.fill").foregroundStyle(.orange)
                    }
                    if !request.year.isEmpty { Text(request.year) }
                }
                .font(Typography.caption).foregroundStyle(Brand.secondaryLabel)

                if !cardSubtitle.isEmpty {
                    Text(cardSubtitle).font(.system(size: 12)).foregroundStyle(Brand.secondaryLabel).lineLimit(2)
                }

                // 简介：秒开时为空 → 显示占位，异步到了就地填
                if intro.isEmpty {
                    Text("剧情简介加载中…")
                        .font(Typography.body).foregroundStyle(Brand.secondaryLabel.opacity(0.6))
                        .lineLimit(3)
                } else {
                    Text(intro).font(Typography.body).foregroundStyle(Brand.secondaryLabel).lineLimit(4)
                }

                Spacer(minLength: Spacing.md)
                HStack(spacing: Spacing.sm) {
                    if let first = matches.first {
                        Button { Task { await openDetail(first) } } label: {
                            Label("立即播放", systemImage: "play.fill").frame(minWidth: 120)
                        }
                        .buttonStyle(.borderedProminent).tint(Brand.accent)
                    } else {
                        Button { } label: {
                            Label(isSearchingSources ? "检索中…" : "立即播放", systemImage: "play.fill")
                                .frame(minWidth: 120)
                        }
                        .buttonStyle(.borderedProminent).tint(Brand.accent)
                        .disabled(true)
                    }
                }
            }
        }
    }

    // MARK: 源区：搜索中提示 + 流式源列表 + 选中源选集
    @ViewBuilder
    private var sourceSection: some View {
        if let sel = selected, let detail {
            selectedSourceView(sel, detail: detail)
        } else if isLoadingDetail {
            LoadingView("加载剧集…").frame(maxWidth: .infinity, minHeight: 200)
        } else if let err = detailError {
            ErrorView(err, retry: { if let s = selected { Task { await openDetail(s) } } })
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            sourceListView
        }
    }

    /// 可播放源列表（流式追加）。
    private var sourceListView: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text("可播放源").font(Typography.headline)
                if isSearchingSources {
                    ProgressView().controlSize(.small)
                    Text("正在检索在线源…").font(.system(size: 12)).foregroundStyle(Brand.secondaryLabel)
                } else {
                    Text("\(matches.count) 个").font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
                }
            }

            if matches.isEmpty {
                if isSearchingSources {
                    // 不整页转圈，只此区域提示
                    Text("正在跨在线视频源检索，搜到即显示…")
                        .font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    EmptyState("未找到可播放源", systemImage: "film.stack",
                               description: "「\(request.title)」在当前在线视频源中没有资源，可在「视频源」启用更多站点或做连通性测试")
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            } else {
                ForEach(matches) { m in
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
                        .padding(.vertical, 6)
                        .padding(.horizontal, Spacing.sm)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Brand.chipFill))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 选中某源后的选集视图（可换源）。
    private func selectedSourceView(_ sel: SourceMatch, detail: DramaDetail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text("当前源：").font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
                Text(sel.siteName).font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.accent)
                Button { selected = nil; self.detail = nil } label: {
                    Label("换源", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered).controlSize(.small)
                Spacer()
                Text("\(detail.episodes.count) 集").font(.system(size: 11)).foregroundStyle(Brand.secondaryLabel)
            }
            if detail.episodes.isEmpty {
                Text("暂无分集信息").font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52, maximum: 68), spacing: 8)], spacing: 8) {
                    ForEach(Array(detail.episodes.enumerated()), id: \.element.id) { idx, ep in
                        Button { onPlay(detail.drama) } label: {
                            Text(ep.title.isEmpty ? "\(idx + 1)" : ep.title)
                                .font(.system(size: 12, weight: .medium)).lineLimit(1)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Brand.chipFill))
                                .foregroundStyle(Brand.label)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - 异步逻辑

    /// 拉豆瓣简介（异步，不阻塞秒开）。anime(B站)无豆瓣简介，跳过。
    private func loadIntro() async {
        guard request.kind != "anime" else { return }
        let kind = request.kind == "tv" ? "tv" : "movie"
        if let s = try? await CatalogService.shared.doubanSubject(id: request.doubanId, kind: kind) {
            intro = s.intro
            cardSubtitle = s.cardSubtitle
        }
    }

    /// 流式搜可播放源：只搜已测通在线源，搜到一个追加一个（不等全部）。
    private func streamSearchSources() async {
        isSearchingSources = true; sourcesDone = false
        let sm = SourceManager.shared
        // 只搜在线源：已测通的（ok==true）；未测过的也纳入（避免一刀切漏掉好源），但排除已知失效源
        let onlineSites = sm.enabledSites.filter { site in
            guard let r = sm.testResults[site.key] else { return true }  // 未测过：纳入
            return r.ok                                                   // 已知失效：跳过
        }
        guard !onlineSites.isEmpty else {
            isSearchingSources = false; sourcesDone = true; return
        }
        // 并发搜，单源 8s 超时，先到先显
        await withTaskGroup(of: [SourceMatch].self) { group in
            var pending = onlineSites.makeIterator()
            func enqueue() {
                if let s = pending.next() {
                    group.addTask {
                        let list = await Self.searchOne(sm: sm, site: s, query: request.title)
                        return list
                    }
                }
            }
            for _ in 0..<6 { enqueue() }
            while let chunk = await group.next() {
                if !chunk.isEmpty {
                    // 流式追加 + 去重 + 排序（精确优先/集数多优先）
                    matches.append(contentsOf: chunk)
                    var seen = Set<String>()
                    let q = request.title
                    matches = matches.filter { seen.insert($0.id).inserted }.sorted { a, b in
                        let ea = a.drama.title == q, eb = b.drama.title == q
                        if ea != eb { return ea }
                        return (a.drama.episodeCount ?? 0) > (b.drama.episodeCount ?? 0)
                    }
                }
                enqueue()
            }
        }
        isSearchingSources = false; sourcesDone = true
    }

    /// 单源搜索（8s 超时保护，慢源/失效源及时放弃）。
    private static func searchOne(sm: SourceManager, site: SourceManager.TVBoxSite, query: String) async -> [SourceMatch] {
        await withTaskGroup(of: [SourceMatch]?.self) { g in
            g.addTask {
                let list = (try? await sm.tvboxSearch(siteKey: site.key, query: query)) ?? []
                return list.map { SourceMatch(drama: $0, siteKey: site.key, siteName: site.name) }
            }
            g.addTask {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                return nil
            }
            let first = await g.next() ?? nil
            g.cancelAll()
            return first ?? []
        }
    }

    /// 选中某源 → 加载该剧详情（选集）。
    private func openDetail(_ m: SourceMatch) async {
        selected = m; detail = nil; detailError = nil
        isLoadingDetail = true
        do {
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

// MARK: - SearchRequest 海报代理
extension SearchRequest {
    var proxiedPosterURL: URL? {
        guard !poster.isEmpty else { return nil }
        let enc = poster.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? poster
        return URL(string: "\(AppConfig.gatewayBaseURL)/api/image-proxy?url=\(enc)")
    }
}
