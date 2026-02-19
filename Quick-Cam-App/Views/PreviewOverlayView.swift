import SwiftUI
import AVFoundation

struct PreviewOverlayView: View {
    let player: AVPlayer
    let captions: [TimedCaption]
    let captionStyle: CaptionStyle
    let videoAspectRatio: CGFloat
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                ZStack {
                    ComposedVideoPlayerView(player: player)

                    if !captions.isEmpty {
                        LiveCaptionOverlayView(
                            player: player,
                            captions: captions,
                            captionStyle: captionStyle,
                            videoAspectRatio: videoAspectRatio
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)

                Text("This is how your exported video will look")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.bottom, 16)
            }
        }
    }
}
