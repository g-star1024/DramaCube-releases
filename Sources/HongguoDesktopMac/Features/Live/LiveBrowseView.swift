import SwiftUI
import HongguoCore

/// 电视直播浏览页：分组 chips + 频道网格（logo + 名称），点击即播（单集直播流）。
///
/// 频道来自 LiveEngine 多源排重合并（按 name|group 去重），按 group 分组。
/// 播放走网关直播代理（统一 UA okHttp/Mod-1.5.0.0 防盗链）。
struct LiveBrowseView: View {
    @ObservedObject private var lm = LiveManager.shared

    @State private var channels: [LiveManager.LiveChannel] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedGroup: String? // nil = 全部
    @State private var playError: String?
    /// 连通性结果：channelId -> true绿/false红；nil=未测试
    @State private var reachability: [String: Bool] = [:]
    @State private var isTesting = false
    /// 直播源切换弹层
    @State private var showSourcePicker = false
    /// 各源探活频道数（sourceId -> count）
    @State private var sourceCounts: [String: Int] = [:]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 5)

    /// 分组列表（保持出现顺序）。
    private var groups: [String] {
        var seen: [String] = []
        for ch in channels where !seen.contains(ch.group) { seen.append(ch.group) }
        return seen
    }

    private var shown: [LiveManager.LiveChannel] {
        // 已测试且失败的频道不再出现在切换列表（实际不可用）
        let available = channels.filter { reachability[$0.id] != false }
        guard let g = selectedGroup else { return available }
        return available.filter { $0.group == g }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !groups.isEmpty {
                groupBar
                Divider()
            }
            content
        }
        .background(Brand.background)
        .navigationTitle("电视直播")
        .toolbar {
            // 直播源切换按钮（当前源名 + 点击弹源列表）
            ToolbarItem(placement: .automatic) {
                Button { showSourcePicker = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .semibold))
                        Text(activeSourceName)
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
                .help("当前直播源：\(activeSourceName)，点击切换")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await runConnectivityTest() }
                } label: {
                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("测试连通", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                .disabled(isTesting || channels.isEmpty)
                .help("测试所有频道流可达性，绿点=可播，红点=不可达")
            }
        }
        .popover(isPresented: $showSourcePicker, arrowEdge: .top) { sourcePicker }
        .task { await load() }
        .alert("播放失败", isPresented: Binding(get: { playError != nil }, set: { if !$0 { playError = nil } })) {
            Button("好", role: .cancel) { playError = nil }
        } message: {
            Text(playError ?? "")
        }
    }

    // MARK: 分组条
    private var groupBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                groupChip(nil, "全部")
                ForEach(groups, id: \.self) { g in
                    groupChip(g, g)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.xs)
        }
    }

    private func groupChip(_ g: String?, _ name: String) -> some View {
        let active = selectedGroup == g
        return Button { selectedGroup = g } label: {
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
        if isLoading && channels.isEmpty {
            LoadingView("正在加载直播频道…")
        } else if let error {
            ErrorView(error, retry: { Task { await load() } })
        } else if channels.isEmpty {
            EmptyState("暂无直播频道", systemImage: "tv",
                       description: "请到「设置 → 电视直播」添加 m3u 直播源")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.lg) {   // 加大频道卡片间距，避免挤在一起
                    ForEach(shown) { ch in
                        LiveChannelCard(ch, reachable: reachability[ch.id])
                            .onTapGesture { play(ch) }
                    }
                }
                .padding(Spacing.lg)
            }
        }
    }

    // MARK: 加载
    /// 当前启用的直播源名（单选模式下唯一 enabled 的源）。
    private var activeSourceName: String {
        lm.sources.first(where: \.enabled)?.name ?? "未选择"
    }

    /// 直播源切换弹层：列出全部源（含探活频道数），单选切换。
    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("选择直播源")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("同一时刻只用一个源")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.secondaryLabel)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // 后台被关闭（enabled=false）的源不在切换弹层展示
                    ForEach(lm.sources.filter(\.enabled)) { s in
                        let isActive = s.enabled
                        Button {
                            Task { await switchSource(s) }
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isActive ? Brand.accent : Brand.secondaryLabel)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.name).font(Typography.body).lineLimit(1)
                                    if let c = sourceCounts[s.id] {
                                        Text(c > 0 ? "\(c) 个频道" : "源失效/无频道")
                                            .font(.system(size: 10))
                                            .foregroundStyle(c > 0 ? Brand.secondaryLabel : .red)
                                    }
                                }
                                Spacer()
                                if isActive {
                                    Text("当前").font(.system(size: 10)).foregroundStyle(Brand.accent)
                                }
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Divider()
            HStack {
                Spacer()
                Text("管理直播源请到「设置 → 电视直播」")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.secondaryLabel)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 6)
            }
        }
        .frame(width: 320, height: 380)
        .onAppear { Task { await probeSources() } }
    }

    /// 切换直播源：单选启用该源，重新拉频道。
    private func switchSource(_ s: LiveManager.LiveSource) async {
        showSourcePicker = false
        await lm.setActive(id: s.id)
        selectedGroup = nil
        reachability = await lm.savedReachability()
        await load()
    }

    /// 探活所有源（后台逐个拉取返回频道数，弹层展示可用性）。只探启用源。
    private func probeSources() async {
        for s in lm.sources where s.enabled && sourceCounts[s.id] == nil {
            let c = await lm.testSource(id: s.id)
            sourceCounts[s.id] = c
        }
    }

    private func load() async {
        isLoading = true; error = nil
        lm.load()
        // 先恢复上次持久化的连通性结果（角标状态重启不丢，失败频道立即被过滤）
        reachability = await lm.savedReachability()
        do {
            channels = try await lm.channels()
            AppLog.log(.app, "直播频道加载完成：\(channels.count) 个（\(groups.count) 组）")
        } catch {
            self.error = "加载失败：\(error.localizedDescription)"
            AppLog.log(.error, "直播频道加载失败：\(error.localizedDescription)")
        }
        isLoading = false
    }

    /// 批量连通性测试：绿点=可播，红点=不可达。
    private func runConnectivityTest() async {
        guard !channels.isEmpty else { return }
        isTesting = true
        let result = await lm.testChannels(channels)
        reachability = result
        let ok = result.values.filter { $0 }.count
        AppLog.log(.app, "直播连通性测试：\(ok)/\(result.count) 可播")
        isTesting = false
    }

    // MARK: 播放（直播即单集流，直接进播放器）
    private func play(_ ch: LiveManager.LiveChannel) {
        let stream = lm.streamURLString(channelURL: ch.url)
        let drama = Drama(id: "live|\(ch.id)", title: ch.name, coverURL: ch.logo,
                          tags: [ch.group], category: ch.group)
        let ep = Episode(id: "live", index: 1, title: ch.name, playURL: stream)
        let detail = DramaDetail(drama: drama, episodes: [ep])
        NotificationCenter.default.post(
            name: .hongguoPlayDetail,
            object: PlayerPayload(id: drama.id, detail: detail, index: 0)
        )
    }
}

