import SwiftUI
import HongguoGatewayCore

// MARK: - 统一媒体中枢（M4 超越点）
// 对标 Cinetry「左侧服务器一键切换栏 + 实时连接状态指示 + 聚合首页」。
// 数据源走网关统一聚合层（/api/servers、/api/aggregate/*），
// 把红果/TVBox/NAS/IPTV/Emby/Jellyfin/AList/Subsonic/audiobookshelf 收敛到一个入口。

/// 服务器连接状态视图对象（对端 /api/servers）。
struct ServerVO: Codable, Identifiable {
    let id, kind, name: String
    let online: Bool, latencyMs: Int
    let canTranscode, canSearch: Bool
}

@MainActor
final class MediaHubViewModel: ObservableObject {
    @Published var servers: [ServerVO] = []
    @Published var focusedID: String? = nil          // nil = 聚合模式
    @Published var continueWatching: [MediaItem] = []
    @Published var recentlyAdded: [MediaItem] = []
    @Published var isLoading = false
    @Published var error: String?

    private var base: URL { URL(string: "http://127.0.0.1:\(AppSettings.shared.gatewayPort)")! }

    /// 直连网关的 URLSession（绕过系统代理；127.0.0.1 本不应走代理，但部分全局代理会拦）。
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.connectionProxyDictionary = [:]
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    /// 等待网关就绪（启动窗口期轮询 health，最多 ~10s），避免网关未起听时请求一次性失败。
    private func waitGatewayReady() async -> Bool {
        for _ in 0..<20 {
            if let (data, resp) = try? await session.data(from: base.appendingPathComponent("api/health")),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               obj["ok"] != nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    /// 拉服务器列表（后端已缓存连接状态秒回；后台异步 probe 刷新）。
    /// 只展示在线源（失败源不显示，符合「首页不展示失败源」要求）。
    func loadServers() async {
        guard await waitGatewayReady() else { self.error = "网关未就绪"; return }
        do {
            let (data, _) = try await session.data(from: base.appendingPathComponent("api/servers"))
            struct Env: Codable { let ok: Bool; let data: [ServerVO]? }
            let env = try JSONDecoder().decode(Env.self, from: data)
            let all = env.data ?? []
            // 过滤失败源：在线 或 未标定(刚启动) 的显示；明确 offline 的不显示
            servers = all.filter { $0.online }
            if servers.isEmpty { servers = all }  // 全失败时也兜底显示，避免空侧栏
        } catch {
            self.error = "服务器列表加载失败"
        }
    }

    /// 聚焦/取消聚焦某服务器。
    func focus(_ id: String?) async {
        focusedID = id
        await loadHome()
    }

    /// 聚合首页（继续观看 + 最新入库）。等网关就绪 + 失败自动重试，避免启动窗口期一次性失败。
    func loadHome() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        guard await waitGatewayReady() else {
            self.error = "本地网关未启动，请重启应用"
            return
        }
        // 最多尝试 3 次（指数退避），个别慢响应自动重试
        for attempt in 0..<3 {
            do {
                var req = URLRequest(url: base.appendingPathComponent("api/aggregate/home?limit=24"))
                req.timeoutInterval = 15
                req.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, _) = try await session.data(for: req)
                struct HomeVO: Codable { let continueWatching, recentlyAdded: [MediaItem] }
                struct Env: Codable { let ok: Bool; let data: HomeVO? }
                let env = try JSONDecoder().decode(Env.self, from: data)
                continueWatching = env.data?.continueWatching ?? []
                recentlyAdded = env.data?.recentlyAdded ?? []
                if continueWatching.isEmpty && recentlyAdded.isEmpty {
                    self.error = "暂无在线源返回内容，请稍后重试或检查服务器连接"
                } else {
                    self.error = nil
                }
                return  // 成功即返回
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64((attempt + 1)) * 1_000_000_000)
                    continue
                }
                self.error = "聚合首页加载失败（源响应超时，可重试）"
            }
        }
    }
}

public struct MediaHubView: View {
    @StateObject private var vm = MediaHubViewModel()
    var onSelect: (MediaItem) -> Void

