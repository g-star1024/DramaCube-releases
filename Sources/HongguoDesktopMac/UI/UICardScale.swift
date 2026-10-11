import SwiftUI

// MARK: - 全局界面密度环境
// 由 HongguoApp 注入（= AppSettings.uiFontScale）。
// 各海报/视频网格把 adaptive 卡片宽度乘以该系数，实现「界面缩放」——
// 只调卡片/封面的排布密度，不动窗口 frame、不用 transform，
// 因此命中测试正常、布局平滑重排，绝无 v2.1.1 scaleEffect 的失控问题。

private struct UICardScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

public extension EnvironmentValues {
    /// 界面密度系数（0.85 ~ 1.3，1.0 默认）。网格卡片宽度乘以它。
    var uiCardScale: Double {
        get { self[UICardScaleKey.self] }
        set { self[UICardScaleKey.self] = newValue }
    }
}
