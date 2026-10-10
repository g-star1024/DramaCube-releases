import SwiftUI

// MARK: - 全局字体缩放环境（M4）
// 经 @Environment(\.uiFontScale) 注入；自定义文本用 .scaled() 应用。

private struct UIFontScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

public extension EnvironmentValues {
    var uiFontScale: Double {
        get { self[UIFontScaleKey.self] }
        set { self[UIFontScaleKey.self] = newValue }
    }
}

public extension View {
    /// 按全局缩放系数放大字体（对自定义字号文本生效）。
    func uiScaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(UIScaledFontModifier(size: size, weight: weight, design: design))
    }
}

private struct UIScaledFontModifier: ViewModifier {
    @Environment(\.uiFontScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}
