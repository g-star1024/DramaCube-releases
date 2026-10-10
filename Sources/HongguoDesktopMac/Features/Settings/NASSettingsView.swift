import SwiftUI
import HongguoCore

/// 资源库设置页（NAS）：添加 WebDAV / 本机挂载目录、开关、连通性测试、删除。
///
/// 库配置由网关侧持久化，升级重装不丢；前端另有本地镜像兜底展示。
struct NASSettingsView: View {
    @ObservedObject var nm = NASManager.shared

    @State private var showAdd = false
    @State private var testingId: String?
    @State private var testMsg: [String: String] = [:]

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                addCard
                listCard
            }
            .padding(Spacing.xl)
        }
        .background(Brand.background)
        .task { nm.load() }
        .sheet(isPresented: $showAdd) { AddLibrarySheet(nm: nm) }
    }

    // MARK: 顶部：添加 + 说明
    private var addCard: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NAS 资源库")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.label)
                Text("添加 WebDAV 服务器或本机已挂载的 SMB/AFP 目录（/Volumes/…），客户端会扫描其中的视频文件并聚合为剧集。配置保存在本地，升级重装不丢。")
                    .font(Typography.caption)
                    .foregroundStyle(Brand.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { showAdd = true } label: {
                Label("添加资源库", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(Spacing.lg)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Brand.chipFill))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.separator.opacity(0.5), lineWidth: 0.5))
    }

    // MARK: 库列表
    private var listCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("已添加（\(nm.libraries.count) 个）")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.secondaryLabel)
                .padding(.bottom, Spacing.sm)

            if nm.libraries.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "externaldrive.badge.questionmark")
                            .font(.system(size: 26))
                            .foregroundStyle(Brand.secondaryLabel)
                        Text("还没有资源库，点右上角「添加资源库」")
                            .font(Typography.caption)
                            .foregroundStyle(Brand.secondaryLabel)
                    }
                    .padding(.vertical, Spacing.xl)
                    Spacer()
                }
            } else {
                ForEach(nm.libraries) { lib in
                    libRow(lib)
                    if lib.id != nm.libraries.last?.id { Divider().padding(.leading, 40) }
                }
            }
        }
        .padding(Spacing.lg)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Brand.chipFill))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.separator.opacity(0.5), lineWidth: 0.5))
    }

    private func libRow(_ lib: NASManager.NASLibrary) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: lib.type == .webdav ? "network" : "externaldrive")
                .font(.system(size: 16))
                .foregroundStyle(Brand.accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Brand.accent.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(lib.name).font(Typography.body).foregroundStyle(Brand.label)
                    Text(lib.typeName)
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.secondaryLabel)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Brand.chipFill))
                }
                Text(lib.baseURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Brand.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let msg = testMsg[lib.id] {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(msg.hasPrefix("✓") ? .green : .red)
                }
            }
            Spacer()

            Button(testingId == lib.id ? "测试中…" : "测试") {
                testingId = lib.id
                Task {
                    if let r = await nm.test(id: lib.id) {
                        testMsg[lib.id] = r.ok
                            ? "✓ \(r.latencyMs)ms · \(r.videoCount) 个视频"
                            : "✗ \(r.error ?? "连接失败")"
                    } else {
                        testMsg[lib.id] = "✗ 网关未响应"
                    }
                    testingId = nil
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(testingId == lib.id)

            Toggle("", isOn: Binding(
                get: { lib.enabled },
                set: { on in Task { await nm.setEnabled(id: lib.id, on) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            Button { Task { await nm.remove(id: lib.id) } } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("删除该资源库")
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 添加资源库弹窗
private struct AddLibrarySheet: View {
    @ObservedObject var nm: NASManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: NASManager.NASLibrary.LibType = .webdav
    @State private var base = ""
    @State private var user = ""
    @State private var pass = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("添加资源库")
                .font(.system(size: 16, weight: .semibold))

            Picker("类型", selection: $type) {
                Text("WebDAV 服务器").tag(NASManager.NASLibrary.LibType.webdav)
                Text("本机挂载目录").tag(NASManager.NASLibrary.LibType.mount)
            }
            .pickerStyle(.segmented)

            field("名称", text: $name, placeholder: "如：群晖电影库")
            field(type == .webdav ? "服务器地址" : "挂载路径", text: $base,
                  placeholder: type == .webdav ? "http://192.168.1.10:5005/电影" : "/Volumes/电影")
            if type == .webdav {
                field("账号（可选）", text: $user, placeholder: "WebDAV 用户名")
                SecureField("密码（可选）", text: $pass)
                    .textFieldStyle(.roundedBorder)
            }

            if let error {
                Text(error).font(Typography.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button(isSaving ? "添加中…" : "添加并测试") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || name.isEmpty || base.isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 460)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func save() {
        isSaving = true; error = nil
        Task {
            do {
                let lib = try await nm.add(
                    name: name, type: type, base: base,
                    user: user.isEmpty ? nil : user,
                    pass: pass.isEmpty ? nil : pass)
                // 添加后立即测一次
                if let r = await nm.test(id: lib.id), !r.ok {
                    error = "已添加，但连接测试失败：\(r.error ?? "未知错误")。可在列表中重试。"
                    isSaving = false
                    return
                }
                dismiss()
            } catch {
                self.error = "添加失败：\(error.localizedDescription)"
            }
            isSaving = false
        }
    }
}
