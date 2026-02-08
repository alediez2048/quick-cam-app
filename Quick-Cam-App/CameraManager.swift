import AVFoundation
import AppKit
import Combine
import QuartzCore
import Speech

struct TimedCaption {
    let text: String
    let startTime: CMTime
    let endTime: CMTime
}

struct RecordedVideo: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let thumbnail: NSImage?
    let date: Date
    let title: String

    static func == (lhs: RecordedVideo, rhs: RecordedVideo) -> Bool {
        lhs.url == rhs.url
    }
}

class CameraManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordedVideoURL: URL?
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCamera: AVCaptureDevice?
    @Published var error: String?
    @Published var isSessionRunning = false
    @Published var isAuthorized = false
    @Published var isReady = false
    @Published var previousRecordings: [RecordedVideo] = []
    @Published var isExporting = false
    @Published var isTranscribing = false
    @Published var transcriptionProgress: String = ""

    private let captureSession = AVCaptureSession()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var movieOutput = AVCaptureMovieFileOutput()
    private var currentInput: AVCaptureDeviceInput?
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var isConfiguring = false

    var session: AVCaptureSession {
        captureSession
    }

    override init() {
        super.init()
        discoverCameras()
    }

    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async {
                self.isAuthorized = true
            }
            setupAndStartSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                }
                if granted {
                    self?.setupAndStartSession()
                } else {
                    DispatchQueue.main.async {
                        self?.error = "Camera access denied"
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.isAuthorized = false
                self.error = "Camera access denied. Please enable in System Settings > Privacy & Security > Camera"
            }
        @unknown default:
            break
        }
    }

    func discoverCameras() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        availableCameras = discoverySession.devices
        if selectedCamera == nil {
            selectedCamera = availableCameras.first
        }
    }

    func setupAndStartSession() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
            self?.startRunning()
        }
    }

    private func configureSession() {
        guard !isConfiguring else { return }
        isConfiguring = true

        captureSession.beginConfiguration()

        // Remove existing inputs and outputs
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }

        // Start with high preset (most compatible)
        captureSession.sessionPreset = .high

        // Add camera input
        guard let camera = selectedCamera else {
            DispatchQueue.main.async {
                self.error = "No camera available"
                self.isReady = false
            }
            captureSession.commitConfiguration()
            isConfiguring = false
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                currentInput = input
            } else {
                DispatchQueue.main.async {
                    self.error = "Cannot add camera input - camera may be in use"
                    self.isReady = false
                }
                captureSession.commitConfiguration()
                isConfiguring = false
                return
            }
        } catch {
            DispatchQueue.main.async {
                self.error = "Failed to access camera: \(error.localizedDescription)"
                self.isReady = false
            }
            captureSession.commitConfiguration()
            isConfiguring = false
            return
        }

        // Try to upgrade to higher quality after input is added
        if captureSession.canSetSessionPreset(.hd4K3840x2160) {
            captureSession.sessionPreset = .hd4K3840x2160
        } else if captureSession.canSetSessionPreset(.hd1920x1080) {
            captureSession.sessionPreset = .hd1920x1080
        }

        // Add audio input (optional - don't fail if unavailable)
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession.canAddInput(audioInput) {
                    captureSession.addInput(audioInput)
                }
            } catch {
                // Audio not available, continue without it
            }
        }

        // Add movie output
        movieOutput = AVCaptureMovieFileOutput()
        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
        } else {
            DispatchQueue.main.async {
                self.error = "Cannot add movie output"
                self.isReady = false
            }
            captureSession.commitConfiguration()
            isConfiguring = false
            return
        }

        captureSession.commitConfiguration()
        isConfiguring = false

        DispatchQueue.main.async {
            self.error = nil
            self.isReady = true
        }
    }

    private func startRunning() {
        if !captureSession.isRunning {
            captureSession.startRunning()
        }
        DispatchQueue.main.async {
            self.isSessionRunning = self.captureSession.isRunning
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    func switchCamera(to camera: AVCaptureDevice) {
        // Update UI state immediately
        DispatchQueue.main.async {
            self.selectedCamera = camera
            self.isReady = false
        }

        // Reconfigure session on background queue
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            // Stop if running
            let wasRunning = self.captureSession.isRunning
            if wasRunning {
                self.captureSession.stopRunning()
            }

            // Reconfigure
            self.configureSession()

            // Restart if it was running
            if wasRunning {
                self.startRunning()
            }
        }
    }

    func startRecording() {
        // Quick check on main thread
        guard !isRecording else { return }

        // Set recording state immediately to prevent double-taps
        isRecording = true

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            guard self.captureSession.isRunning else {
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.error = "Camera session not running"
                }
                return
            }

            guard let connection = self.movieOutput.connection(with: .video) else {
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.error = "Video connection not available"
                }
                return
            }

            // Create temp file URL
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "QuickCam_\(Date().timeIntervalSince1970).mov"
            let fileURL = tempDir.appendingPathComponent(fileName)

            try? FileManager.default.removeItem(at: fileURL)

            // Record in native orientation - we'll rotate during export
            self.movieOutput.startRecording(to: fileURL, recordingDelegate: self)
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        sessionQueue.async { [weak self] in
            self?.movieOutput.stopRecording()
        }
    }

    func exportToDownloads(title: String, enableCaptions: Bool = false, completion: @escaping (Bool, String?) -> Void) {
        guard let sourceURL = recordedVideoURL else {
            completion(false, "No video to export")
            return
        }

        isExporting = true

        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        let sanitizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileName: String
        if sanitizedTitle.isEmpty {
            fileName = "QuickCam_\(dateFormatter.string(from: Date())).mov"
        } else {
            fileName = "\(sanitizedTitle)_\(dateFormatter.string(from: Date())).mov"
        }
        let destinationURL = downloadsURL.appendingPathComponent(fileName)

        try? FileManager.default.removeItem(at: destinationURL)

        let asset = AVAsset(url: sourceURL)

        Task {
            do {
                // Transcribe audio if captions enabled
                var captions: [TimedCaption] = []
                if enableCaptions {
                    await MainActor.run {
                        self.isTranscribing = true
                        self.transcriptionProgress = "Transcribing audio..."
                    }
                    captions = await self.transcribeAudio(from: sourceURL)
                    await MainActor.run {
                        self.isTranscribing = false
                        self.transcriptionProgress = ""
                    }
                }

                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)

                guard let videoTrack = videoTracks.first else {
                    await MainActor.run {
                        self.isExporting = false
                        completion(false, "No video track found")
                    }
                    return
                }

                let naturalSize = try await videoTrack.load(.naturalSize)
                let duration = try await asset.load(.duration)

                let composition = AVMutableComposition()

                guard let compositionVideoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    await MainActor.run {
                        self.isExporting = false
                        completion(false, "Failed to create video track")
                    }
                    return
                }

                let timeRange = CMTimeRange(start: .zero, duration: duration)
                try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)

                if let audioTrack = audioTracks.first {
                    if let compositionAudioTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    ) {
                        try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
                    }
                }

                let sourceWidth = naturalSize.width
                let sourceHeight = naturalSize.height
                let outputWidth: CGFloat = 2160
                let outputHeight: CGFloat = 3840

                let scale = outputHeight / sourceHeight
                let scaledWidth = sourceWidth * scale
                let translateX = -(scaledWidth - outputWidth) / 2.0

                var transform = CGAffineTransform.identity
                transform = transform.scaledBy(x: scale, y: scale)
                transform = transform.translatedBy(x: translateX / scale, y: 0)

                let videoComposition = AVMutableVideoComposition()
                videoComposition.renderSize = CGSize(width: outputWidth, height: outputHeight)
                videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = timeRange

                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
                layerInstruction.setTransform(transform, at: .zero)

                instruction.layerInstructions = [layerInstruction]
                videoComposition.instructions = [instruction]

                // Add timed captions if we have transcription
                if !captions.isEmpty {
                    let videoLayer = CALayer()
                    videoLayer.frame = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)

                    let parentLayer = CALayer()
                    parentLayer.frame = videoLayer.frame
                    parentLayer.addSublayer(videoLayer)

                    let totalDuration = CMTimeGetSeconds(duration)

                    // Create text layers for each caption segment
                    for caption in captions {
                        let textLayer = CATextLayer()
                        textLayer.string = caption.text
                        textLayer.font = "HelveticaNeue-Bold" as CFTypeRef
                        textLayer.fontSize = 72
                        textLayer.foregroundColor = NSColor.white.cgColor
                        textLayer.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
                        textLayer.alignmentMode = .center
                        textLayer.contentsScale = 2.0
                        textLayer.isWrapped = true
                        textLayer.truncationMode = .end

                        // Position at bottom
                        let padding: CGFloat = 100
                        let textHeight: CGFloat = 200
                        let textWidth = outputWidth - (padding * 2)
                        textLayer.frame = CGRect(
                            x: padding,
                            y: padding,
                            width: textWidth,
                            height: textHeight
                        )

                        // Animate opacity to show/hide caption at correct times
                        let startSeconds = CMTimeGetSeconds(caption.startTime)
                        let endSeconds = CMTimeGetSeconds(caption.endTime)

                        // Start hidden
                        textLayer.opacity = 0

                        let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
                        opacityAnimation.values = [0, 0, 1, 1, 0, 0]
                        opacityAnimation.keyTimes = [
                            0,
                            NSNumber(value: max(0, startSeconds - 0.01) / totalDuration),
                            NSNumber(value: startSeconds / totalDuration),
                            NSNumber(value: endSeconds / totalDuration),
                            NSNumber(value: min(totalDuration, endSeconds + 0.01) / totalDuration),
                            1
                        ]
                        opacityAnimation.duration = totalDuration
                        opacityAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
                        opacityAnimation.isRemovedOnCompletion = false
                        textLayer.add(opacityAnimation, forKey: "opacity")

                        parentLayer.addSublayer(textLayer)
                    }

                    videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                        postProcessingAsVideoLayer: videoLayer,
                        in: parentLayer
                    )
                }

                guard let exportSession = AVAssetExportSession(
                    asset: composition,
                    presetName: AVAssetExportPresetHighestQuality
                ) else {
                    await MainActor.run {
                        self.isExporting = false
                        completion(false, "Failed to create export session")
                    }
                    return
                }

                exportSession.outputURL = destinationURL
                exportSession.outputFileType = .mov
                exportSession.videoComposition = videoComposition

                await exportSession.export()

                switch exportSession.status {
                case .completed:
                    await MainActor.run {
                        self.isExporting = false
                        self.loadPreviousRecordings()
                        completion(true, destinationURL.path)
                    }
                case .failed:
                    let errorMsg = exportSession.error?.localizedDescription ?? "Export failed"
                    await MainActor.run {
                        self.isExporting = false
                        completion(false, errorMsg)
                    }
                case .cancelled:
                    await MainActor.run {
                        self.isExporting = false
                        completion(false, "Export cancelled")
                    }
                default:
                    await MainActor.run {
                        self.isExporting = false
                        completion(false, "Unknown export error")
                    }
                }

            } catch {
                await MainActor.run {
                    self.isExporting = false
                    completion(false, error.localizedDescription)
                }
            }
        }
    }

    private func transcribeAudio(from videoURL: URL) async -> [TimedCaption] {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            return []
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                guard status == .authorized else {
                    continuation.resume(returning: [])
                    return
                }

                let request = SFSpeechURLRecognitionRequest(url: videoURL)
                request.shouldReportPartialResults = false

                recognizer.recognitionTask(with: request) { result, error in
                    guard let result = result, result.isFinal else {
                        if error != nil {
                            continuation.resume(returning: [])
                        }
                        return
                    }

                    var captions: [TimedCaption] = []
                    var currentWords: [String] = []
                    var segmentStart: CMTime?

                    for segment in result.bestTranscription.segments {
                        if segmentStart == nil {
                            segmentStart = CMTime(seconds: segment.timestamp, preferredTimescale: 600)
                        }

                        currentWords.append(segment.substring)

                        // Create caption every ~5 words or at natural pauses
                        if currentWords.count >= 5 {
                            let endTime = CMTime(seconds: segment.timestamp + segment.duration, preferredTimescale: 600)
                            let caption = TimedCaption(
                                text: currentWords.joined(separator: " "),
                                startTime: segmentStart!,
                                endTime: endTime
                            )
                            captions.append(caption)
                            currentWords = []
                            segmentStart = nil
                        }
                    }

                    // Add remaining words
                    if !currentWords.isEmpty, let start = segmentStart {
                        let lastSegment = result.bestTranscription.segments.last!
                        let endTime = CMTime(seconds: lastSegment.timestamp + lastSegment.duration, preferredTimescale: 600)
                        let caption = TimedCaption(
                            text: currentWords.joined(separator: " "),
                            startTime: start,
                            endTime: endTime
                        )
                        captions.append(caption)
                    }

                    continuation.resume(returning: captions)
                }
            }
        }
    }

    func loadPreviousRecordings() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!

            do {
                let files = try FileManager.default.contentsOfDirectory(
                    at: downloadsURL,
                    includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                    options: .skipsHiddenFiles
                )

                let videoFiles = files.filter { url in
                    let filename = url.lastPathComponent
                    let isMov = url.pathExtension.lowercased() == "mov"
                    let isQuickCam = filename.hasPrefix("QuickCam_") || filename.contains("QuickCam")
                    // Match date pattern like _2024-01-07 or _2025-12-31
                    let hasDatePattern = filename.range(of: "_\\d{4}-\\d{2}-\\d{2}", options: .regularExpression) != nil
                    return isMov && (isQuickCam || hasDatePattern)
                }

                var recordings: [RecordedVideo] = []

                for url in videoFiles {
                    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                    let date = (attributes?[.modificationDate] as? Date) ?? Date()

                    // Extract title from filename
                    var title = url.deletingPathExtension().lastPathComponent
                    // Remove date suffix if present
                    if let range = title.range(of: "_\\d{4}-\\d{2}-\\d{2}_\\d{2}-\\d{2}-\\d{2}$", options: .regularExpression) {
                        title = String(title[..<range.lowerBound])
                    }
                    if title == "QuickCam" {
                        title = "Untitled"
                    }

                    // Generate thumbnail
                    let thumbnail = self?.generateThumbnail(for: url)

                    recordings.append(RecordedVideo(
                        url: url,
                        thumbnail: thumbnail,
                        date: date,
                        title: title
                    ))
                }

                // Sort by date, newest first
                recordings.sort { $0.date > $1.date }

                DispatchQueue.main.async {
                    self?.previousRecordings = recordings
                }
            } catch {
                // Silently fail - no previous recordings
            }
        }
    }

    private func generateThumbnail(for url: URL) -> NSImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 200, height: 200)

        do {
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            return nil
        }
    }

    func deleteRecording(_ video: RecordedVideo) {
        try? FileManager.default.removeItem(at: video.url)
        previousRecordings.removeAll { $0.url == video.url }
    }

    func discardRecording() {
        guard let url = recordedVideoURL else { return }
        try? FileManager.default.removeItem(at: url)
        recordedVideoURL = nil
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
            if let error = error {
                self.error = error.localizedDescription
            } else {
                self.recordedVideoURL = outputFileURL
            }
        }
    }
}
