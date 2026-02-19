import SwiftUI
import AVFoundation

struct ComposedVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerContainerView {
        let containerView = PlayerContainerView()
        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = true
        containerView.layer?.backgroundColor = NSColor.black.cgColor

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        containerView.layer?.addSublayer(playerLayer)
        containerView.playerLayer = playerLayer

        return containerView
    }

    func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        nsView.playerLayer?.player = player
        nsView.playerLayer?.frame = nsView.bounds
    }

    class PlayerContainerView: NSView {
        var playerLayer: AVPlayerLayer?

        override func layout() {
            super.layout()
            playerLayer?.frame = bounds
        }
    }
}
