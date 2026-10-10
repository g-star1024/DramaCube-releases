import SwiftUI
import HongguoCore

/// 设置面板（macOS 规范：TabView 分区 + 自定义对齐行布局）。
///
/// 全部绑定 `AppSettings`（UserDefaults-backed），改动即时生效；
/// 端口等需重启的项有标注。「服务」页可现场探测网关健康、清理本地缓存。
public struct SettingsView: View {
    @ObservedObject private var s = AppSettings.shared

    @State private var healthState: HealthState = .idle
    @State private var cacheCleared = false

    public init() {}

    private enum HealthState: Equatable {
        case idle, checking
        case ok(String)
        case failed(String)
    }

    public var body: some View {
        TabView {
            generalTab.tabItem { Label("通用", systemImage: "gearshape") }
            playbackTab.tabItem { Label("播放", systemImage: "play.circle") }
            browseTab.tabItem { Label("浏览", systemImage: "square.grid.2x2") }
            sourcesTab.tabItem { Label("视频源", systemImage: "antenna.radiowaves.left.and.right") }
            liveTab.tabItem { Label("电视直播", systemImage: "tv") }
            nasTab.tabItem { Label("资源库", systemImage: "externaldrive.connected.to.line.below") }
            serviceTab.tabItem { Label("服务", systemImage: "stethoscope") }
            aboutTab.tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 640, height: 520)
    }

    // MARK: - 通用（菜单栏 / Dock / 窗口行为）

    @State private var hideDockIcon = UserDefaults.standard.bool(forKey: "ui.hideDockIcon")
    @State private var closeToTray = UserDefaults.standard.object(forKey: "ui.closeToTray") == nil
        ? true : UserDefaults.standard.bool(forKey: "ui.closeToTray")

