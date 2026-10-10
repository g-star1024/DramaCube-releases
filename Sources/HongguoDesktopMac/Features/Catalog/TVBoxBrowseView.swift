import SwiftUI
import HongguoCore

/// TVBox 视频源浏览页：源 chips + 源切换弹层 + 轮播大图 + 频道分类 + 分页网格。
///
/// 默认展示延迟最低的可用源（无测速结果时为订阅第一个启用源）；
/// 列表走 cache-then-network（启动秒开，再后台刷新回写）。
/// Drama.id 为 `tvbox|<site>|<vodId>`，详情/播放在 DetailView / CatalogView 中按前缀分流。
struct TVBoxBrowseView: View {
    @ObservedObject var sm: SourceManager
    let onSelect: (Drama) -> Void

    @State private var items: [Drama] = []
    @State private var featured: [Drama] = []
    @State private var page = 1
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var error: String?
    @State private var showSourcePicker = false
    @State private var selectedTypeId: Int? // nil = 最新（不区分频道）

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 6)

    var body: some View {
        VStack(spacing: 0) {
            // 顶部不再平铺当前源 chip；频道行右侧放「切换源」按钮（截图标记1位置）
            if !sm.enabledSites.isEmpty, sm.currentSource != "hongguo" {
                categoryBar
            }
            Divider()
            content
        }
        .background(Brand.background)
        .task { await initialLoad() }
        .onChange(of: sm.currentSource) { _, _ in
            selectedTypeId = nil
            // 切换源：轮播缓存按源 key 隔离，切走即清空重拉新源最新
            featured = []
            items = []
            // 频道也要随源懒加载（此前漏掉，导致手动切源后只剩「最新」，切模块返回才出现）
            Task {
                _ = await sm.tvboxCategories(siteKey: sm.currentSource)
                await load(reset: true)
                await refreshFeatured()
            }
        }
        .onChange(of: selectedTypeId) { _, _ in Task { await load(reset: true) } }
        .onChange(of: sm.sites) { _, _ in ensureDefaultSource() }
        .popover(isPresented: $showSourcePicker, arrowEdge: .top) {
            sourcePicker
        }
    }

    // MARK: 源切换按钮（只留一个 ⟳ 按钮，附当前源名，点击弹全源列表）
    private var sourceSwitchButton: some View {
        Button { showSourcePicker = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                Text(sm.currentSourceName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Brand.label)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Brand.chipFill))
            .overlay(Capsule().strokeBorder(Brand.separator.opacity(0.6), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("当前源：\(sm.currentSourceName)，点击切换")
    }

    /// 全源切换弹层（含延迟与状态）。
    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("选择视频源")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sm.sortedSites) { s in
                        let off = sm.disabled.contains(s.key)
                        Button {
                            if !off {
                                sm.currentSource = s.key
                                showSourcePicker = false
                            }
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: sm.currentSource == s.key ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(sm.currentSource == s.key ? Brand.accent : Brand.secondaryLabel)
                                Text(s.name).font(Typography.body).lineLimit(1)
                                Spacer()
                                if let r = sm.testResults[s.key] {
                                    Text(r.ok ? "\(r.latencyMs)ms" : "失败")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(r.ok ? .green : .red)
                                }
                                if off {
                                    Text("已禁用")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Brand.secondaryLabel)
                                }
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(off)
                        .opacity(off ? 0.5 : 1)
                    }
                }
            }
        }
        .frame(width: 320, height: 420)
    }

    // MARK: 频道分类条（maccms class）+ 右侧源切换按钮（标记1位置）
    @ViewBuilder
    private var categoryBar: some View {
        let cats = sm.categories[sm.currentSource] ?? []
        HStack(spacing: Spacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    catChip(id: nil, name: "最新")
                    ForEach(cats) { c in
                        catChip(id: c.typeId, name: c.name)
                    }
                }
            }
            // 源切换按钮固定在频道行右侧（不被横向滚动挤走）
            sourceSwitchButton
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
    }

    private func catChip(id: Int?, name: String) -> some View {
        let active = selectedTypeId == id
        return Button { selectedTypeId = id } label: {
            Text(name)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(active ? Brand.label : Color.clear))
                .foregroundStyle(active ? Brand.background : Brand.secondaryLabel)
                .overlay(Capsule().strokeBorder(active ? Color.clear : Brand.separator.opacity(0.6), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: 内容
    @ViewBuilder
    private var content: some View {
        if !sm.hasSubscription {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 34))
                    .foregroundStyle(Brand.secondaryLabel)
                Text("尚未导入视频源订阅").font(Typography.body)
                Text("请到「设置 → 视频源」粘贴 TVBox 订阅地址一键导入")
                    .font(Typography.caption)
                    .foregroundStyle(Brand.secondaryLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sm.enabledSites.isEmpty {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 34))
                    .foregroundStyle(.orange)
                Text("所有视频源均已禁用").font(Typography.body)
                Text("请到「设置 → 视频源」重新启用，或执行一次连通性测试")
                    .font(Typography.caption)
                    .foregroundStyle(Brand.secondaryLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            ErrorView(error, retry: { Task { await load(reset: true) } })
        } else if items.isEmpty && isLoading {
            LoadingView("正在加载 \(sm.currentSourceName)…")
        } else if items.isEmpty {
            EmptyState("该源暂无内容", systemImage: "tray", description: "可能是站点无数据或接口异常，可在设置中做连通性测试")
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if !featured.isEmpty {
                    HeroCarousel(items: Array(featured.prefix(6)), onSelect: onSelect)
                }
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(items) { d in
                        PosterCard(d)
                            .onTapGesture { onSelect(d) }
                    }
                }
            }
            .padding(Spacing.lg)

            if isLoading {
                HStack(spacing: Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("加载中…").font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
                }
                .frame(maxWidth: .infinity).padding(Spacing.md)
            } else if hasMore {
                Button("加载更多") { Task { await load(reset: false) } }
                    .buttonStyle(.bordered)
                    .padding(.bottom, Spacing.lg)
            } else {
                Text("已经到底啦 · 共 \(items.count) 部")
                    .font(Typography.caption)
                    .foregroundStyle(Brand.secondaryLabel)
                    .frame(maxWidth: .infinity).padding(.bottom, Spacing.lg)
            }
        }
    }

    // MARK: 加载
    /// 默认源：当前源不可用（未导入/被禁用/还是 hongguo）时，切到最快可用源。
    private func ensureDefaultSource() {
        guard sm.hasSubscription else { return }
        if sm.currentSource == "hongguo" || sm.disabled.contains(sm.currentSource)
            || !sm.sites.contains(where: { $0.key == sm.currentSource }) {
            if let fast = sm.fastestEnabledSite {
                sm.currentSource = fast.key
            }
        }
    }

    private var cacheKey: String { "tvbox:\(sm.currentSource):t\(selectedTypeId ?? 0)" }
    private var featuredCacheKey: String { "tvbox:featured:\(sm.currentSource)" }

    private func initialLoad() async {
        ensureDefaultSource()
        let src = sm.currentSource
        guard src != "hongguo", sm.enabledSites.contains(where: { $0.key == src }) else { return }
        isLoading = true
        // 缓存秒开
        if let cached: [Drama] = await DiskCache.shared.read([Drama].self, key: cacheKey), !cached.isEmpty {
            items = cached
        }
        if let cf: [Drama] = await DiskCache.shared.read([Drama].self, key: featuredCacheKey), !cf.isEmpty {
            featured = cf
        }
        // 频道懒加载
        Task { _ = await sm.tvboxCategories(siteKey: src) }
        await load(reset: true, force: true)
        // 轮播 = 该源最新第一页前 6 部（缓存按源 key 隔离，切换源时强制重拉）
        await refreshFeatured()
    }

    /// 拉取当前源轮播（有该源缓存先用缓存，同时后台刷新回写）。
    private func refreshFeatured() async {
        let src = sm.currentSource
        guard src != "hongguo", sm.enabledSites.contains(where: { $0.key == src }) else { featured = []; return }
        if let cf: [Drama] = await DiskCache.shared.read([Drama].self, key: featuredCacheKey), !cf.isEmpty {
            featured = cf
        }
        if let f = try? await sm.tvboxLatest(siteKey: src, page: 1), !f.isEmpty {
            featured = Array(f.prefix(6))
            await DiskCache.shared.write(Array(f.prefix(6)), key: featuredCacheKey)
        }
    }

    private func load(reset: Bool, force: Bool = false) async {
        let src = sm.currentSource
        guard src != "hongguo", sm.enabledSites.contains(where: { $0.key == src }) else { isLoading = false; return }
        if isLoading, !force { return }
        isLoading = true
        if reset { page = 1; hasMore = true; error = nil }
        let target = reset ? 1 : page
        do {
            let fresh = try await sm.tvboxLatest(siteKey: src, page: target, typeId: selectedTypeId)
            if reset { items = fresh } else { items.append(contentsOf: fresh) }
            page = target + 1
            hasMore = fresh.count >= 12
            AppLog.log(.app, "视频源 \(src) 第 \(target) 页（频道 \(selectedTypeId ?? -1)）：\(fresh.count) 部")
            if reset { await DiskCache.shared.write(items, key: cacheKey) }
        } catch {
            if reset { self.error = "加载失败：\(error.localizedDescription)" }
            AppLog.log(.error, "视频源 \(src) 加载失败：\(error.localizedDescription)")
        }
        isLoading = false
    }
}
