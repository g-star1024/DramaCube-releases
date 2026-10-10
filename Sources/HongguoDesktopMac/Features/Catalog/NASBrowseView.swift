import SwiftUI
import HongguoCore

/// NAS 资源库浏览页：库切换 + 路径导航 + 视频列表。
///
/// 直出当前路径下全部视频文件（递归），点击卡片直接播放（不再聚合目录成剧、不进详情选集）。
/// Drama.id = nas|<libId>|file|<相对路径>，playURL 由 PlayerViewModel 按 nas| 前缀直连。
struct NASBrowseView: View {
    @ObservedObject var nm: NASManager
    let onSelect: (Drama) -> Void

    @State private var currentLibId: String?
    @State private var currentPath: String = ""
    @State private var items: [Drama] = []
    @State private var isLoading = false
    @State private var error: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 6)

    var body: some View {
        VStack(spacing: 0) {
            if currentLibId != nil { pathBar }
            Divider()
            content
        }
        .background(Brand.background)
        .task {
            nm.load()
            // 默认选第一个启用的库
            if currentLibId == nil {
                currentLibId = nm.libraries.first(where: { $0.enabled })?.id ?? nm.libraries.first?.id
            }
            await load()
        }
        .onChange(of: currentLibId) { _, _ in currentPath = ""; Task { await load() } }
        .onChange(of: nm.libraries) { _, libs in
            if currentLibId == nil || !libs.contains(where: { $0.id == currentLibId }) {
                currentLibId = libs.first(where: { $0.enabled })?.id ?? libs.first?.id
                Task { await load() }
            }
        }
        .popover(isPresented: $showLibPicker, arrowEdge: .top) { libPicker }
    }

    @State private var showLibPicker = false

    // MARK: 库切换按钮（只留一个 ⟳ 按钮附库名，点击弹库列表；不再平铺全部库 chip）
    private var libSwitchButton: some View {
        let cur = nm.libraries.first(where: { $0.id == currentLibId })
        return Button { showLibPicker = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                Text(cur?.name ?? "选择资源库")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Brand.label)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Brand.chipFill))
            .overlay(Capsule().strokeBorder(Brand.separator.opacity(0.6), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("当前资源库：\(cur?.name ?? "未选择")，点击切换")
    }

    /// 资源库切换弹层。
    private var libPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("选择资源库")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(nm.libraries) { lib in
                        Button {
                            if lib.enabled { currentLibId = lib.id; showLibPicker = false }
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: currentLibId == lib.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(currentLibId == lib.id ? Brand.accent : Brand.secondaryLabel)
                                Image(systemName: lib.type == .webdav ? "network" : "externaldrive")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Brand.secondaryLabel)
                                Text(lib.name).font(Typography.body).lineLimit(1)
                                Spacer()
                                Text(lib.typeName)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Brand.secondaryLabel)
                                if !lib.enabled {
                                    Text("已禁用").font(.system(size: 11)).foregroundStyle(Brand.secondaryLabel)
                                }
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!lib.enabled)
                        .opacity(lib.enabled ? 1 : 0.5)
                    }
                }
            }
        }
        .frame(width: 300, height: 260)
    }

    // MARK: 路径导航条（右侧放库切换按钮）
    private var pathBar: some View {
        HStack(spacing: Spacing.xs) {
            Button { navigateUp() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(currentPath.isEmpty ? Brand.secondaryLabel.opacity(0.4) : Brand.label)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Brand.chipFill))
            }
            .buttonStyle(.plain)
            .disabled(currentPath.isEmpty)

            Text(currentPath.isEmpty ? "根目录" : currentPath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Brand.secondaryLabel)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            libSwitchButton
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: 内容
    @ViewBuilder
    private var content: some View {
        if nm.libraries.isEmpty {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "externaldrive.badge.plus")
                    .font(.system(size: 34))
                    .foregroundStyle(Brand.secondaryLabel)
                Text("尚未添加 NAS 资源库").font(Typography.body)
                Text("请到「设置 → 资源库」添加 WebDAV 或本机挂载目录")
                    .font(Typography.caption)
                    .foregroundStyle(Brand.secondaryLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            ErrorView(error, retry: { Task { await load() } })
        } else if items.isEmpty && isLoading {
            LoadingView("正在扫描媒体库…")
        } else if items.isEmpty {
            EmptyState("该目录暂无视频", systemImage: "film", description: "支持 mp4 / mkv / mov / m4v / avi / wmv / flv / ts / m3u8")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(items) { d in
                        NASCard(d)
                            .onTapGesture { Task { await play(d) } }
                    }
                }
                .padding(Spacing.lg)
            }
        }
    }

    private func navigateUp() {
        guard !currentPath.isEmpty else { return }
        let parts = currentPath.split(separator: "/").map(String.init)
        currentPath = parts.dropLast().joined(separator: "/")
        Task { await load() }
    }

    private func load() async {
        guard let libId = currentLibId else { items = []; return }
        isLoading = true; error = nil
        do {
            items = try await nm.browse(id: libId, path: currentPath)
        } catch {
            self.error = "加载失败：\(error.localizedDescription)"
        }
        isLoading = false
    }

    /// 点击视频卡片直接播放（单集，跳过详情页）。
    private func play(_ drama: Drama) async {
        // id = nas|<libId>|file|<path>
        let parts = drama.id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4 else { return }
        do {
            let url = try await nm.playURLString(id: parts[1], path: parts[3])
            let ep = Episode(id: "1", index: 1, title: drama.title, playURL: url)
            let detail = DramaDetail(drama: drama, episodes: [ep])
            await MainActor.run {
                PlayerWindowManager.shared.show(detail: detail, startIndex: 0)
            }
        } catch {
            self.error = "无法播放：\(error.localizedDescription)"
        }
    }
}

/// NAS 视频卡片（无封面，用文件名+图标占位；点击直接播放）。
private struct NASCard: View {
    let drama: Drama
    init(_ d: Drama) { self.drama = d }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.placeholder, Brand.secondaryBackground],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .aspectRatio(2/3, contentMode: .fit)
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Brand.accent.opacity(0.55))
                if let st = drama.updateStatus, !st.isEmpty {
                    Text(st)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(5)
                }
            }
            Text(drama.title)
                .font(Typography.caption)
                .foregroundStyle(Brand.label)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .contentShape(Rectangle())
    }
}
