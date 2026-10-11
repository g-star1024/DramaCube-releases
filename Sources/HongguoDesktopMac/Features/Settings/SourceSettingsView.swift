import SwiftUI

/// 视频源管理页：订阅源管理（增删/更新/逐地址成败）、连通性测试、单源开关。
struct SourceSettingsView: View {
    @ObservedObject var sm = SourceManager.shared
    @State private var urlInput = ""
    @State private var importResults: [SourceManager.SubImportResult] = []
    @State private var showOnlyFailed = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                subscriptionCard
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
            Task { await sm.refreshSubscriptionURLs() }
        }
    }

    // MARK: 订阅源管理
    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("订阅源管理").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.secondaryLabel)
                Spacer()
                if !sm.subscriptionURLs.isEmpty {
                    Button(sm.isImporting ? "更新中…" : "全部更新") {
                        Task { await refreshAll() }
                    }
                    .controlSize(.small)
                    .disabled(sm.isImporting)
                }
            }

            // 已保存的订阅地址列表（重启后保留）
            if !sm.subscriptionURLs.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sm.subscriptionURLs, id: \.self) { url in
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "link").font(.system(size: 11)).foregroundStyle(Brand.secondaryLabel)
                            Text(url)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Brand.label)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(url)
                            Spacer()
                            Button { Task { await sm.removeSubscriptionURL(url) } } label: {
                                Image(systemName: "trash").font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red.opacity(0.8))
                            .help("删除此订阅地址")
                        }
                        .padding(.vertical, 5)
                        if url != sm.subscriptionURLs.last { Divider() }
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Brand.background))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.separator.opacity(0.6), lineWidth: 0.5))
            }

            // 新增订阅输入框
            TextEditor(text: $urlInput)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 50, maxHeight: 80)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Brand.background))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.separator.opacity(0.6), lineWidth: 0.5))
            HStack(spacing: Spacing.sm) {
                Spacer()
                Button(sm.isImporting ? "导入中…" : "添加订阅") {
                    Task { await doImport() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.accent)
                .disabled(sm.isImporting || urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // 每地址导入明细（成功的绿色、失败的红色，单个失败不影响其余）
            if !importResults.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(importResults.enumerated()), id: \.offset) { _, r in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(r.ok ? .green : .red)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(shortURL(r.url))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Brand.label)
                                    .lineLimit(1)
                                Text(r.ok ? "新增 \(r.added) 个站点" : (r.error ?? "失败"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(r.ok ? Brand.secondaryLabel : .red)
                            }
                        }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Brand.background))
            }

            Text("支持 TVBox / MoonTV 标准订阅（maccms JSON 接口）。可一次粘贴多个地址（换行/逗号/分号分隔），单个失败自动跳过不影响其余，按接口排重合并。已添加的地址保存在上方列表，重启不丢失，可点「全部更新」重新拉取。")
                .font(Typography.caption)
                .foregroundStyle(Brand.secondaryLabel)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Brand.chipFill))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.separator.opacity(0.5), lineWidth: 0.5))
    }

    private func shortURL(_ url: String) -> String {
        url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
    }

    // MARK: 连通性测试
    private var testCard: some View {
        VStack(spacing: Spacing.sm) {
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
            HStack(spacing: Spacing.sm) {
                Text("自动测速").font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
                Picker("", selection: Binding(
                    get: { sm.autoTestIntervalHours },
                    set: { sm.autoTestIntervalHours = $0 }
                )) {
                    Text("关闭").tag(0.0)
                    Text("每 6 小时").tag(6.0)
                    Text("每 12 小时").tag(12.0)
                    Text("每 24 小时").tag(24.0)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                Spacer()
                if let last = sm.lastAutoTest, sm.autoTestIntervalHours > 0 {
                    Text("上次自动：\(last.formatted(date: .omitted, time: .shortened))")
                        .font(Typography.caption)
                        .foregroundStyle(Brand.secondaryLabel)
                }
            }
            Text("测速完成后失败源一律自动禁用（含手动开启的失效源）；恢复可用的源会自动重新启用，除非您手动关过。")
                .font(Typography.caption)
                .foregroundStyle(Brand.secondaryLabel)
        }
        .padding(Spacing.lg)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Brand.chipFill))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.separator.opacity(0.5), lineWidth: 0.5))
    }

    // MARK: 站点列表（LazyVStack 懒渲染，避免切到本 Tab 时一次性排版 100+ 行卡顿）
    private var siteListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("站点（\(sm.sites.count) 个，启用 \(sm.enabledSites.count)，按延迟排序）")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.secondaryLabel)
                .padding(.bottom, Spacing.sm)

            let shown = sm.sortedSites.filter { s in
                !showOnlyFailed || (sm.testResults[s.key].map { !$0.ok } ?? false)
            }
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                ForEach(shown) { s in
                    siteRow(s)
                    if s.id != shown.last?.id { Divider().padding(.leading, 4) }
                }
            }
        }
        .padding(Spacing.lg)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Brand.chipFill))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.separator.opacity(0.5), lineWidth: 0.5))
    }

    private func siteRow(_ s: SourceManager.TVBoxSite) -> some View {
        let off = sm.disabled.contains(s.key)
        return HStack(spacing: Spacing.sm) {
            Circle()
                .fill(statusColor(s.key))
                .frame(width: 8, height: 8)
            Text(s.name)
                .font(Typography.body)
                .lineLimit(1)
                .foregroundStyle(off ? Brand.secondaryLabel : Brand.label)
            if off {
                Text("已禁用")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Brand.secondaryLabel.opacity(0.6)))
            }
            if let r = sm.testResults[s.key] {
                Text(r.ok ? "\(r.latencyMs)ms" : "失败")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(r.ok ? Brand.secondaryLabel : .red)
                    .help(r.ok ? "延迟 \(r.latencyMs)ms" : (r.error ?? "测试失败"))
            }
            Spacer()
            Button("测试") { Task { await sm.testOne(s.key) } }
                .controlSize(.small)
                .buttonStyle(.borderless)
            Toggle("", isOn: Binding(
                get: { !off },
                set: { sm.setEnabled(s.key, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
        .opacity(off ? 0.55 : 1)
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
        let url = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        importResults = await sm.importSubscription(url: url)
        // 成功的地址已保存，清空输入框便于继续添加
        if importResults.contains(where: \.ok) { urlInput = "" }
    }

    private func refreshAll() async {
        importResults = await sm.refreshAllSubscriptions()
    }
}
