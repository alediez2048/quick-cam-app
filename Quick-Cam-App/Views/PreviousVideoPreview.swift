import SwiftUI
import AVFoundation

struct PreviousVideoPreview: View {
    let video: RecordedVideo
    let onClose: () -> Void
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onClose) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(video.title)
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                // Spacer for symmetry
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .opacity(0)
            }
            .padding()

            // Video player
            if let player = player {
                VideoPlayerView(player: player)
                    .aspectRatio(9/16, contentMode: .fit)
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .onAppear {
                        player.play()
                    }
            }

            Spacer()

            // Info
            VStack(spacing: 8) {
                Text("Recorded on \(video.date.formatted(date: .long, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.gray)

                Button(action: {
                    NSWorkspace.shared.selectFile(video.url.path, inFileViewerRootedAtPath: "")
                }) {
                    HStack {
                        Image(systemName: "folder")
                        Text("Show in Finder")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            player = AVPlayer(url: video.url)
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player?.currentItem,
                queue: .main
            ) { _ in
                player?.seek(to: .zero)
                player?.play()
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
