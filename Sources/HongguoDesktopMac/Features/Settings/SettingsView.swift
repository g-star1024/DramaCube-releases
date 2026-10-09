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
            playbackTab.tabItem { Label("播放", systemImage: "play.circle") }
            browseTab.tabItem { Label("浏览", systemImage: "square.grid.2x2") }
            serviceTab.tabItem { Label("服务", systemImage: "antenna.radiowaves.left.and.right") }
            aboutTab.tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 420)
    }

    // MARK: 行布局原语（标签固定宽度左对齐，控件右贴齐）

    private func row<V: View>(_ label: String, @ViewBuilder control: () -> V) -> some View {
        HStack(spacing: Spacing.md) {
            Text(label)
                .font(Typography.body)
                .foregroundStyle(Brand.label)
                .frame(width: 120, alignment: .leading)
            control()
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }

    private func sectionCard(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.secondaryLabel)
                .padding(.bottom, 6)
            rows()
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Brand.chipFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.separator.opacity(0.5), lineWidth: 0.5)
        )
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
                        .frame(width: 140)
                    }
                    row("自动连播") {
                        Toggle("", isOn: $s.autoPlayNext).labelsHidden().toggleStyle(.switch)
                    }
                    row("老板键") {
                        Toggle("", isOn: $s.bossKeyEnabled).labelsHidden().toggleStyle(.switch)
                        Text("⌘⇧H 隐藏 / 显示主窗口")
                            .font(Typography.caption)
                            .foregroundStyle(Brand.secondaryLabel)
                    }
                    row("跳过片头") {
                        Stepper(value: $s.introSkipSeconds, in: 0...30, step: 5) {
                            Text(s.introSkipSeconds == 0 ? "不跳过" : "自动跳过 \(Int(s.introSkipSeconds)) 秒")
                                .font(Typography.body)
                        }
                        .frame(width: 180, alignment: .leading)
                    }
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
                            Text("探索").tag("explore")
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    row("每页数量") {
                        Picker("", selection: $s.pageSize) {
                            ForEach([12, 24, 36, 48], id: \.self) { n in
                                Text("\(n) 部").tag(n)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                }
                sectionCard("本地缓存") {
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
                    }
                    Text("清除后重新联网加载，不影响收藏与播放记录。")
                        .font(Typography.caption)
                        .foregroundStyle(Brand.secondaryLabel)
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
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    row("端口") {
                        TextField("", value: $s.gatewayPort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                        Text("修改后需重启应用生效")
                            .font(Typography.caption)
                            .foregroundStyle(Brand.secondaryLabel)
                    }
                }
                sectionCard("健康检查") {
                    HStack(spacing: Spacing.md) {
                        Button(healthState == .checking ? "探测中…" : "立即检查") {
                            checkHealth()
                        }
                        .disabled(healthState == .checking)

                        switch healthState {
                        case .idle:
                            Text("未检测").font(.caption).foregroundStyle(Brand.secondaryLabel)
                        case .checking:
                            ProgressView().controlSize(.small)
                        case .ok(let detail):
                            Label(detail, systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(.green)
                        case .failed(let detail):
                            Label(detail, systemImage: "xmark.octagon.fill")
                                .font(.caption).foregroundStyle(.red)
                        }
                        Spacer()
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
                    row("最低系统") {
                        Text("macOS " + AppConfig.minMacOS).font(Typography.body)
                    }
                    row("内容来源") {
                        Text("公开网页解析（本地网关收口）").font(Typography.body)
                    }
                }
                sectionCard("更新") {
                    row("检查更新") {
                        Button("前往 GitHub Releases") {
                            if let url = URL(string: "https://github.com/g-star1024/hongguo-mac/releases/latest") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
                sectionCard("运行日志") {
                    row("日志文件") {
                        Text(AppLog.currentLogFile.lastPathComponent)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Brand.secondaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    row("打开目录") {
                        Button("在 Finder 中显示日志") {
                            NSWorkspace.shared.open(AppLog.logDirectory)
                        }
                    }
                    Text("遇到卡死/异常时，把最新一份日志发给开发者即可定位问题（含主线程卡顿记录与内存曲线）。")
                        .font(Typography.caption)
                        .foregroundStyle(Brand.secondaryLabel)
                }
            }
            .padding(Spacing.xl)
        }
        .background(Brand.background)
    }

    // MARK: - 健康检查

    private func checkHealth() {
        healthState = .checking
        let url = URL(string: "\(AppConfig.gatewayBaseURL)/api/health")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let result: HealthState
            if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               obj["ok"] != nil {
                result = .ok("网关正常")
            } else {
                result = .failed("网关未响应（可能未启动）")
            }
            Task { @MainActor in healthState = result }
        }.resume()
    }
}
