import SwiftUI
import HongguoCore

/// 个人库：收藏 + 历史（含播放进度 / 秒级续播入口）。
public struct LibraryView: View {
    public enum Segment: String, CaseIterable, Identifiable {
        case history, favorite
        public var id: String { rawValue }
        var title: String {
            switch self { case .history: return "历史"; case .favorite: return "收藏" }
        }
    }

    let initial: Segment
    @State private var segment: Segment

    public init(initial: Segment = .history) {
        self.initial = initial
        _segment = State(initialValue: initial)
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            Divider()
            if segment == .history {
                HistoryListView()
            } else {
                FavoriteListView()
            }
        }
        .navigationTitle(segment.title)
        .frame(minWidth: 640, minHeight: 480)
    }
}

/// 收藏列表（支持编辑模式多选批量删除）。
struct FavoriteListView: View {
    @State private var items: [FavoriteItem] = []
    /// 集数懒回填结果（收藏存储无集数字段，后台经详情接口补全）
    @State private var counts: [String: Int] = [:]
    /// 编辑（多选删除）模式
    @State private var isEditing = false
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                EmptyState("还没有收藏", systemImage: "heart",
                           description: "在详情页点击「收藏」，喜欢的内容会在这里")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 编辑模式工具条
                if isEditing {
                    editBar
                    Divider()
                }
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150, maximum: 180), spacing: Spacing.md)],
                        spacing: Spacing.md
                    ) {
                        ForEach(items) { item in
                            ZStack(alignment: .topTrailing) {
                                PosterCard(Drama(id: item.dramaId, title: item.title,
                                                 coverURL: item.coverURL,
                                                 episodeCount: counts[item.dramaId]))
                                    .onTapGesture {
                                        if isEditing { toggleSelect(item.dramaId) } else { open(item) }
                                    }
                                    .overlay(selectionOverlay(item.dramaId))
                                    .contextMenu {
                                        if !isEditing {
                                            Button("查看详情") { open(item) }
                                            Button("取消收藏", role: .destructive) { remove(item) }
                                        }
                                    }
                            }
                        }
                    }
                    .padding(Spacing.md)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .toolbar {
            ToolbarItem {
                if !items.isEmpty {
                    Button(isEditing ? "完成" : "选择") {
                        isEditing.toggle()
                        if !isEditing { selected.removeAll() }
                    }
                }
            }
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .hongguoLibraryChanged)) { _ in reload() }
        .task(id: items) { await backfillCounts() }
    }

    // MARK: 编辑工具条
    private var editBar: some View {
        HStack(spacing: Spacing.md) {
            Button(selected.count == items.count ? "取消全选" : "全选") {
                selected = selected.count == items.count ? [] : Set(items.map(\.dramaId))
            }
            .controlSize(.small)
            Text("已选 \(selected.count) 项")
                .font(Typography.caption)
                .foregroundStyle(Brand.secondaryLabel)
            Spacer()
            Button("删除选中", role: .destructive) { removeSelected() }
                .controlSize(.small)
                .disabled(selected.isEmpty)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(Brand.chipFill)
    }

    /// 编辑模式下的选中圈/勾。
    private func selectionOverlay(_ dramaId: String) -> some View {
        Group {
            if isEditing {
                let on = selected.contains(dramaId)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(on ? Brand.accent : Color.white)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .padding(8)
            }
        }
    }

    private func toggleSelect(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func reload() { items = Repository.shared.favorites() }

    private func backfillCounts() async {
        let dramas = items.map { Drama(id: $0.dramaId, title: $0.title, coverURL: $0.coverURL) }
        await CountBackfiller.shared.backfill(dramas) { id, count in
            counts[id] = count
        }
    }

    private func open(_ item: FavoriteItem) {
        NotificationCenter.default.post(
            name: .hongguoOpenDrama,
            object: Drama(id: item.dramaId, title: item.title, coverURL: item.coverURL)
        )
    }

    private func remove(_ item: FavoriteItem) {
        Repository.shared.removeFavorite(dramaId: item.dramaId)
        reload()
    }

    private func removeSelected() {
        Repository.shared.removeFavorites(dramaIds: selected)
        selected.removeAll()
        isEditing = false
        reload()
    }
}

/// 历史 / 播放进度列表（支持滑动删除 + 编辑模式多选批量删除）。
struct HistoryListView: View {
    @State private var items: [HistoryItem] = []
    @State private var isEditing = false
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                EmptyState("还没有观看记录", systemImage: "clock",
                           description: "播放过的短剧会自动记录进度，可从此续播")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if isEditing {
                    editBar
                    Divider()
                }
                List {
                    ForEach(items) { item in
                        HStack(spacing: Spacing.sm) {
                            if isEditing {
                                let on = selected.contains(item.key)
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(on ? Brand.accent : Brand.secondaryLabel)
                                    .onTapGesture { toggleSelect(item.key) }
                            }
                            HistoryRow(item: item)
                        }
                    }
                    .onDelete { offsets in
                        if !isEditing {
                            for i in offsets { Repository.shared.removeHistory(items[i]) }
                            reload()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .toolbar {
            ToolbarItem {
                if !items.isEmpty {
                    Button(isEditing ? "完成" : "选择") {
                        isEditing.toggle()
                        if !isEditing { selected.removeAll() }
                    }
                }
            }
            ToolbarItem {
                if !items.isEmpty && !isEditing {
                    Button("清空") { Repository.shared.clearHistory(); reload() }
                }
            }
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .hongguoLibraryChanged)) { _ in reload() }
    }

    private var editBar: some View {
        HStack(spacing: Spacing.md) {
            Button(selected.count == items.count ? "取消全选" : "全选") {
                selected = selected.count == items.count ? [] : Set(items.map(\.key))
            }
            .controlSize(.small)
            Text("已选 \(selected.count) 项")
                .font(Typography.caption)
                .foregroundStyle(Brand.secondaryLabel)
            Spacer()
            Button("删除选中", role: .destructive) { removeSelected() }
                .controlSize(.small)
                .disabled(selected.isEmpty)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(Brand.chipFill)
    }

    private func toggleSelect(_ key: String) {
        if selected.contains(key) { selected.remove(key) } else { selected.insert(key) }
    }

    private func removeSelected() {
        Repository.shared.removeHistories(keys: selected)
        selected.removeAll()
        isEditing = false
        reload()
    }

    private func reload() { items = Repository.shared.history() }
}

/// 单条历史行：封面 + 标题 + 集数 + 进度 + 续播。
struct HistoryRow: View {
    let item: HistoryItem
    /// 正在拉详情/播放（防连点 + 行内反馈）
    @State private var isOpening = false
    /// 打开失败提示（代替「一点反应没有」）
    @State private var openError: String?

    var body: some View {
        Button { resume() } label: {
            HStack(spacing: Spacing.md) {
                Group {
                    if let urlStr = item.coverURL, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            case .failure: Brand.placeholder
                            default: ProgressView()
                            }
                        }
                    } else { Brand.placeholder }
                }
                .frame(width: 60, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(item.title).font(Typography.body).foregroundStyle(Brand.label).lineLimit(1)
                    Text(item.episodeTitle).font(Typography.caption).foregroundStyle(Brand.secondaryLabel).lineLimit(1)
                    if item.duration > 0 {
                        ProgressView(value: min(item.position, item.duration), total: item.duration)
                            .tint(Brand.pink)
                        Text("看到 \(HongguoFormat.duration(item.position)) / \(HongguoFormat.duration(item.duration))")
                            .font(.caption2).foregroundStyle(Brand.secondaryLabel)
                    } else {
                        Text("已观看").font(.caption2).foregroundStyle(Brand.secondaryLabel)
                    }
                    Text(HongguoFormat.relative(item.updatedAt))
                        .font(.caption2).foregroundStyle(Brand.secondaryLabel)
                }
                Spacer()
                if isOpening {
                    ProgressView().controlSize(.regular)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Brand.pink)
                }
            }
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isOpening)
        .alert("无法打开", isPresented: Binding(
            get: { openError != nil },
            set: { if !$0 { openError = nil } }
        )) {
            Button("知道了", role: .cancel) { openError = nil }
        } message: {
            Text(openError ?? "")
        }
    }

    /// 点击历史：能续播的直接拉详情进播放器（定位到历史那一集）；
    /// 拉不到详情则退回打开详情页（可换源/看简介）；详情页也加载失败才弹提示。
    /// 绝不「一点反应没有」。
    private func resume() {
        if isOpening { return }
        isOpening = true
        Task {
            defer { isOpening = false }
            do {
                let detail = try await loadDetail()
                guard !detail.episodes.isEmpty else {
                    openDetailFallback(reason: "该剧暂无分集资源")
                    return
                }
                let idx = detail.episodes.firstIndex(where: { $0.id == item.episodeId }) ?? 0
                NotificationCenter.default.post(
                    name: .hongguoPlayDetail,
                    object: PlayerPayload(id: detail.drama.id, detail: detail, index: idx)
                )
            } catch {
                openDetailFallback(reason: error.localizedDescription)
            }
        }
    }

    /// 按 id 前缀分流拉详情（tvbox / nas / 旧红果 id）。
    private func loadDetail() async throws -> DramaDetail {
        let id = item.dramaId
        if id.hasPrefix("tvbox|") {
            let parts = id.split(separator: "|").map(String.init)
            guard parts.count == 3 else { throw HongguoParseError.fieldMissing("tvbox id") }
            return try await SourceManager.shared.tvboxDetail(siteKey: parts[1], vodId: parts[2])
        } else if id.hasPrefix("nas|") {
            let parts = id.split(separator: "|", maxSplits: 3).map(String.init)
            guard parts.count == 4 else { throw HongguoParseError.fieldMissing("nas id") }
            if parts[2] == "dir" {
                return try await NASManager.shared.detail(id: parts[1], dirPath: parts[3])
            }
            let url = try await NASManager.shared.playURLString(id: parts[1], path: parts[3])
            return DramaDetail(
                drama: Drama(id: id, title: item.title, coverURL: item.coverURL),
                episodes: [Episode(id: "1", index: 1, title: item.title, playURL: url)]
            )
        }
        return try await CatalogService.shared.detail(id: id)
    }

    /// 续播失败 → 打开详情页兜底（可换源/看简介）；详情也加载失败 → 弹错误提示。
    private func openDetailFallback(reason: String) {
        let drama = Drama(id: item.dramaId, title: item.title, coverURL: item.coverURL)
        NotificationCenter.default.post(
            name: .hongguoOpenDramaSheet,
            object: DetailRequest(drama: drama, onLoadFailed: { err in
                openError = "「\(item.title)」暂时无法打开：\(err)。源站可能已失效，可在视频源做连通性测试或换源搜索。"
            })
        )
    }
}

/// 详情请求（带失败回调），经 .hongguoOpenDramaSheet 通知 CatalogView 弹详情页。
struct DetailRequest {
    let drama: Drama
    let onLoadFailed: (String) -> Void
}

extension Notification.Name {
    static let hongguoLibraryChanged = Notification.Name("hongguoLibraryChanged")
    static let hongguoPlayDetail = Notification.Name("hongguoPlayDetail")
    static let hongguoOpenDramaSheet = Notification.Name("hongguoOpenDramaSheet")
}
