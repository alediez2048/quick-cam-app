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
    let isGeneratingPreview: Bool
    let previewPlayerItem: AVPlayerItem?
    let onSave: (String, Bool, Bool, CaptionStyle, TranscriptionLanguage, [TimedCaption], [CMTimeRange]) -> Void
    let onRetake: () -> Void
    let onPreview: (Bool, Bool, AspectRatioOption, CaptionStyle, TranscriptionLanguage, [TimedCaption], [CMTimeRange]) -> Void
    let onDismissPreview: () -> Void

    @State private var player: AVPlayer?
    @State private var videoTitle: String = ""
    @State private var enableCaptions: Bool = false
    @State private var enhanceAudio: Bool = false
    @State private var selectedCaptionStyle: CaptionStyle = .classic
    @AppStorage("transcriptionLanguage") private var selectedLanguage: TranscriptionLanguage = .english
    @State private var captions: [TimedCaption] = []
    @State private var deletedWordIndices: Set<Int> = []
    @State private var isLocallyTranscribing: Bool = false
    @State private var speechAuthDenied: Bool = false
    @State private var showPreviewOverlay: Bool = false
    @State private var previewPlayer: AVPlayer?
    @State private var previewCaptions: [TimedCaption] = []
    @State private var previewCaptionStyle: CaptionStyle = .classic
    @FocusState private var isTitleFocused: Bool
    private let transcriptionService = TranscriptionService()

    var body: some View {
        ZStack {
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

                        if speechAuthDenied {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                                Text("Speech recognition not authorized. Grant permission in System Settings > Privacy & Security > Speech Recognition.")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                            .padding(.horizontal)
                            .padding(.top, 4)
                        } else if !selectedLanguage.isAvailable {
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

                        // Transcript editor
                        if let player = player {
                            if isLocallyTranscribing {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Transcribing...")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            } else if !captions.isEmpty {
                                TranscriptEditorView(
                                    captions: $captions,
                                    player: player,
                                    deletedWordIndices: $deletedWordIndices
                                )
                            }
                        }
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
                        Text(isProcessingAudio ? "Enhancing audio..." : isTranscribing ? transcriptionProgress : "Exporting...")
                            .foregroundColor(.white)
                            .font(.caption)
                    }
                    .padding(.bottom, 40)
                } else if isGeneratingPreview {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Building preview...")
                            .foregroundColor(.white)
                            .font(.caption)
                    }
                    .padding(.bottom, 40)
                } else {
                    HStack(spacing: 20) {
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
                            let exclusionRanges = computeExclusionRanges()
                            previewCaptionStyle = selectedCaptionStyle
                            if enableCaptions {
                                previewCaptions = exclusionRanges.isEmpty
                                    ? captions
                                    : ExportService.adjustCaptions(captions, excludedRanges: exclusionRanges)
                            } else {
                                previewCaptions = []
                            }
                            onPreview(enableCaptions, enhanceAudio, aspectRatio, selectedCaptionStyle, selectedLanguage, captions, exclusionRanges)
                        }) {
                            VStack(spacing: 8) {
                                Image(systemName: "eye")
                                    .font(.system(size: 24))
                                Text("Preview")
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                            .frame(width: 80, height: 80)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            let exclusionRanges = computeExclusionRanges()
                            onSave(videoTitle, enableCaptions, enhanceAudio, selectedCaptionStyle, selectedLanguage, captions, exclusionRanges)
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

            if showPreviewOverlay, let previewPlayer = previewPlayer {
                PreviewOverlayView(
                    player: previewPlayer,
                    captions: previewCaptions,
                    captionStyle: previewCaptionStyle,
                    videoAspectRatio: aspectRatio.ratio
                ) {
                    showPreviewOverlay = false
                    previewPlayer.pause()
                    self.previewPlayer = nil
                    onDismissPreview()
                    player?.seek(to: .zero)
                    player?.play()
                }
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
            previewPlayer?.pause()
            previewPlayer = nil
        }
        .onChange(of: enableCaptions) { _, enabled in
            if enabled && captions.isEmpty {
                transcribeVideo()
            }
        }
        .onChange(of: selectedLanguage) { _, _ in
            if enableCaptions {
                captions = []
                deletedWordIndices = []
                transcribeVideo()
            }
        }
        .onChange(of: previewPlayerItem) { _, newItem in
            if let newItem = newItem {
                player?.pause()
                let newPlayer = AVPlayer(playerItem: newItem)
                previewPlayer = newPlayer
                showPreviewOverlay = true
                newPlayer.play()
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: newItem,
                    queue: .main
                ) { _ in
                    newPlayer.seek(to: .zero)
                    newPlayer.play()
                }
            }
        }
    }

    private func computeExclusionRanges() -> [CMTimeRange] {
        guard !deletedWordIndices.isEmpty else { return [] }
        let allWords = captions.flatMap { $0.words }
        return deletedWordIndices.compactMap { index -> CMTimeRange? in
            guard index < allWords.count else { return nil }
            let word = allWords[index]
            return CMTimeRange(start: word.startTime, end: word.endTime)
        }
    }

    private func transcribeVideo() {
        isLocallyTranscribing = true
        speechAuthDenied = false
        Task {
            let authorized = await TranscriptionService.requestAuthorizationIfNeeded()
            guard authorized else {
                await MainActor.run {
                    isLocallyTranscribing = false
                    speechAuthDenied = true
                    enableCaptions = false
                }
                return
            }
            let result = (try? await transcriptionService.transcribeAudio(
                from: videoURL,
                locale: selectedLanguage.locale
            )) ?? []
            await MainActor.run {
                captions = result
                isLocallyTranscribing = false
            }
        }
    }
}
