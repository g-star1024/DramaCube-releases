import SwiftUI

/// 视频源管理页：订阅导入/更新、连通性测试、单源开关。
struct SourceSettingsView: View {
    @ObservedObject var sm = SourceManager.shared
    @State private var urlInput = ""
    @State private var message: String?
    @State private var msgIsError = false
    @State private var showOnlyFailed = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                importCard
                if sm.hasSubscription {
                    testCard
                    siteListCard
                } else {
                    emptyHint
                }
            }
            .padding(Spacing.xl)
        }
        .background(Brand.background)
        .onAppear {
            if urlInput.isEmpty { urlInput = sm.subscriptionURL }
        }
    }

    // MARK: 订阅导入
    private var importCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("TVBox 订阅").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.secondaryLabel)
            HStack(spacing: Spacing.sm) {
                TextField("粘贴订阅地址（JSON/TVBox 格式）", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                Button(sm.isImporting ? "导入中…" : (sm.hasSubscription ? "更新订阅" : "一键导入")) {
                    Task { await doImport() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.accent)
                .disabled(sm.isImporting || urlInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let message {
                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(msgIsError ? .red : .green)
            }
            Text("支持 TVBox / MoonTV 标准订阅（maccms JSON 接口）。导入后站点内容在侧边栏「视频源」浏览，搜索自动聚合所有启用的源。")
                .font(Typography.caption)
                .foregroundStyle(Brand.secondaryLabel)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Brand.chipFill))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.separator.opacity(0.5), lineWidth: 0.5))
    }

    // MARK: 连通性测试
    private var testCard: some View {
        HStack(spacing: Spacing.md) {
            Button(sm.isTesting ? "测试中…（\(sm.sites.count) 源）" : "全部连通性测试") {
                Task { await sm.testAll() }
            }
            .disabled(sm.isTesting)
            if sm.isTesting { ProgressView().controlSize(.small) }
            Spacer()
            let okCount = sm.testResults.values.filter(\.ok).count
            if !sm.testResults.isEmpty {
                Text("上次测试：\(okCount)/\(sm.testResults.count) 可用")
                    .font(Typography.caption)
                    .foregroundStyle(Brand.secondaryLabel)
                Toggle("只看失败", isOn: $showOnlyFailed)
                    .toggleStyle(.checkbox)
                    .font(Typography.caption)
            }
        }
        .padding(Spacing.lg)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Brand.chipFill))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.separator.opacity(0.5), lineWidth: 0.5))
    }

    // MARK: 站点列表
    private var siteListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("站点（\(sm.sites.count) 个，启用 \(sm.enabledSites.count)）")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.secondaryLabel)
                .padding(.bottom, Spacing.sm)

            let shown = sm.sites.filter { s in
                !showOnlyFailed || (sm.testResults[s.key].map { !$0.ok } ?? false)
            }
            ForEach(shown) { s in
                siteRow(s)
                if s.id != shown.last?.id { Divider().padding(.leading, 4) }
            }
        }
        .padding(Spacing.lg)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Brand.chipFill))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.separator.opacity(0.5), lineWidth: 0.5))
    }

    private func siteRow(_ s: SourceManager.TVBoxSite) -> some View {
        HStack(spacing: Spacing.sm) {
            // 状态点
            Circle()
                .fill(statusColor(s.key))
                .frame(width: 8, height: 8)
            Text(s.name)
                .font(Typography.body)
                .lineLimit(1)
            if let r = sm.testResults[s.key] {
                Text(r.ok ? "\(r.latencyMs)ms" : "失败")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(r.ok ? Brand.secondaryLabel : .red)
            }
            Spacer()
            Button("测试") { Task { await sm.testOne(s.key) } }
                .controlSize(.small)
                .buttonStyle(.borderless)
            Toggle("", isOn: Binding(
                get: { !sm.disabled.contains(s.key) },
                set: { sm.setEnabled(s.key, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }

    private func statusColor(_ key: String) -> Color {
        guard let r = sm.testResults[key] else { return Brand.secondaryLabel.opacity(0.4) }
        return r.ok ? .green : .red
    }

    private var emptyHint: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 34))
                .foregroundStyle(Brand.secondaryLabel)
            Text("尚未导入视频源订阅")
                .font(Typography.body)
            Text("粘贴 TVBox 订阅地址，一键导入后即可浏览/搜索上百个站点")
                .font(Typography.caption)
                .foregroundStyle(Brand.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
    }

    // MARK: 动作
    private func doImport() async {
        let url = urlInput.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        message = nil
        do {
            let count = try await sm.importSubscription(url: url)
            message = "导入成功：\(count) 个站点，已可在「视频源」页浏览"
            msgIsError = false
        } catch {
            message = "导入失败：\(error.localizedDescription)"
            msgIsError = true
        }
    }
}