    private var generalTab: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                sectionCard("菜单栏托盘") {
                    row("关闭主窗口时") {
                        Text(closeToTray ? "最小化到菜单栏" : "直接退出应用")
                            .font(.system(size: 12))
                            .foregroundStyle(Brand.secondaryLabel)
                        Toggle("", isOn: $closeToTray)
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    rowDivider
                    row("隐藏 Dock 图标") {
                        Text(hideDockIcon ? "仅显示菜单栏图标" : "Dock 与菜单栏同时显示")
                            .font(.system(size: 12))
                            .foregroundStyle(Brand.secondaryLabel)
                        Toggle("", isOn: $hideDockIcon)
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                }
                sectionCard("播放窗口") {
                    row("竖版视频") {
                        Text("自动收窄窗口消除黑边")
                            .font(.system(size: 12))
                            .foregroundStyle(Brand.secondaryLabel)
                    }
                }
            }
            .padding(Spacing.xl)
        }
        .background(Brand.background)
        .onChange(of: hideDockIcon) { _, v in
            UserDefaults.standard.set(v, forKey: "ui.hideDockIcon")
            MenuBarController.shared.start()
        }
        .onChange(of: closeToTray) { _, v in
            UserDefaults.standard.set(v, forKey: "ui.closeToTray")
            MenuBarController.shared.start()
        }
    }

    // MARK: - 视频源

    private var sourcesTab: some View {
        SourceSettingsView()
    }

    // MARK: - 电视直播

    private var liveTab: some View {
        LiveSettingsView()
    }

    // MARK: - 资源库（NAS）

    private var nasTab: some View {
        NASSettingsView()
    }

    // MARK: 分组列表原语（参考移动端设置：分组标题悬浮 + 圆角卡片内多行）
    //
    // 设计语言：卡片行高紧凑、行间细分割线、label 左对齐控件右贴齐，
    // 视觉密度对齐参考截图（系统/网络/服务器/播放器/缓存/反馈/关于 分组列表）。

    /// 单行：label 左，控件右。
    private func row<V: View>(_ label: String, @ViewBuilder control: () -> V) -> some View {
        HStack(spacing: Spacing.md) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Brand.label)
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// 目录选择行控件：显示当前目录（或默认），点「选择」弹 NSOpenPanel 选目录，「还原」清空回默认。
    private func dirPicker(current: String, defaultLabel: String, onPick: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(current.isEmpty ? defaultLabel : abbreviatePath(current))
                .font(.system(size: 11))
                .foregroundStyle(current.isEmpty ? Brand.secondaryLabel : Brand.label)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 200, alignment: .trailing)
                .help(current.isEmpty ? defaultLabel : current)
            Button("选择") {
                if let path = pickDirectory() { onPick(path) }
            }
            .controlSize(.small)
            if !current.isEmpty {
                Button("还原") { onPick("") }
                    .controlSize(.small)
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
    }

    private func abbreviatePath(_ p: String) -> String {
        p.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// 弹 NSOpenPanel 选一个目录，返回路径。
    private func pickDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    /// 可导航行（右侧 chevron，点击动作）。
    private func navRow(_ label: String, value: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Text(label).font(.system(size: 13)).foregroundStyle(Brand.label)
                Spacer()
                if let value {
                    Text(value).font(.system(size: 12)).foregroundStyle(Brand.secondaryLabel)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.secondaryLabel.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 分组卡片：标题悬浮在上，内容行间自动加分割线。
    private func sectionCard<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.secondaryLabel)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                rows()
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Brand.chipFill.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.separator.opacity(0.4), lineWidth: 0.5)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 行间分割线（配合 sectionCard 使用）。
    private var rowDivider: some View {
        Divider().padding(.leading, 14)
    }

    // MARK: - 播放

    private var playbackTab: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                sectionCard("播放偏好") {
                    row("默认倍速") {
                        Picker("", selection: $s.defaultPlaybackRate) {
                            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0], id: \.self) { r in
                                Text("\(r, specifier: "%.2f")x").tag(r)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        .controlSize(.small)
                    }
                    rowDivider
                    row("自动连播") {
                        Toggle("", isOn: $s.autoPlayNext).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    rowDivider
                    row("老板键") {
                        Text("⌘⇧H")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Brand.secondaryLabel)
                        Toggle("", isOn: $s.bossKeyEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    rowDivider
                    row("跳过片头") {
                        Stepper(value: $s.introSkipSeconds, in: 0...30, step: 5) {
                            Text(s.introSkipSeconds == 0 ? "不跳过" : "\(Int(s.introSkipSeconds)) 秒")
                                .font(.system(size: 12))
                        }
                        .frame(width: 170, alignment: .trailing)
                        .controlSize(.small)
                    }
                    rowDivider
                    row("默认播放器") {
                        Picker("", selection: $s.defaultExternalPlayer) {
                            Text("内置播放器").tag("builtin")
                            ForEach(ExternalPlayerApp.allCases.filter { $0 != .systemDefault && ExternalPlayerOpener.isInstalled($0) }) { app in
                                Text(app.displayName).tag(app.rawValue)
                            }
                            Text("系统默认播放器").tag(ExternalPlayerApp.systemDefault.rawValue)
                        }
                        .labelsHidden()
                        .frame(width: 160)
                        .controlSize(.small)
                    }
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.secondaryLabel)
                        Text("设为外部播放器后，选集播放时自动用该播放器打开，无需每次在播放界面手动切换。内置播放器 = 在应用内播放。")
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                }

                sectionCard("缓冲") {
                    row("缓冲策略") {
                        Picker("", selection: $s.bufferStrategy) {
                            Text("低缓冲").tag("low")
                            Text("中缓冲").tag("medium")
                            Text("高缓冲").tag("high")
                            Text("超高缓冲").tag("ultra")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                        .controlSize(.small)
                    }
                    rowDivider
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.secondaryLabel)
                        Text("缓冲块越大播放越流畅但越耗流量/内存。当前：\(Int(s.forwardBufferSeconds)) 秒。下集预缓冲在播放进度 90% 时自动预热下一集。")
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    rowDivider
                    row("下集预缓冲") {
                        Toggle("", isOn: $s.prefetchNextEpisode).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                }

                sectionCard("下载") {
                    row("最大同时下载") {
                        Stepper(value: Binding(
                            get: { DownloadManager.shared.maxConcurrent },
                            set: { DownloadManager.shared.maxConcurrent = $0 }
                        ), in: 1...6) {
                            Text("\(DownloadManager.shared.maxConcurrent) 个")
                                .font(.system(size: 12))
                        }
                        .frame(width: 150, alignment: .trailing)
                        .controlSize(.small)
                    }
                    rowDivider
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.secondaryLabel)
                        Text("m3u8 自动调用 ffmpeg 转 mp4（检测到 \(DownloadManager.ffmpegPath != nil ? "已安装" : "未安装 ffmpeg，直链可直接下载")）。下载文件保存在「下载/剧立方」目录。")
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                }
            }
            .padding(Spacing.xl)
        }
        .background(Brand.background)
    }

    // MARK: - 浏览

    private var browseTab: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                sectionCard("浏览偏好") {
                    row("启动默认分区") {
                        Picker("", selection: $s.homeSection) {
                            Text("发现").tag("discover")
                            Text("排行榜").tag("rank")
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        .controlSize(.small)
                    }
                    rowDivider
                    row("每页数量") {
                        Picker("", selection: $s.pageSize) {
                            ForEach([12, 24, 36, 48], id: \.self) { n in
                                Text("\(n) 部").tag(n)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        .controlSize(.small)
                    }
                }
                sectionCard("本地缓存") {
                    row("下载目录") {
                        dirPicker(current: s.customDownloadDir, defaultLabel: "默认（下载/剧立方）") { path in
                            s.customDownloadDir = path
                        }
                    }
                    rowDivider
                    row("缓存目录") {
                        dirPicker(current: s.customCacheDir, defaultLabel: "默认（Application Support）") { path in
                            s.customCacheDir = path
                        }
                    }
                    rowDivider
                    row("清除缓存") {
                        Button(cacheCleared ? "已清除" : "清除列表 / 图片缓存") {
                            Task {
                                await DiskCache.shared.clearAll()
                                URLCache.shared.removeAllCachedResponses()
                                cacheCleared = true
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                                    cacheCleared = false
                                }
                            }
                        }
                        .disabled(cacheCleared)
                        .controlSize(.small)
                    }
                    rowDivider
                    row("说明") {
                        Text("自定义目录仅影响新下载/新缓存，已有文件不迁移。清除缓存不影响收藏与播放记录。")
                            .font(.system(size: 12))
                            .foregroundStyle(Brand.secondaryLabel)
                    }
                }
            }
            .padding(Spacing.xl)
        }
        .background(Brand.background)
    }

    // MARK: - 服务

    private var serviceTab: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                sectionCard("本地网关") {
                    row("地址") {
                        Text(AppConfig.gatewayBaseURL)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Brand.secondaryLabel)
                            .textSelection(.enabled)
                    }
                    rowDivider
                    row("端口") {
                        TextField("", value: $s.gatewayPort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .controlSize(.small)
                        Text("重启生效")
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.secondaryLabel)
                    }
                }
                sectionCard("健康检查") {
                    row("网关状态") {
                        switch healthState {
                        case .idle:
                            Text("未检测").font(.system(size: 12)).foregroundStyle(Brand.secondaryLabel)
                        case .checking:
                            ProgressView().controlSize(.small)
                        case .ok(let detail):
                            Label(detail, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12)).foregroundStyle(.green)
                        case .failed(let detail):
                            Label(detail, systemImage: "xmark.octagon.fill")
                                .font(.system(size: 12)).foregroundStyle(.red)
                        }
                        Button(healthState == .checking ? "探测中…" : "立即检查") { checkHealth() }
                            .disabled(healthState == .checking)
                            .controlSize(.small)
                    }
                }
            }
            .padding(Spacing.xl)
        }
        .background(Brand.background)
    }

    // MARK: - 关于

    private var aboutTab: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                VStack(spacing: Spacing.sm) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    Text("剧立方 DramaCube for Mac")
                        .font(Typography.headline)
                    Text("版本 \(AppConfig.appVersion)")
                        .font(Typography.caption)
                        .foregroundStyle(Brand.secondaryLabel)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.md)

                sectionCard("信息") {
                    row("版本") {
                        Text(AppConfig.appVersion)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Brand.secondaryLabel)
                    }
                    rowDivider
                    row("最低系统") {
                        Text("macOS " + AppConfig.minMacOS)
                            .font(.system(size: 12))
                            .foregroundStyle(Brand.secondaryLabel)
                    }
                    rowDivider
                    row("内容来源") {
                        Text("公开网页解析（本地网关收口）")
                            .font(.system(size: 12))
                            .foregroundStyle(Brand.secondaryLabel)
                    }
                }
                sectionCard("更新") {
                    navRow("检查更新", value: "GitHub Releases") {
                        if let url = URL(string: "https://github.com/g-star1024/hongguo-mac/releases/latest") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                sectionCard("运行日志") {
                    row("日志文件") {
                        Text(AppLog.currentLogFile.lastPathComponent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Brand.secondaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    rowDivider
                    navRow("在 Finder 中显示日志") {
                        NSWorkspace.shared.open(AppLog.logDirectory)
                    }
                }
            }
            .padding(Spacing.xl)
        }
        .background(Brand.background)
    }

    // MARK: - 健康检查

    private func checkHealth() {
        healthState = .checking
        // 优先看进程内网关是否在跑（最可靠，不受瞬时网络/超时影响）
        let url = URL(string: "\(AppConfig.gatewayBaseURL)/api/health")!
        // 带 5s 超时 + 失败重试一次，避免偶发超时误报「未响应」
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        attemptHealth(req, retries: 1)
    }

    private nonisolated func attemptHealth(_ req: URLRequest, retries: Int) {
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let ok = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["ok"] != nil
            if ok {
                Task { @MainActor in self.healthState = .ok("网关正常") }
            } else if retries > 0 {
                // 网关可能刚启动尚未监听，0.6s 后重试
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
                    self.attemptHealth(req, retries: retries - 1)
                }
            } else {
                // 网络失败但进程内网关在跑 → 视为正常（避免误报）
                Task { @MainActor in
                    let running = GatewayController.shared.isRunning
                    self.healthState = running ? .ok("网关运行中（进程内）")
                                               : .failed("网关未响应（可能未启动）")
                }
            }
        }.resume()
    }
}
