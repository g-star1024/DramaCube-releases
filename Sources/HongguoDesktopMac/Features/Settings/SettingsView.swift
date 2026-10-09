import SwiftUI
import HongguoCore

/// 设置面板（符合 macOS 设置窗口规范）。
public struct SettingsView: View {
    @AppStorage("enableHardwareAccel") private var hw = true
    @AppStorage("defaultSpeed") private var speed = 1.0

    public init() {}

    public var body: some View {
        TabView {
            Form {
                Section("播放") {
                    Toggle("硬件加速解码", isOn: $hw)
                    Stepper(value: $speed, in: 0.5...3.0, step: 0.5) {
                        Text("默认倍速：\(speed, specifier: "%.1f")x")
                    }
                }
                Section("关于") {
                    LabeledContent("版本", value: AppConfig.appVersion)
                    LabeledContent("最低系统", value: "macOS " + AppConfig.minMacOS)
                    LabeledContent("本地网关", value: AppConfig.gatewayBaseURL)
                }
            }
            .tabItem { Label("通用", systemImage: "gear") }
            .padding()
        }
        .frame(width: 460, height: 320)
    }
}