/// 直播频道卡片：logo + 名称 + 分组徽标 + 右上角连通性角标。
private struct LiveChannelCard: View {
    let channel: LiveManager.LiveChannel
    /// nil=未测试，true=可播（绿），false=不可达（红）
    let reachable: Bool?
    init(_ c: LiveManager.LiveChannel, reachable: Bool? = nil) {
        self.channel = c
        self.reachable = reachable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Brand.placeholder)
                    .aspectRatio(16/9, contentMode: .fit)
                if let logo = channel.logo, let url = URL(string: logo) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFit().padding(14)
                        case .failure:
                            fallbackIcon
                        default:
                            ProgressView().controlSize(.small)
                        }
                    }
                } else {
                    fallbackIcon
                }
                // 分组徽标
                Text(channel.group)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(5)
                // 连通性角标（右上角）：绿=可播，红=不可达
                if let reachable {
                    Circle()
                        .fill(reachable ? Color.green : Color.red)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(6)
                        .help(reachable ? "可正常播放" : "当前不可达")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            Text(channel.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Brand.label)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(channel.name)
        }
        .contentShape(Rectangle())
    }

    private var fallbackIcon: some View {
        Image(systemName: "tv.fill")
            .font(.system(size: 30))
            .foregroundStyle(Brand.accent.opacity(0.5))
    }
}
