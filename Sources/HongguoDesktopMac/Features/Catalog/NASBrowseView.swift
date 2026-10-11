import SwiftUI
import HongguoCore

/// NAS 资源库浏览页：库切换 + 路径导航 + 视频列表。
///
/// 直出当前路径下全部视频文件（递归），点击卡片直接播放（不再聚合目录成剧、不进详情选集）。
/// Drama.id = nas|<libId>|file|<相对路径>，playURL 由 PlayerViewModel 按 nas| 前缀直连。
struct NASBrowseView: View {
    @ObservedObject var nm: NASManager
    let onSelect: (Drama) -> Void

    @State private var currentLibId: String?
    @State private var currentPath: String = ""
    @State private var allItems: [Drama] = []     // 当前目录全部视频（一次性从 NAS 列出，轻量）
    @State private var visibleCount = 30           // 懒加载：首屏只渲染前 30 个，滚动加载更多
    @State private var isLoading = false
    @State private var isRefreshing = false        // 后台刷新中（缓存已显示，静默更新）
    @State private var error: String?
    @State private var lastScanTime: Date?         // 上次扫描时间（缓存命中时显示）

    private let pageSize = 30
    /// 扫描结果磁盘缓存有效期（10 分钟内不重复全库扫描）
    private let scanCacheTTL: TimeInterval = 600
    /// 用户手动选择的库 id 持久化 key（避免每次访问被重置回第一个库）
    private let lastLibKey = "nas.lastLibId"

    /// 当前可见的卡片（懒加载切片）。封面生成是重活，只渲染可见部分避免一次性打满 CPU/IO。
    private var items: [Drama] { Array(allItems.prefix(visibleCount)) }

    // 自适应网格（对齐发现频道）：按宽度自动分列，不再固定每行 6 个。
    // columns 必须是稳定引用（见 TVBoxBrowseView 同注释）：计算属性每次 body 求值新建
    // GridItem 数组会致 LazyVGrid 重建、复位懒加载状态。改 @State 持有 + onChange 才重建。
    @Environment(\.uiCardScale) private var cardScale
    @State private var columns: [GridItem] = [GridItem(.adaptive(minimum: 130, maximum: 160), spacing: Spacing.md)]
    private func rebuildColumns() {
        columns = [GridItem(.adaptive(minimum: 130 * cardScale, maximum: 160 * cardScale), spacing: Spacing.md)]
    }

    var body: some View {
        VStack(spacing: 0) {
            if currentLibId != nil { pathBar }
            Divider()
            content
        }
        .background(Brand.background)
        .onChange(of: cardScale) { _, _ in rebuildColumns() }
        .task {
            rebuildColumns()
            nm.load()
            // 优先恢复用户上次手动选择的库；没有才默认第一个启用的库
            if currentLibId == nil {
                let saved = UserDefaults.standard.string(forKey: lastLibKey)
                if let saved, nm.libraries.contains(where: { $0.id == saved }) {
                    currentLibId = saved
                } else {
                    currentLibId = nm.libraries.first(where: { $0.enabled })?.id ?? nm.libraries.first?.id
                }
            }
            await load()
        }
        .onChange(of: currentLibId) { _, newId in
            currentPath = ""
            // 持久化用户选择（含 .task 里的默认选择）
            if let newId { UserDefaults.standard.set(newId, forKey: lastLibKey) }
            Task { await load() }
        }
        .onChange(of: nm.libraries) { _, libs in
            if currentLibId == nil {
                // 首次加载：优先恢复持久化选择
                let saved = UserDefaults.standard.string(forKey: lastLibKey)
                if let saved, libs.contains(where: { $0.id == saved }) {
                    currentLibId = saved
                } else {
                    currentLibId = libs.first(where: { $0.enabled })?.id ?? libs.first?.id
                }
                Task { await load() }
            } else if !libs.contains(where: { $0.id == currentLibId }) {
                // 当前库被删除了才回退第一个启用库
                currentLibId = libs.first(where: { $0.enabled })?.id ?? libs.first?.id
                Task { await load() }
            }
        }
        .popover(isPresented: $showLibPicker, arrowEdge: .top) { libPicker }
        .toolbar {
            // 库切换按钮放右上角 toolbar（同电视直播位置）
            ToolbarItem(placement: .automatic) {
                if currentLibId != nil {
                    libSwitchButton
                }
            }
        }
    }

