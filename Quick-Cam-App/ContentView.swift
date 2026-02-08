import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var showPreview = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var selectedPreviousVideo: RecordedVideo?

    var body: some View {
        HStack(spacing: 0) {
            // Previous recordings sidebar
            PreviousRecordingsSidebar(
                recordings: cameraManager.previousRecordings,
                onSelect: { video in
                    selectedPreviousVideo = video
                },
                onDelete: { video in
                    cameraManager.deleteRecording(video)
                }
            )
            .frame(width: 200)

            // Main content
            ZStack {
                Color.black.ignoresSafeArea()

                if let selectedVideo = selectedPreviousVideo {
                    // Show selected previous video
                    PreviousVideoPreview(
                        video: selectedVideo,
                        onClose: {
                            selectedPreviousVideo = nil
                        }
                    )
                } else if showPreview, let videoURL = cameraManager.recordedVideoURL {
                    PreviewView(
                        videoURL: videoURL,
                        isExporting: cameraManager.isExporting,
                        isTranscribing: cameraManager.isTranscribing,
                        transcriptionProgress: cameraManager.transcriptionProgress,
                        onSave: { title, enableCaptions in
                            cameraManager.exportToDownloads(title: title, enableCaptions: enableCaptions) { success, path in
                                if success {
                                    cameraManager.discardRecording()
                                    showPreview = false
                                    cameraManager.setupAndStartSession()
                                }
                            }
                        },
                        onRetake: {
                            cameraManager.discardRecording()
                            showPreview = false
                            cameraManager.setupAndStartSession()
                        }
                    )
                } else {
                    VStack(spacing: 0) {
                        // Camera picker at top
                        HStack {
                            if cameraManager.availableCameras.count > 1 {
                                Picker("Camera", selection: Binding(
                                    get: { cameraManager.selectedCamera },
                                    set: { newCamera in
                                        if let camera = newCamera {
                                            cameraManager.switchCamera(to: camera)
                                        }
                                    }
                                )) {
                                    ForEach(cameraManager.availableCameras, id: \.uniqueID) { camera in
                                        Text(camera.localizedName).tag(camera as AVCaptureDevice?)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: 250)
                                .disabled(cameraManager.isRecording)
                            }

                            Spacer()

                            if cameraManager.isRecording {
                                VStack(spacing: 4) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(.red)
                                            .frame(width: 10, height: 10)
                                        Text("REC")
                                            .foregroundColor(.red)
                                            .fontWeight(.bold)
                                    }
                                    Text(formatDuration(recordingDuration))
                                        .foregroundColor(.white)
                                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.6))
                                .cornerRadius(6)
                            }
                        }
                        .padding()

                        // Camera preview
                        CameraPreviewView(cameraManager: cameraManager)
                            .aspectRatio(9/16, contentMode: .fit)
                            .cornerRadius(12)
                            .padding(.horizontal)
                            .overlay(
                                Group {
                                    if !cameraManager.isAuthorized {
                                        VStack(spacing: 12) {
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 40))
                                            Text("Camera access required")
                                                .font(.headline)
                                            Text("Please allow camera access to use Quick Cam")
                                                .font(.caption)
                                                .multilineTextAlignment(.center)
                                        }
                                        .foregroundColor(.white)
                                        .padding()
                                    } else if !cameraManager.isReady || !cameraManager.isSessionRunning {
                                        VStack(spacing: 8) {
                                            ProgressView()
                                                .scaleEffect(1.5)
                                                .tint(.white)
                                            Text("Starting camera...")
                                                .font(.caption)
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                            )

                        Spacer()

                        // Record button
                        Button(action: {
                            if cameraManager.isRecording {
                                cameraManager.stopRecording()
                            } else {
                                cameraManager.startRecording()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .stroke(lineWidth: 4)
                                    .foregroundColor(.white)
                                    .frame(width: 72, height: 72)

                                if cameraManager.isRecording {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(.red)
                                        .frame(width: 28, height: 28)
                                } else {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 56, height: 56)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!cameraManager.isReady || !cameraManager.isSessionRunning)
                        .opacity(cameraManager.isReady && cameraManager.isSessionRunning ? 1.0 : 0.5)
                        .padding(.bottom, 40)
                    }
                }

                // Error display
                if let error = cameraManager.error {
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
            cameraManager.checkAuthorization()
            cameraManager.loadPreviousRecordings()
        }
        .onChange(of: cameraManager.recordedVideoURL) { _, newURL in
            if newURL != nil {
                showPreview = true
                cameraManager.stopSession()
            }
        }
        .onChange(of: cameraManager.isRecording) { _, isRecording in
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

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Previous Recordings Sidebar

struct PreviousRecordingsSidebar: View {
    let recordings: [RecordedVideo]
    let onSelect: (RecordedVideo) -> Void
    let onDelete: (RecordedVideo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Previous Recordings")
                .font(.headline)
                .foregroundColor(.white)
                .padding()

            if recordings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                    Text("No recordings yet")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(recordings) { video in
                            PreviousRecordingCard(
                                video: video,
                                onSelect: { onSelect(video) },
                                onDelete: { onDelete(video) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color.black.opacity(0.8))
    }
}

struct PreviousRecordingCard: View {
    let video: RecordedVideo
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                // Thumbnail
                ZStack {
                    if let thumbnail = video.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(9/16, contentMode: .fill)
                            .frame(height: 120)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .aspectRatio(9/16, contentMode: .fill)
                            .frame(height: 120)
                            .overlay(
                                Image(systemName: "video")
                                    .foregroundColor(.gray)
                            )
                    }

                    // Play icon overlay
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white.opacity(0.8))

                    // Delete button
                    if isHovering {
                        VStack {
                            HStack {
                                Spacer()
                                Button(action: onDelete) {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white)
                                        .padding(6)
                                        .background(Color.red)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .padding(4)
                            }
                            Spacer()
                        }
                    }
                }
                .cornerRadius(8)

                // Title and date
                Text(video.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(video.date, style: .date)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Previous Video Preview

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

// MARK: - Camera Preview

struct CameraPreviewView: NSViewRepresentable {
    @ObservedObject var cameraManager: CameraManager

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.setSession(cameraManager.session)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        // Don't update the session - it's already set
    }
}

class CameraPreviewNSView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasSetupLayer = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    func setSession(_ session: AVCaptureSession) {
        guard !hasSetupLayer else { return }
        hasSetupLayer = true

        let newPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
        newPreviewLayer.videoGravity = .resizeAspectFill
        newPreviewLayer.frame = bounds

        layer?.addSublayer(newPreviewLayer)
        previewLayer = newPreviewLayer
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}

#Preview {
    ContentView()
}
