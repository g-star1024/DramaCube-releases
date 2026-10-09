import SwiftUI

/// 分类筛选胶囊（SF 风格圆角 button）。
public struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    public init(_ title: String, isSelected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.caption)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? Brand.pink : .secondary)
        .controlSize(.small)
    }
}