    @State private var showLibPicker = false

    // MARK: 库切换按钮（只留一个 ⟳ 按钮附库名，点击弹库列表；不再平铺全部库 chip）
    private var libSwitchButton: some View {
        let cur = nm.libraries.first(where: { $0.id == currentLibId })
        return Button { showLibPicker = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                Text(cur?.name ?? "选择资源库")
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
        .help("当前资源库：\(cur?.name ?? "未选择")，点击切换")
    }

    /// 资源库切换弹层。
    private var libPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("选择资源库")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // 后台被禁用的库不在切换弹层展示
                    ForEach(nm.libraries.filter(\.enabled)) { lib in
                        Button {
                            currentLibId = lib.id; showLibPicker = false
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: currentLibId == lib.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(currentLibId == lib.id ? Brand.accent : Brand.secondaryLabel)
                                Image(systemName: lib.type == .webdav ? "network" : "externaldrive")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Brand.secondaryLabel)
                                Text(lib.name).font(Typography.body).lineLimit(1)
                                Spacer()
                                Text(lib.typeName)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Brand.secondaryLabel)
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(width: 300, height: 260)
    }

    // MARK: 路径导航条（右侧放库切换按钮）
    private var pathBar: some View {
        HStack(spacing: Spacing.xs) {
            Button { navigateUp() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(currentPath.isEmpty ? Brand.secondaryLabel.opacity(0.4) : Brand.label)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Brand.chipFill))
            }
            .buttonStyle(.plain)
            .disabled(currentPath.isEmpty)

