import SwiftUI
import AppKit
import QuartzCore

// MARK: - mpv 视频渲染承载视图
// 把 MpvEngine.metalLayer 作为 NSView 的 layer，SwiftUI 通过 NSViewRepresentable 嵌入。

public struct MpvVideoSurface: NSViewRepresentable {
    let engine: MpvEngine

    public init(engine: MpvEngine) { self.engine = engine }

    public func makeNSView(context: Context) -> MpvMetalView {
        let v = MpvMetalView()
        v.attach(engine: engine)
        return v
    }

    public func updateNSView(_ nsView: MpvMetalView, context: Context) {
        nsView.attach(engine: engine)
    }
}

/// 承载 CAMetalLayer 的 NSView（mpv 通过 wid 渲染到此 layer）。
public final class MpvMetalView: NSView {
    private weak var engine: MpvEngine?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    func attach(engine: MpvEngine) {
        self.engine = engine
        engine.metalLayer.frame = bounds
        engine.metalLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        if layer !== engine.metalLayer {
            layer = engine.metalLayer
        }
    }

    override public func layout() {
        super.layout()
        engine?.metalLayer.frame = bounds
    }

    override public func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        engine?.metalLayer.contentsScale = window?.backingScaleFactor ?? 2
    }
}
