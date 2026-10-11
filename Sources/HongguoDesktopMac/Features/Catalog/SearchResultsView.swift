import SwiftUI
import HongguoCore

/// 搜索结果页：流式跨源检索。
///
/// 体验对齐用户要求：
///  - **不整页转圈**：右上角小 spinner + 实时滚动显示「正在检索：X 源」；
///  - **结果流式列表**：搜到一个源的匹配立即追加一行（不等全部源轮巡完）；
///  - **点击直接播放**：回调上层拉详情后直拨播放器，不再跳中间页。
struct SearchResultsView: View {
    let keyword: String
    let onPlay: (SourceMatch) -> Void

    @State private var matches: [SourceMatch] = []
    @State private var isSearching = true
    @State private var searchingSiteName = ""

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            content
        }
        .task(id: keyword) { await streamSearch() }
    }

    // MARK: 状态条：结果数 + 右上角滚动显示正在检索的源
    private var statusBar: some View {
        HStack(spacing: Spacing.sm) {
            Text("「\(keyword)」")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.label)
            Text(matches.isEmpty ? (isSearching ? "检索中" : "无结果") : "\(matches.count) 条结果")
                .font(Typography.caption)
                .foregroundStyle(Brand.secondaryLabel)
            Spacer()
            if isSearching {
                ProgressView().controlSize(.small)
                Text(searchingSiteName.isEmpty ? "正在检索在线源…" : "正在检索：\(searchingSiteName)")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.secondaryLabel)
                    .lineLimit(1)
                    .id(searchingSiteName)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: searchingSiteName)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Brand.secondaryBackground)
    }

    // MARK: 结果列表（流式追加）
    @ViewBuilder
    private var content: some View {
        if matches.isEmpty {
            if isSearching {
                VStack(spacing: Spacing.sm) {
                    Spacer()
                    Text("正在跨在线视频源检索，搜到即显示…")
                        .font(Typography.body)
                        .foregroundStyle(Brand.secondaryLabel)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState("未找到相关内容", systemImage: "magnifyingglass",
                           description: "换个关键词试试，或在「视频源」启用更多站点")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(matches) { m in
                        Button { onPlay(m) } label: { resultRow(m) }
                            .buttonStyle(.plain)
                    }
                    if isSearching {
                        HStack(spacing: Spacing.sm) {
                            ProgressView().controlSize(.small)
                            Text("继续检索其他源…")
                                .font(Typography.caption)
                                .foregroundStyle(Brand.secondaryLabel)
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                }
                .padding(Spacing.lg)
            }
        }
    }

    private func resultRow(_ m: SourceMatch) -> some View {
        HStack(spacing: Spacing.md) {
            // 封面小图
            Group {
                if let cover = m.drama.coverURL, let url = URL(string: proxied(cover)) {
                    CoverImage(url)
                } else { Brand.placeholder }
            }
            .frame(width: 64, height: 86)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(m.drama.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Brand.label)
                    .lineLimit(1)
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
                        Text(st).font(.system(size: 11)).foregroundStyle(Brand.secondaryLabel).lineLimit(1)
                    }
                }
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Brand.pink)
        }
        .padding(Spacing.sm)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Brand.chipFill))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.separator.opacity(0.5), lineWidth: 0.5))
        .contentShape(Rectangle())
    }

    // MARK: - 流式检索

    /// 并发跨源搜索（只搜在线源、单源 8s 超时、搜到一个追加一个）。
    private func streamSearch() async {
        matches = []; isSearching = true; searchingSiteName = ""
        let sm = SourceManager.shared
        // 单源模式：当前源是具体 tvbox 站点时只搜它；否则聚合全部在线启用源
        let targets: [SourceManager.TVBoxSite]
        if sm.currentSource != "hongguo", !sm.currentSource.isEmpty,
           let one = sm.sites.first(where: { $0.key == sm.currentSource }) {
            targets = [one]
        } else {
            targets = sm.enabledSites.filter { site in
                guard let r = sm.testResults[site.key] else { return true }
                return r.ok || !sm.disabled.contains(site.key)
            }
        }
        guard !targets.isEmpty else { isSearching = false; return }

        await withTaskGroup(of: (String, [SourceMatch]).self) { group in
            var pending = targets.makeIterator()
            func enqueue() {
                if let s = pending.next() {
                    let kw = keyword
                    group.addTask {
                        let list = await Self.searchOne(sm: sm, site: s, query: kw)
                        return (s.name, list)
                    }
                }
            }
            for _ in 0..<6 { enqueue() }
            while let (siteName, chunk) = await group.next() {
                searchingSiteName = siteName
                if !chunk.isEmpty {
                    matches.append(contentsOf: chunk)
                    var seen = Set<String>()
                    matches = matches.filter { seen.insert($0.id).inserted }
                }
                enqueue()
            }
        }
        searchingSiteName = ""
        isSearching = false
    }

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

    private func proxied(_ poster: String) -> String {
        guard poster.hasPrefix("http") else { return poster }
        let enc = poster.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? poster
        return "\(AppConfig.gatewayBaseURL)/api/image-proxy?url=\(enc)"
    }
}