    public init(onSelect: @escaping (MediaItem) -> Void = { _ in }) {
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationSplitView {
            serverSidebar
        } detail: {
            homeContent
        }
        .task {
            await vm.loadServers()
            await vm.loadHome()
        }
    }

    // MARK: 左侧：服务器一键切换栏 + 实时状态
    private var serverSidebar: some View {
        List(selection: $vm.focusedID) {
            // 聚合模式（全部服务器）
            Button {
                Task { await vm.focus(nil) }
            } label: {
                HStack {
                    Label("聚合（全部）", systemImage: "square.grid.2x2")
                    Spacer()
                    if vm.focusedID == nil { Image(systemName: "checkmark") .foregroundStyle(.tint) }
                }
            }
            .buttonStyle(.plain)
            .tag(String?.none)

            Section("媒体服务器") {
                ForEach(vm.servers) { s in
                    Button {
                        Task { await vm.focus(s.id) }
                    } label: {
                        HStack(spacing: 8) {
                            statusDot(online: s.online)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name).font(.system(size: 13))
                                Text("\(kindLabel(s.kind)) · \(s.latencyMs)ms")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if vm.focusedID == s.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                    .buttonStyle(.plain)
                    .tag(String?.some(s.id))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("媒体中枢")
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        .toolbar {
            ToolbarItem {
                Button { Task { await vm.loadServers() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新连接状态")
            }
        }
    }

    private func statusDot(online: Bool) -> some View {
        Circle()
            .fill(online ? Color.green : Color.red)
            .frame(width: 8, height: 8)
    }

    // MARK: 右侧：聚合首页（继续观看 + 最新入库）
    @ViewBuilder
    private var homeContent: some View {
        if vm.isLoading && vm.continueWatching.isEmpty && vm.recentlyAdded.isEmpty {
            LoadingView("加载聚合首页…")
        } else if let err = vm.error, vm.continueWatching.isEmpty {
            ErrorView(err, retry: { Task { await vm.loadHome() } })
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if !vm.continueWatching.isEmpty {
                        sectionHeader("继续观看", icon: "play.circle")
                        itemRow(vm.continueWatching)
                    }
                    if !vm.recentlyAdded.isEmpty {
                        sectionHeader("最新入库", icon: "sparkles")
                        itemRow(vm.recentlyAdded)
                    }
                    if vm.continueWatching.isEmpty && vm.recentlyAdded.isEmpty {
                        EmptyState("暂无内容", systemImage: "tray",
                                   description: "添加媒体服务器或开始播放后，这里会聚合展示")
                    }
                }
                .padding(20)
            }
            .navigationTitle(vm.focusedID.flatMap { id in vm.servers.first { $0.id == id }?.name } ?? "聚合首页")
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.title3.weight(.semibold))
    }

    private func itemRow(_ items: [MediaItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(items) { item in
                    Button { onSelect(item) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            posterView(item)
                                .frame(width: 120, height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Text(item.title)
                                .font(.caption)
                                .lineLimit(2)
                                .frame(width: 120, alignment: .leading)
                            sourceBadge(item.sourceKey)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func posterView(_ item: MediaItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.15))
            if let p = item.poster, let url = URL(string: p) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "film").foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "film").foregroundStyle(.secondary)
            }
        }
        .clipped()
    }

    /// 来源标注徽章（对标 Cinetry 来源标注）。
    private func sourceBadge(_ sourceKey: String) -> some View {
        let name = vm.servers.first { $0.id == sourceKey }?.name ?? sourceKey
        return Text(name)
            .font(.system(size: 9))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }

    private func kindLabel(_ kind: String) -> String {
        switch kind {
        case "hongguo": return "红果短剧"
        case "tvbox": return "TVBox"
        case "emby": return "Emby"
        case "jellyfin": return "Jellyfin"
        case "webdav", "mount": return "NAS"
        case "alist", "openlist": return "AList"
        case "subsonic", "navidrome": return "音乐"
        case "audiobookshelf": return "听书"
        case "iptv": return "直播"
        default: return kind
        }
    }
}
