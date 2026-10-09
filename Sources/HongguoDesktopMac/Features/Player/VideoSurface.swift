import SwiftUI
import AVKit
import AppKit

/// 画中画协调器：持有当前播放层，提供开关能力（系统媒体中心 / 按钮共用）。
@MainActor
final class PipCoordinator: NSObject {
    static let shared = PipCoordinator()
    weak var playerLayer: AVPlayerLayer?
    var controller: AVPictureInPictureController?
    @Published var isPossible = false
    @Published var active = false

    func register(_ layer: AVPlayerLayer) {
        playerLayer = layer
        if AVPictureInPictureController.isPictureInPictureSupported(),
           let c = AVPictureInPictureController(playerLayer: layer) {
            c.delegate = self
            controller = c
            isPossible = true
        } else {
            isPossible = false
        }
    }

    func toggle() {
        guard let c = controller else { return }
        if c.isPictureInPictureActive { c.stopPictureInPicture() } else { c.startPictureInPicture() }
    }
}

extension PipCoordinator: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        MainActor.assumeIsolated { active = true }
    }
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        MainActor.assumeIsolated { active = false }
    }
}

/// 自定义视频层（NSViewRepresentable 承载 AVPlayerLayer）。
/// 相比系统 `VideoPlayer`，可直接拿到 playerLayer 以支持画中画。
struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = CGColor.black
        view.layer = layer
        PipCoordinator.shared.register(layer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let layer = nsView.layer as? AVPlayerLayer, layer.player !== player {
            layer.player = player
        }
    }
}
