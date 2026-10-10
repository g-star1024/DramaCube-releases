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
    @State private var allItems: [Drama] = []     // 当前目录全部视频（一次性从 NAS 列出，轻量）
    @State private var visibleCount = 30           // 懒加载：首屏只渲染前 30 个，滚动加载更多
    @State private var isLoading = false
    @State private var error: String?

    private let pageSize = 30

    /// 当前可见的卡片（懒加载切片）。封面生成是重活，只渲染可见部分避免一次性打满 CPU/IO。
    private var items: [Drama] { Array(allItems.prefix(visibleCount)) }

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
        } else if allItems.isEmpty && isLoading {
            LoadingView("正在扫描媒体库…")
        } else if allItems.isEmpty {
            EmptyState("该目录暂无视频", systemImage: "film", description: "支持 mp4 / mkv / mov / m4v / avi / wmv / flv / ts / m3u8")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(items) { d in
                        NASCard(d)
                            .onTapGesture { onSelect(d) }
                            .onAppear {
                                // 懒加载：滚到倒数第 6 个时加载下一批封面/卡片
                                if d.id == items.dropLast(6).last?.id, visibleCount < allItems.count {
                                    visibleCount = min(visibleCount + pageSize, allItems.count)
                                }
                            }
                    }
                }
                .padding(Spacing.lg)
                // 底部加载更多提示
                if visibleCount < allItems.count {
                    HStack(spacing: Spacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("加载更多…（\(visibleCount)/\(allItems.count)）")
                            .font(Typography.caption)
                            .foregroundStyle(Brand.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Spacing.lg)
                } else if allItems.count > pageSize {
                    Text("共 \(allItems.count) 个视频")
                        .font(Typography.caption)
                        .foregroundStyle(Brand.secondaryLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, Spacing.lg)
                }
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
        guard let libId = currentLibId else { allItems = []; return }
        isLoading = true; error = nil
        do {
            allItems = try await nm.browse(id: libId, path: currentPath)
            visibleCount = min(pageSize, allItems.count)  // 重置懒加载到首屏数量
        } catch {
            self.error = "加载失败：\(error.localizedDescription)"
        }
        isLoading = false
    }
}

/// NAS 视频卡片（无封面，暖沙底+播放图标占位；点击进详情选集）。
private struct NASCard: View {
    let drama: Drama
    init(_ d: Drama) { self.drama = d }

    @State private var coverURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.placeholder, Brand.secondaryBackground],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .aspectRatio(2/3, contentMode: .fit)
                if let coverURL, let img = NSImage(contentsOf: coverURL) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                } else {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Brand.accent.opacity(0.55))
                }
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
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            Text(drama.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.label)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(drama.title)
                .frame(maxWidth: .infinity, alignment: .leading)
            // 固定信息行高度占位，避免卡片高度不一错位
            Text(" ")
                .font(.system(size: 12))
        }
        .contentShape(Rectangle())
        .task { await loadCover() }
    }

    /// 加载首帧封面：先查缓存，无则后台生成。
    private func loadCover() async {
        // id = nas|<libId>|file|<path>，需还原播放地址
        let parts = drama.id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4 else { return }
        guard let playURL = try? await NASManager.shared.playURLString(id: parts[1], path: parts[3]) else { return }
        if let url = await NASCoverGenerator.shared.cover(forVideoPlayURL: playURL) {
            coverURL = url
        }
    }
}
