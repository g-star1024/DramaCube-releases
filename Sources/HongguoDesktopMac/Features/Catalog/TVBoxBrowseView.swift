import SwiftUI
import HongguoCore

/// TVBox 视频源浏览页：顶部源选择 chips + 当前源最新列表（分页）。
///
/// 点选卡片走统一 openDetail；Drama.id 为 `tvbox|<site>|<vodId>`，
/// 详情/播放在 DetailView / CatalogView 中按前缀分流到 SourceManager。
struct TVBoxBrowseView: View {
    @ObservedObject var sm: SourceManager
    let onSelect: (Drama) -> Void

    @State private var items: [Drama] = []
    @State private var page = 1
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var error: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 6)

    var body: some View {
        VStack(spacing: 0) {
            sourceBar
            Divider()
            content
        }
        .background(Brand.background)
        .task { await load(reset: true) }
        .onChange(of: sm.currentSource) { _, _ in Task { await load(reset: true) } }
    }

    // MARK: 源切换条
    private var sourceBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                // 内置红果固定在最前
                sourceChip(id: "hongguo", name: "红果短剧", builtin: true)
                ForEach(sm.enabledSites) { s in
                    sourceChip(id: s.key, name: s.name, builtin: false)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
        }
    }

    private func sourceChip(id: String, name: String, builtin: Bool) -> some View {
        let active = sm.currentSource == id
        return Button {
            sm.currentSource = id
        } label: {
            HStack(spacing: 4) {
                if builtin { Image(systemName: "flame.fill").font(.system(size: 10)) }
                Text(name).font(Typography.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(active ? Brand.accent : Brand.chipFill)
            )
            .foregroundStyle(active ? .white : Brand.label)
            .overlay(
                Capsule().strokeBorder(active ? Color.clear : Brand.separator.opacity(0.6), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 内容
    @ViewBuilder
    private var content: some View {
        if sm.currentSource == "hongguo" {
            // 红果源由发现/排行榜/探索页承载，这里给引导
            EmptyState("红果源请在「发现 / 排行榜 / 探索」中浏览",
                       systemImage: "flame",
                       description: "此处展示 TVBox 订阅源内容；选择上方任意站点开始浏览")
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
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(items) { d in
                    PosterCard(d)
                        .onTapGesture { onSelect(d) }
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
    private func load(reset: Bool) async {
        let src = sm.currentSource
        guard src != "hongguo" else { return }
        if isLoading { return }
        isLoading = true
        if reset { page = 1; hasMore = true; error = nil }
        let target = reset ? 1 : page
        do {
            let fresh = try await sm.tvboxLatest(siteKey: src, page: target)
            if reset { items = fresh } else { items.append(contentsOf: fresh) }
            page = target + 1
            hasMore = fresh.count >= 12
            AppLog.log(.app, "视频源 \(src) 第 \(target) 页：\(fresh.count) 部")
        } catch {
            if reset { self.error = "加载失败：\(error.localizedDescription)" }
            AppLog.log(.error, "视频源 \(src) 加载失败：\(error.localizedDescription)")
        }
        isLoading = false
    }
}