            Text(currentPath.isEmpty ? "根目录" : currentPath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Brand.secondaryLabel)
                .lineLimit(1)
                .truncationMode(.head)
            // 上次扫描时间 + 手动刷新
            if let t = lastScanTime {
                Text("更新于 \(t, style: .time)")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.secondaryLabel.opacity(0.7))
            }
            Button { Task { await refresh() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isRefreshing ? Brand.secondaryLabel : Brand.label)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Brand.chipFill))
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing || isLoading)
            .help("重新扫描（跳过缓存）")
            Spacer()
            // 库切换按钮已挪到右上角 toolbar（同电视直播位置）
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: 内容
    @ViewBuilder
    private var content: some View {
        if nm.libraries.isEmpty {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "externaldrive.badge.plus")
                    .font(.system(size: 34))
                    .foregroundStyle(Brand.secondaryLabel)
                Text("尚未添加 NAS 资源库").font(Typography.body)
                Text("请到「设置 → 资源库」添加 WebDAV 或本机挂载目录")
                    .font(Typography.caption)
                    .foregroundStyle(Brand.secondaryLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            ErrorView(error, retry: { Task { await load() } })
        } else if allItems.isEmpty && isLoading {
            LoadingView("正在扫描媒体库…")
        } else if allItems.isEmpty && isRefreshing {
            LoadingView("正在刷新媒体库…")
        } else if allItems.isEmpty {
            EmptyState("该目录暂无视频", systemImage: "film", description: "支持 mp4 / mkv / mov / m4v / avi / wmv / flv / ts / m3u8")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(items) { d in
                        NASCard(d)
                            .onTapGesture { onSelect(d) }
                    }
                }
                .padding(Spacing.lg)
                // 底部加载更多哨兵：进入视口即触发下一批。
                // 用 Task 异步改 visibleCount（onAppear 同步改 @State 会被 SwiftUI 更新周期吞掉/延迟，
                // 表现为「只转圈不加载」），isExpanding 防抖防连续触发。
                if visibleCount < allItems.count {
                    HStack(spacing: Spacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("加载更多…（\(visibleCount)/\(allItems.count)）")
                            .font(Typography.caption)
                            .foregroundStyle(Brand.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Spacing.lg)
                    // 关键：visibleCount 变化强制哨兵重建，使 onAppear 能重复触发——
                    // 否则大屏下首屏卡片不足以把哨兵顶出视口，哨兵常驻视口不再触发，
                    // 表现为「偶尔只加载一次就不动了」。重建后若仍在视口则连续加载直到填满。
                    .id("sentinel-\(visibleCount)")
                    .onAppear { loadMore() }
                } else if allItems.count > pageSize {
                    Text("共 \(allItems.count) 个视频")
                        .font(Typography.caption)
                        .foregroundStyle(Brand.secondaryLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, Spacing.lg)
                }
            }
        }
    }

    /// 加载下一批可见卡片（懒渲染，数据已在 allItems，只是控制渲染数量）。
    @State private var isExpanding = false
    private func loadMore() {
        guard !isExpanding, visibleCount < allItems.count else { return }
        isExpanding = true
        Task { @MainActor in
            // 让出当前更新周期，避免 onAppear 内同步改 State 被吞
            try? await Task.sleep(nanoseconds: 30_000_000)
            visibleCount = min(visibleCount + pageSize, allItems.count)
            isExpanding = false
        }
    }

    private func navigateUp() {
        guard !currentPath.isEmpty else { return }
        let parts = currentPath.split(separator: "/").map(String.init)
        currentPath = parts.dropLast().joined(separator: "/")
        Task { await load() }
    }

    private var scanCacheKey: String { "nas:scan:\(currentLibId ?? ""):\(currentPath)" }

    /// 加载：先读磁盘扫描缓存（TTL 内直接显示，不重复全库扫描）→ 过期/无缓存才扫网络。
    /// force=true（手动刷新）跳过缓存强制重扫。
    private func load(force: Bool = false) async {
        guard let libId = currentLibId else { allItems = []; return }
        error = nil

        // ① 非强制刷新：先试磁盘缓存
        if !force {
            let cached = await DiskCache.shared.readFresh([Drama].self, key: scanCacheKey, maxAge: scanCacheTTL)
            if let items = cached.value, !items.isEmpty {
                allItems = items
                visibleCount = min(pageSize, items.count)
                if cached.fresh {
                    // 缓存新鲜：直接展示，不扫网络
                    lastScanTime = Date()
                    return
                }
                // 缓存过期：先展示旧缓存，再后台静默刷新
                isRefreshing = true
                await scanNetwork(libId: libId)
                isRefreshing = false
                return
            }
        }

        // ② 无缓存/强制刷新：全量扫描
        isLoading = true
        await scanNetwork(libId: libId)
        isLoading = false
    }

    /// 实际网络扫描 + 写缓存。
    private func scanNetwork(libId: String) async {
        do {
            let items = try await nm.browse(id: libId, path: currentPath)
            allItems = items
            visibleCount = min(pageSize, items.count)
            lastScanTime = Date()
            await DiskCache.shared.write(items, key: scanCacheKey)
        } catch {
            // 已有缓存内容时不报错覆盖，仅静默；无内容才显示错误
            if allItems.isEmpty {
                self.error = "加载失败：\(error.localizedDescription)"
            }
        }
    }

    /// 手动刷新：跳过缓存强制重扫。
    private func refresh() async {
        await load(force: true)
    }
}

/// NAS 视频卡片（无封面，暖沙底+播放图标占位；点击进详情选集）。
private struct NASCard: View {
    let drama: Drama
    init(_ d: Drama) { self.drama = d }

    @State private var coverURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.placeholder, Brand.secondaryBackground],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .aspectRatio(2/3, contentMode: .fit)
                if let coverURL, let img = NSImage(contentsOf: coverURL) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                } else {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Brand.accent.opacity(0.55))
                }
                if let st = drama.updateStatus, !st.isEmpty {
                    Text(st)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            Text(drama.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.label)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(drama.title)
                .frame(maxWidth: .infinity, alignment: .leading)
            // 固定信息行高度占位，避免卡片高度不一错位
            Text(" ")
                .font(.system(size: 12))
        }
        .contentShape(Rectangle())
        .task { await loadCover() }
    }

    /// 加载首帧封面：先查缓存，无则后台生成。
    private func loadCover() async {
        // id = nas|<libId>|file|<path>，需还原播放地址
        let parts = drama.id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4 else { return }
        guard let playURL = try? await NASManager.shared.playURLString(id: parts[1], path: parts[3]) else { return }
        if let url = await NASCoverGenerator.shared.cover(forVideoPlayURL: playURL) {
            coverURL = url
        }
    }
}
