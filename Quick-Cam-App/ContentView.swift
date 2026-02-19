import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var cameraViewModel = CameraViewModel()
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var selectedPreviousVideo: RecordedVideo?
    @State private var showPreview = false

    var body: some View {
        HStack(spacing: 0) {
            PreviousRecordingsSidebar(
                recordings: cameraViewModel.previousRecordings,
                onSelect: { video in
                    selectedPreviousVideo = video
                },
                onDelete: { video in
                    cameraViewModel.deleteRecording(video)
                }
            )
            .frame(width: 200)

            ZStack {
                Color.black.ignoresSafeArea()

                if let selectedVideo = selectedPreviousVideo {
                    PreviousVideoPreview(
                        video: selectedVideo,
                        onClose: {
                            selectedPreviousVideo = nil
                        }
                    )
                } else if showPreview, let videoURL = cameraViewModel.recordedVideoURL {
                    PreviewView(
                        videoURL: videoURL,
                        aspectRatio: cameraViewModel.selectedAspectRatio,
                        isExporting: cameraViewModel.isExporting,
                        isTranscribing: cameraViewModel.isTranscribing,
                        isProcessingAudio: cameraViewModel.isProcessingAudio,
                        transcriptionProgress: cameraViewModel.transcriptionProgress,
                        isGeneratingPreview: cameraViewModel.isGeneratingPreview,
                        previewPlayerItem: cameraViewModel.previewPlayerItem,
                        onSave: { title, enableCaptions, enhanceAudio, captionStyle, language, preTranscribedCaptions, exclusionRanges in
                            cameraViewModel.exportToDownloads(title: title, enableCaptions: enableCaptions, enhanceAudio: enhanceAudio, aspectRatio: cameraViewModel.selectedAspectRatio, captionStyle: captionStyle, language: language, preTranscribedCaptions: preTranscribedCaptions, exclusionRanges: exclusionRanges) { success, path in
                                guard success else { return }
                                DispatchQueue.main.async {
                                    showPreview = false
                                    cameraViewModel.discardRecording()
                                    cameraViewModel.setupAndStartSession()
                                }
                            }
                        },
                        onRetake: {
                            cameraViewModel.discardRecording()
                            showPreview = false
                            cameraViewModel.setupAndStartSession()
                        },
                        onPreview: { enableCaptions, enhanceAudio, aspectRatio, captionStyle, language, preTranscribedCaptions, exclusionRanges in
                            cameraViewModel.generatePreview(
                                enableCaptions: enableCaptions,
                                enhanceAudio: enhanceAudio,
                                aspectRatio: aspectRatio,
                                captionStyle: captionStyle,
                                language: language,
                                preTranscribedCaptions: preTranscribedCaptions,
                                exclusionRanges: exclusionRanges
                            )
                        },
                        onDismissPreview: {
                            cameraViewModel.previewPlayerItem = nil
                        }
                    )
                } else {
                    RecordingControlsView(
                        cameraViewModel: cameraViewModel,
                        recordingDuration: $recordingDuration
                    )
                }

                if let error = cameraViewModel.error {
                    VStack {
                        Text(error)
                            .foregroundColor(.white)
                            .padding()
                            .background(.red.opacity(0.8))
                            .cornerRadius(8)
                        Spacer()
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 600, minHeight: 700)
        .onAppear {
            cameraViewModel.checkAuthorization()
            cameraViewModel.loadPreviousRecordings()
        }
        .onChange(of: cameraViewModel.recordedVideoURL) { _, newURL in
            if newURL != nil {
                showPreview = true
                cameraViewModel.stopSession()
            }
        }
        .onChange(of: cameraViewModel.isRecording) { _, isRecording in
            if isRecording {
                recordingDuration = 0
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    recordingDuration += 0.1
                }
            } else {
                recordingTimer?.invalidate()
                recordingTimer = nil
            }
        }
        .onChange(of: cameraViewModel.isPaused) { _, isPaused in
            if isPaused {
                recordingTimer?.invalidate()
                recordingTimer = nil
            } else if cameraViewModel.isRecording {
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    recordingDuration += 0.1
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
