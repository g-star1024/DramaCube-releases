import SwiftUI
import HongguoCore

/// 设置面板（macOS 规范：TabView 分区 + Form）。
///
/// 全部绑定 `AppSettings`（UserDefaults-backed），改动即时生效；
/// 端口等需重启的项有标注。「服务」页可现场探测网关健康。
public struct SettingsView: View {
    @ObservedObject private var s = AppSettings.shared

    @State private var healthState: HealthState = .idle

    public init() {}

    private enum HealthState: Equatable {
        case idle, checking
        case ok(String)
        case failed(String)
    }

    public var body: some View {
        TabView {
            playbackTab
                .tabItem { Label("播放", systemImage: "play.circle") }
            browseTab
                .tabItem { Label("浏览", systemImage: "square.grid.2x2") }
            serviceTab
                .tabItem { Label("服务", systemImage: "antenna.radiowaves.left.and.right") }
            aboutTab
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 360)
    }

    // MARK: - 播放

    private var playbackTab: some View {
        Form {
            Section("播放偏好") {
                Picker("默认倍速", selection: $s.defaultPlaybackRate) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0], id: \.self) { r in
                        Text("\(r, specifier: "%.2f")x").tag(r)
                    }
                }
                Toggle("自动连播下一集", isOn: $s.autoPlayNext)
                Toggle("启用老板键（⌘⇧H 隐藏/显示）", isOn: $s.bossKeyEnabled)
                Stepper(value: $s.introSkipSeconds, in: 0...30, step: 5) {
                    Text(s.introSkipSeconds == 0 ? "不跳过片头" : "自动跳过片头 \(Int(s.introSkipSeconds)) 秒")
                }
            }
        }
        .padding(20)
    }

    // MARK: - 浏览

    private var browseTab: some View {
        Form {
            Section("浏览偏好") {
                Picker("启动时默认分区", selection: $s.homeSection) {
                    Text("发现").tag("discover")
                    Text("排行榜").tag("rank")
                    Text("探索").tag("explore")
                }
                Picker("列表每页数量", selection: $s.pageSize) {
                    ForEach([12, 24, 36, 48], id: \.self) { n in
                        Text("\(n) 部").tag(n)
                    }
                }
            }
        }
        .padding(20)
    }

    // MARK: - 服务

    private var serviceTab: some View {
        Form {
            Section("本地网关") {
                LabeledContent("地址", value: AppConfig.gatewayBaseURL)
                Stepper(value: $s.gatewayPort, in: 1024...65535, step: 1) {
                    Text("端口：\(s.gatewayPort)")
                }
                Text("修改端口后需重启应用生效。")
                    .font(.caption)
                    .foregroundStyle(Brand.secondaryLabel)
            }
            Section("健康检查") {
                HStack {
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
                }
            }
        }
        .padding(20)
    }

    // MARK: - 关于

    private var aboutTab: some View {
        Form {
            Section("红果短剧 for Mac") {
                LabeledContent("版本", value: AppConfig.appVersion)
                LabeledContent("最低系统", value: "macOS " + AppConfig.minMacOS)
                LabeledContent("内容来源", value: "公开网页解析（本地网关收口）")
            }
            Section("更新") {
                Button("前往 GitHub 检查更新") {
                    if let url = URL(string: "https://github.com/g-star1024/hongguo-desktop-releases/releases/latest") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .padding(20)
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
