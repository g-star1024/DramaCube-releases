import SwiftUI

/// 加载中占位。
public struct LoadingView: View {
    let message: String
    public init(_ message: String = "加载中…") { self.message = message }
    public var body: some View {
        VStack(spacing: Spacing.sm) {
            ProgressView().controlSize(.large)
            Text(message).font(Typography.caption).foregroundStyle(Brand.secondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 错误占位（带重试）。
public struct ErrorView: View {
    let message: String
    let retry: () -> Void
    public init(_ message: String, retry: @escaping () -> Void = {}) {
        self.message = message
        self.retry = retry
    }
    public var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Brand.secondaryLabel)
                .multilineTextAlignment(.center)
            Button("重试", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(Brand.pink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.lg)
    }
}

/// 空状态占位（基于 ContentUnavailableView，自动适配 Dark Mode）。
public struct EmptyState: View {
    let title: String
    let systemImage: String
    let description: String?
    public init(_ title: String, systemImage: String = "tray", description: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }
    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let d = description { Text(d) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
