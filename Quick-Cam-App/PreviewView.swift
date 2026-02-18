import SwiftUI
import AVKit
import AVFoundation

struct PreviewView: View {
    let videoURL: URL
    let aspectRatio: AspectRatioOption
    let isExporting: Bool
    let isTranscribing: Bool
    let isProcessingAudio: Bool
    let transcriptionProgress: String
    let onSave: (String, Bool, Bool, CaptionStyle, TranscriptionLanguage) -> Void
    let onRetake: () -> Void

    @State private var player: AVPlayer?
    @State private var videoTitle: String = ""
    @State private var enableCaptions: Bool = false
    @State private var enhanceAudio: Bool = false
    @State private var selectedCaptionStyle: CaptionStyle = .classic
    @AppStorage("transcriptionLanguage") private var selectedLanguage: TranscriptionLanguage = .english
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Preview")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding()

            // Video player - cropped to 9:16 vertical preview
            if let player = player {
                CroppedVideoPlayerView(player: player)
                    .aspectRatio(aspectRatio.ratio, contentMode: .fit)
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .onAppear {
                        player.play()
                    }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(aspectRatio.ratio, contentMode: .fit)
                    .cornerRadius(12)
                    .overlay(
                        ProgressView()
                            .scaleEffect(1.5)
                    )
                    .padding(.horizontal)
            }

            ScrollView {
                // Title input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Video Title (optional)")
                        .font(.caption)
                        .foregroundColor(.gray)
                    TextField("Enter a title...", text: $videoTitle)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTitleFocused)
                }
                .padding(.horizontal)
                .padding(.top, 16)

                // Auto-captions toggle
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-generate captions")
                            .foregroundColor(.white)
                        Text("Transcribe speech and add subtitles")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Toggle("", isOn: $enableCaptions)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.top, 12)

                // Caption options
                if enableCaptions {
                    // Language selector
                    HStack {
                        Text("Language")
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $selectedLanguage) {
                            ForEach(TranscriptionLanguage.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .frame(width: 150)
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    if !selectedLanguage.isAvailable {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                            Text("\(selectedLanguage.displayName) is not available on this system")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                        .padding(.horizontal)
                        .padding(.top, 4)
                    }

                    // Caption style picker
                    CaptionStylePickerView(selectedStyle: $selectedCaptionStyle)
                }

                // Enhance audio toggle
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enhance audio")
                            .foregroundColor(.white)
                        Text("Remove background noise and normalize volume")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Toggle("", isOn: $enhanceAudio)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.top, 8)
            }

            Spacer()

            // Action buttons
            if isExporting || isTranscribing || isProcessingAudio {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(isProcessingAudio ? "Enhancing audio…" : isTranscribing ? transcriptionProgress : "Exporting...")
                        .foregroundColor(.white)
                        .font(.caption)
                }
                .padding(.bottom, 40)
            } else {
                HStack(spacing: 40) {
                    Button(action: onRetake) {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 24))
                            Text("Retake")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(width: 80, height: 80)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        onSave(videoTitle, enableCaptions, enhanceAudio, selectedCaptionStyle, selectedLanguage)
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 24))
                            Text("Save")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(width: 80, height: 80)
                        .background(Color.green)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            player = AVPlayer(url: videoURL)
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
