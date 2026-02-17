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
                        isExporting: cameraViewModel.isExporting,
                        isTranscribing: cameraViewModel.isTranscribing,
                        transcriptionProgress: cameraViewModel.transcriptionProgress,
                        onSave: { title, enableCaptions in
                            cameraViewModel.exportToDownloads(title: title, enableCaptions: enableCaptions) { success, path in
                                if success {
                                    cameraViewModel.discardRecording()
                                    showPreview = false
                                    cameraViewModel.setupAndStartSession()
                                }
                            }
                        },
                        onRetake: {
                            cameraViewModel.discardRecording()
                            showPreview = false
                            cameraViewModel.setupAndStartSession()
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
    }
}

#Preview {
    ContentView()
}
