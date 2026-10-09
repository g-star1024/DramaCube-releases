import SwiftUI
import AVKit
import HongguoCore

/// 播放器界面。经本地网关代理 CDN 直链（剥离 Referer）。
///
/// 注意：当前网关以「整文件代理」方式返回媒体，适合渐进式 MP4；
/// 对 HLS(m3u8) 的流式播放将在 M5 中让网关支持 Range/分片后完善。
public struct PlayerView: View {
    let detail: DramaDetail
    @State private var player: AVPlayer?
    @State private var current: Episode?

    public init(detail: DramaDetail) {
        self.detail = detail
        let first = detail.episodes.first
        _current = State(initialValue: first)
        if let url = first?.playURL {
            _player = State(initialValue: AVPlayer(url: Self.gatewayURL(for: url)))
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let player {
                VideoPlayer(player: player)
                    .frame(minHeight: 400)
            } else {
                ContentUnavailableView("暂无可播放地址", systemImage: "play.slash")
            }
            Divider()
            episodeStrip
        }
        .frame(width: 880, height: 600)
        .navigationTitle(detail.drama.title)
    }

    private var episodeStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.sm) {
                ForEach(detail.episodes) { ep in
                    Button {
                        current = ep
                        if let url = ep.playURL {
                            player?.replaceCurrentItem(with: AVPlayerItem(url: Self.gatewayURL(for: url)))
                            player?.play()
                        }
                    } label: {
                        Text("\(ep.index)").padding(.horizontal, 8).padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .tint(ep.id == current?.id ? Brand.pink : .secondary)
                }
            }
            .padding(Spacing.sm)
        }
    }

    /// 将 CDN 直链包成网关代理地址（网关负责剥离 Referer）。
    static func gatewayURL(for cdnURL: String) -> URL {
        let encoded = cdnURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cdnURL
        return URL(string: "\(AppConfig.gatewayBaseURL)/api/play?url=\(encoded)")!
    }
}
