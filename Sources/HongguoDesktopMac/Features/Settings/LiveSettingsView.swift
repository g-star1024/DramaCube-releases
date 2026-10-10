import SwiftUI

/// 电视直播源管理页：添加/删除/开关 m3u 直播源（多源导入自动排重合并）。
struct LiveSettingsView: View {
    @ObservedObject private var lm = LiveManager.shared
    @State private var urlInput = ""
    @State private var nameInput = ""
    @State private var message: String?
    @State private var msgIsError = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                importCard
                if !lm.sources.isEmpty {
                    listCard
                } else {
                    emptyHint
                }
            }
            .padding(Spacing.xl)
        }
        .background(Brand.background)
        .onAppear { lm.load() }
    }

    // MARK: 添加源
    private var importCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("直播源（m3u 订阅）").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.secondaryLabel)
            HStack(spacing: Spacing.sm) {
                TextField("名称（可选，默认取域名）", text: $nameInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
                TextField("粘贴 m3u 直播源地址", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                Button(lm.isImporting ? "添加中…" : "添加源") {
                    Task { await doAdd() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.accent)
                .disabled(lm.isImporting || urlInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let message {
                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(msgIsError ? .red : .green)
            }
            Text("支持标准 m3u/m3u8 直播源（含 #EXTINF 元数据）。可添加多个源，频道按「名称+分组」自动排重合并。播放自带约定 UA（okHttp/Mod-1.5.0.0）。")
                .font(Typography.caption)
                .foregroundStyle(Brand.secondaryLabel)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Brand.chipFill))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.separator.opacity(0.5), lineWidth: 0.5))
    }

    // MARK: 源列表
    private var listCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("已添加 \(lm.sources.count) 个直播源（启用 \(lm.sources.filter(\.enabled).count)）")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.secondaryLabel)
                .padding(.bottom, Spacing.sm)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lm.sources) { s in
                    row(s)
                    if s.id != lm.sources.last?.id { Divider().padding(.leading, 4) }
                }
            }
        }
        .padding(Spacing.lg)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Brand.chipFill))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.separator.opacity(0.5), lineWidth: 0.5))
    }

    private func row(_ s: LiveManager.LiveSource) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "tv")
                .foregroundStyle(s.enabled ? Brand.accent : Brand.secondaryLabel)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).font(Typography.body).lineLimit(1)
                Text(s.url).font(.system(size: 10)).foregroundStyle(Brand.secondaryLabel).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("删除") { Task { await lm.remove(id: s.id) } }
                .controlSize(.small)
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            Toggle("", isOn: Binding(
                get: { s.enabled },
                set: { on in Task { await lm.setEnabled(id: s.id, on) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }

    private var emptyHint: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "tv")
                .font(.system(size: 34))
                .foregroundStyle(Brand.secondaryLabel)
            Text("尚未添加直播源").font(Typography.body)
            Text("粘贴 m3u 直播源地址，频道会按分组展示在侧边栏「电视直播」")
                .font(Typography.caption)
                .foregroundStyle(Brand.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
    }

    // MARK: 动作
    private func doAdd() async {
        let url = urlInput.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        message = nil
        do {
            let isNew = try await lm.add(url: url, name: nameInput.trimmingCharacters(in: .whitespaces))
            message = isNew ? "添加成功，频道已合并到「电视直播」" : "该源已存在，已更新"
            msgIsError = false
            if isNew { urlInput = ""; nameInput = "" }
        } catch {
            message = "添加失败：\(error.localizedDescription)"
            msgIsError = true
        }
    }
}
