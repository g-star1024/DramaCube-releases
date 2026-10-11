import SwiftUI
import HongguoCore

public enum SidebarItem: String, CaseIterable, Identifiable {
    case rank, tvbox, nas, live, library, downloads, settings
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .rank: return "发现"
        case .tvbox: return "视频源"
        case .nas: return "资源库"
        case .live: return "电视直播"
        case .library: return "历史收藏"
        case .downloads: return "下载"
        case .settings: return "设置"
        }
    }
    public var icon: String {
        switch self {
        case .rank: return "sparkles"
        case .tvbox: return "antenna.radiowaves.left.and.right"
        case .nas: return "externaldrive.connected.to.line.below"
        case .live: return "tv"
        case .library: return "bookmark"
        case .downloads: return "arrow.down.circle"
        case .settings: return "gearshape"
        }
    }
}

public struct CatalogView: View {
    @StateObject private var service = CatalogService.shared
    @State private var selection: SidebarItem = .rank
    @State private var query = ""
    /// 搜索模式标记（空串=未搜索）。结果在 SearchResultsView 内流式自管理。
    @State private var searchActive: String?
    /// 点搜索结果正在拉详情准备播放（直拨加载态）
    @State private var openingMatch: SourceMatch?
    @State private var openError: String?

    @State private var selected: Drama?
    @State private var pendingPlay: PlayerPayload?
    /// 历史页兜底详情请求（带加载失败回调）
    @State private var detailRequest: DetailRequest?

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon)
                    .font(.system(size: 14))
                    .padding(.vertical, 7)   // 加大频道行距，避免挤在一起
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationTitle("剧立方")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            Group {
                if let kw = searchActive {
                    searchContent(keyword: kw)
                } else {
                    sectionContent
                }
            }
            .frame(minWidth: 640, minHeight: 480)
            .searchable(text: $query, prompt: "搜索短剧、剧名")
            .onSubmit(of: .search) {
                let q = query.trimmingCharacters(in: .whitespaces)
                searchActive = q.isEmpty ? nil : q
            }
            .onChange(of: query) { _, new in
                if new.trimmingCharacters(in: .whitespaces).isEmpty { searchActive = nil }
            }
            .navigationTitle(showTitle)
        }
        .task {
            // 封面图磁盘缓存：AsyncImage 走 URLSession.shared → URLCache.shared，
            // 扩容后海报/剧照自动落盘，二次打开离线可显。
            if URLCache.shared.memoryCapacity < 64 << 20 {
                URLCache.shared = URLCache(memoryCapacity: 64 << 20,
                                           diskCapacity: 512 << 20,
                                           diskPath: "dramacube-images")
            }
            GatewayController.shared.start()
            BossKeyManager.shared.start()
            SourceManager.shared.load()
            MenuBarController.shared.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hongguoOpenDrama)) { note in
            if let d = note.object as? Drama { selected = d }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hongguoOpenDramaSheet)) { note in
            if let req = note.object as? DetailRequest { detailRequest = req }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hongguoPlayDetail)) { note in
            if let payload = note.object as? PlayerPayload {
                selected = nil
                detailRequest = nil
                pendingPlay = payload
            }
        }
        .sheet(item: $selected) { drama in
            DetailView(drama: drama) { detail, idx in
                // 先收起 sheet，等收起动画完成后再开播放器窗口。
                // 之前直接 show() 会打断 sheet 收起，sheet 残留并拦截全局鼠标事件。
                pendingPlay = PlayerPayload(id: detail.drama.id, detail: detail, index: idx)
                selected = nil
            }
        }
        // 历史页兜底详情：加载失败时回调历史行弹提示，并自动关掉详情页
        .sheet(item: Binding(
            get: { detailRequest.map { IdentifiedDetailRequest(req: $0) } },
            set: { detailRequest = $0?.req }
        )) { wrapped in
            DetailView(drama: wrapped.req.drama, onLoadFailed: { err in
                wrapped.req.onLoadFailed(err)
                detailRequest = nil
            }) { detail, idx in
                pendingPlay = PlayerPayload(id: detail.drama.id, detail: detail, index: idx)
                detailRequest = nil
            }
        }
        .onChange(of: pendingPlay) { _, payload in
            guard let payload else { return }
            pendingPlay = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // 设置了默认外部播放器：直接跳外部播放器，不创建内置播放器窗口
                if PlayerViewModel.openInDefaultExternalPlayerIfSet(detail: payload.detail, index: payload.index) {
                    return
                }
                PlayerWindowManager.shared.show(detail: payload.detail, startIndex: payload.index)
            }
        }
    }

    private var showTitle: String {
        if searchActive != nil { return "搜索" }
        return selection.title
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selection {
        case .rank:
            RankView(onSelect: openDetail)
        case .tvbox:
            TVBoxBrowseView(sm: SourceManager.shared, onSelect: openDetail)
        case .nas:
            NASBrowseView(nm: NASManager.shared, onSelect: openDetail)
        case .live:
            LiveBrowseView()
        case .library:
            LibraryView(initial: .history)
        case .downloads:
            DownloadsView()
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private func searchContent(keyword: String) -> some View {
        if let err = openError {
            // 点结果拉详情失败：停留可重试/返回
            VStack(spacing: Spacing.md) {
                ErrorView(err, retry: {
                    if let m = openingMatch { Task { await openMatch(m) } }
                })
                Button("返回搜索结果") { openError = nil; openingMatch = nil }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let m = openingMatch {
            LoadingView("正在打开「\(m.siteName)」准备播放…")
        } else {
            SearchResultsView(keyword: keyword) { match in
                Task { await openMatch(match) }
            }
        }
    }

    private func openDetail(_ drama: Drama) { selected = drama }

    /// 点搜索结果 → 拉该源详情后**直接播放**（复用点源即播链路）。
    private func openMatch(_ m: SourceMatch) async {
        openingMatch = m; openError = nil
        do {
            let parts = m.drama.id.split(separator: "|").map(String.init)
            guard parts.count == 3 else { throw HongguoParseError.fieldMissing("tvbox id") }
            let det = try await SourceManager.shared.tvboxDetail(siteKey: parts[1], vodId: parts[2])
            guard !det.episodes.isEmpty else {
                openError = "「\(m.siteName)」该剧暂无分集资源，可换其他结果"
                return
            }
            openingMatch = nil
            pendingPlay = PlayerPayload(id: det.drama.id, detail: det, index: 0)
        } catch {
            openError = "加载失败：\(error.localizedDescription)，可换其他结果"
        }
    }
}

/// 播放器入参包装（Identifiable 以便 sheet）。
struct PlayerPayload: Identifiable, Equatable {
    let id: String
    let detail: DramaDetail
    let index: Int

    static func == (lhs: PlayerPayload, rhs: PlayerPayload) -> Bool {
        lhs.id == rhs.id && lhs.index == rhs.index
    }
}

/// DetailRequest 的 Identifiable 包装（sheet(item:) 需要）。
struct IdentifiedDetailRequest: Identifiable {
    let req: DetailRequest
    var id: String { req.drama.id }
}

extension Notification.Name {
    /// 播放器独立窗口被关闭（红 × / ⌘W），PlayerView 收到后停播存进度。
    static let hongguoPlayerWindowClosed = Notification.Name("hongguoPlayerWindowClosed")
}

/// 播放器独立窗口管理器。
///
/// 播放器不再以 sheet 弹出（sheet 挂在主窗口上无法进入全屏），
/// 而是创建带 `.fullScreen` 样式掩码的独立 NSWindow，
/// 「全屏」按钮与绿色交通灯均可用；关闭时回调 PlayerView 停播存进度。
@MainActor
final class PlayerWindowManager {
    static let shared = PlayerWindowManager()
    private var window: NSWindow?
    private let closeDelegate = WindowCloseDelegate()
    // 手动全屏状态（此环境原生 toggleFullScreen 无效，见验证记录）
    private var savedFrame: NSRect?
    private var savedStyleMask: NSWindow.StyleMask?
    // 全屏中 Esc 退出（borderless 下 SwiftUI keyboardShortcut 不可靠，用 AppKit 监听兜底）
    private var escMonitor: Any?

    func show(detail: DramaDetail, startIndex: Int) {
        close()
        AppLog.log(.player, "播放窗口创建《\(detail.drama.title)》")
        let root = PlayerView(detail: detail, startIndex: startIndex) { [weak self] in
            self?.close()
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        w.title = detail.drama.title
        w.contentView = NSHostingView(rootView: root)
        w.center()
        w.isReleasedWhenClosed = false
        w.titlebarAppearsTransparent = false
        w.tabbingMode = .disallowed
        // 点标题栏红色 × 关闭时，也要通知 PlayerView 停播 + 存进度
        closeDelegate.onClose = {
            NotificationCenter.default.post(name: .hongguoPlayerWindowClosed, object: nil)
        }
        w.delegate = closeDelegate
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
        installEscMonitor()
    }

    /// Esc 键监听：手动全屏中拦截并退出全屏；非全屏放行给 SwiftUI（× 按钮关闭）。
    private func installEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.window?.isKeyWindow == true,
                  self?.isManuallyFullscreen == true else { return event }
            MainActor.assumeIsolated {
                self?.toggleFullscreen()
            }
            return nil
        }
    }

    private func removeEscMonitor() {
        if let m = escMonitor { NSEvent.removeMonitor(m) }
        escMonitor = nil
    }

    /// 播放器是否在前台（用于 PlayerView 判断走哪条全屏路径）。
    var hasWindow: Bool { window?.isVisible == true }

    /// 当前处于手动全屏。
    var isManuallyFullscreen: Bool { savedFrame != nil }

    /// 竖版视频窗口自适应：9:16 短剧收窄窗口消除左右黑边。
    /// 竖版 → 窗口高 844（视频区 800 + 控制条约 44），宽 = 视频区高 × 9/16 = 450，即视频区严格 9:16；
    /// 横版 → 恢复 960×620。全屏中不动（全屏本身铺满，由 AVLayer gravity 处理）。
    func adaptToVideo(portrait: Bool) {
        guard let w = window, w.isVisible, savedFrame == nil else { return }
        // 9:16：宽 = 高 × 9/16。视频区高取 800 → 宽 450；窗口总高 = 800 + 控制条约 44 = 844。
        let target: NSSize = portrait ? NSSize(width: 450, height: 844) : NSSize(width: 960, height: 620)
        // 尺寸已接近就不动（避免每集切换抖动）
        if abs(w.frame.width - target.width) < 8 && abs(w.frame.height - target.height) < 8 { return }
        var f = w.frame
        f.size = target
        f.origin.x += (w.frame.width - target.width) / 2
        f.origin.y += (w.frame.height - target.height) / 2
        // 防止超出屏幕
        if let screen = w.screen {
            f.origin.x = max(screen.visibleFrame.minX, min(f.origin.x, screen.visibleFrame.maxX - target.width))
            f.origin.y = max(screen.visibleFrame.minY, min(f.origin.y, screen.visibleFrame.maxY - target.height))
        }
        w.setFrame(f, display: true, animate: true)
        AppLog.log(.player, "播放窗口自适应：\(portrait ? "竖版 9:16" : "横版") \(Int(target.width))x\(Int(target.height))")
    }

    /// 切换播放器窗口全屏。
    ///
    /// 注：原生 `toggleFullScreen` 在部分环境（共享屏幕/受限窗口服务器）会静默失效，
    /// 已实测最小 AppKit 样例同样无效，因此这里用手动全屏：borderless 铺满屏幕 + 自动隐藏菜单栏。
    func toggleFullscreen() {
        guard let w = window, w.isVisible else { return }
        if savedFrame != nil {
            // 退出手动全屏
            if let f = savedFrame {
                w.styleMask = savedStyleMask ?? [.titled, .closable, .miniaturizable, .resizable]
                w.titlebarAppearsTransparent = false
                w.setFrame(f, display: true, animate: true)
            }
            savedFrame = nil
            savedStyleMask = nil
            NSApp.presentationOptions.remove(.autoHideMenuBar)
        } else {
            // 进入手动全屏
            savedFrame = w.frame
            savedStyleMask = w.styleMask
            w.styleMask = [.borderless, .resizable]
            w.titlebarAppearsTransparent = true
            if let screen = w.screen ?? NSScreen.main {
                w.setFrame(screen.frame, display: true, animate: true)
            }
            NSApp.presentationOptions.insert(.autoHideMenuBar)
            w.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        if savedFrame != nil {
            NSApp.presentationOptions.remove(.autoHideMenuBar)
            savedFrame = nil
            savedStyleMask = nil
        }
        removeEscMonitor()
        window?.delegate = nil
        window?.close()
        window = nil
        AppLog.log(.player, "播放窗口已关闭")
    }
}

/// 窗口关闭转发（NSWindowDelegate 弱持有由 window 管理）。
final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
}
