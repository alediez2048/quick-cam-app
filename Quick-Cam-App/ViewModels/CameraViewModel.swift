import AVFoundation
import Combine

class CameraViewModel: ObservableObject {
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
    @Published var isCountingDown = false
    @Published var countdownValue = 0
    @Published var audioLevel: Float = -160.0
    @Published var isPaused = false
    @Published var isProcessingAudio = false
    @Published var selectedAspectRatio: AspectRatioOption = .vertical
    @Published var selectedResolution: ResolutionOption
    @Published var isMirrored: Bool
    @Published var isGridVisible: Bool
    @Published var previewPlayerItem: AVPlayerItem?
    @Published var isGeneratingPreview = false

    // Screen recording state
    @Published var recordingMode: RecordingMode = .cameraOnly
    @Published var selectedLayout: ScreenCameraLayout = .circleBubble
    @Published var bubblePosition: CameraBubblePosition = .bottomRight
    @Published var screenCaptureAuthorized = false
    @Published var screenFrame: CGImage?
    @Published var screenRecordedVideoURL: URL?

    let cameraService: any CameraServiceProtocol
    private let exportService = ExportService()
    private let transcriptionService = TranscriptionService()
    private let audioProcessingService = AudioProcessingService()
    private let recordingsRepository = RecordingsRepository()
    private var cancellables = Set<AnyCancellable>()
    private var countdownTimer: Timer?

    private var cachedProcessedAudioURL: URL?
    private var cachedAudioSourceURL: URL?

    var session: AVCaptureSession {
        cameraService.session
    }

    convenience init() {
        self.init(cameraService: CameraService())
    }

    init(cameraService: any CameraServiceProtocol) {
        let savedRawValue = UserDefaults.standard.string(forKey: "selectedResolution") ?? ResolutionOption.hd1080p.rawValue
        let savedResolution = ResolutionOption(rawValue: savedRawValue) ?? .hd1080p
        self.selectedResolution = savedResolution
        self.isMirrored = UserDefaults.standard.bool(forKey: "isMirrored")
        self.isGridVisible = UserDefaults.standard.bool(forKey: "isGridVisible")

        if let savedMode = UserDefaults.standard.string(forKey: "recordingMode"),
           let mode = RecordingMode(rawValue: savedMode) {
            self.recordingMode = mode
        }
        if let savedLayout = UserDefaults.standard.string(forKey: "screenCameraLayout"),
           let layout = ScreenCameraLayout(rawValue: savedLayout) {
            self.selectedLayout = layout
        }
        if let savedPos = UserDefaults.standard.string(forKey: "bubblePosition"),
           let pos = CameraBubblePosition(rawValue: savedPos) {
            self.bubblePosition = pos
        }

        self.cameraService = cameraService
        cameraService.selectedResolution = savedResolution

        if let observableService = cameraService as? CameraService {
            bindCameraService(observableService)
        }

        $selectedResolution
            .dropFirst()
            .sink { [weak self] resolution in
                guard let self = self else { return }
                UserDefaults.standard.set(resolution.rawValue, forKey: "selectedResolution")
                self.cameraService.selectedResolution = resolution
                self.cameraService.setupAndStartSession()
            }
            .store(in: &cancellables)

        $isMirrored
            .dropFirst()
            .sink { mirrored in
                UserDefaults.standard.set(mirrored, forKey: "isMirrored")
            }
            .store(in: &cancellables)

        $isGridVisible
            .dropFirst()
            .sink { visible in
                UserDefaults.standard.set(visible, forKey: "isGridVisible")
            }
            .store(in: &cancellables)

        $recordingMode
            .dropFirst()
            .sink { [weak self] mode in
                UserDefaults.standard.set(mode.rawValue, forKey: "recordingMode")
                self?.error = nil
                self?.cameraService.error = nil
            }
            .store(in: &cancellables)

        $selectedLayout
            .dropFirst()
            .sink { layout in
                UserDefaults.standard.set(layout.rawValue, forKey: "screenCameraLayout")
            }
            .store(in: &cancellables)

        $bubblePosition
            .dropFirst()
            .sink { pos in
                UserDefaults.standard.set(pos.rawValue, forKey: "bubblePosition")
            }
            .store(in: &cancellables)
    }

    private func bindCameraService(_ service: CameraService) {
        service.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)

        service.$recordedVideoURL
            .receive(on: DispatchQueue.main)
            .assign(to: &$recordedVideoURL)

        service.$availableCameras
            .receive(on: DispatchQueue.main)
            .assign(to: &$availableCameras)

        service.$selectedCamera
            .receive(on: DispatchQueue.main)
            .assign(to: &$selectedCamera)

        service.$error
            .receive(on: DispatchQueue.main)
            .assign(to: &$error)

        service.$isSessionRunning
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSessionRunning)

        service.$isAuthorized
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAuthorized)

        service.$isReady
            .receive(on: DispatchQueue.main)
            .assign(to: &$isReady)

        service.$isPaused
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPaused)

        service.$audioLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$audioLevel)

        service.$selectedResolution
            .receive(on: DispatchQueue.main)
            .sink { [weak self] resolution in
                guard let self = self, self.selectedResolution != resolution else { return }
                self.selectedResolution = resolution
                UserDefaults.standard.set(resolution.rawValue, forKey: "selectedResolution")
            }
            .store(in: &cancellables)

        service.$screenRecordedVideoURL
            .receive(on: DispatchQueue.main)
            .assign(to: &$screenRecordedVideoURL)

        service.screenCaptureService.$isAuthorized
            .receive(on: DispatchQueue.main)
            .assign(to: &$screenCaptureAuthorized)

        service.screenCaptureService.$latestFrame
            .receive(on: DispatchQueue.main)
            .assign(to: &$screenFrame)
    }

    func checkAuthorization() {
        cameraService.checkAuthorization()
    }

    func checkScreenCaptureAuthorization() {
        if let service = cameraService as? CameraService {
            service.screenCaptureService.checkAuthorization()
        }
    }

    func requestScreenCaptureAuthorization() {
        if let service = cameraService as? CameraService {
            service.screenCaptureService.requestAuthorization()
        }
    }

    func setupAndStartSession() {
        cameraService.setupAndStartSession()
    }

    func stopSession() {
        cameraService.stopSession()
    }

    func switchCamera(to camera: AVCaptureDevice) {
        cameraService.switchCamera(to: camera)
    }

    func startRecording() {
        guard !isCountingDown && !isRecording else { return }
        // Clear any previous error before starting
        error = nil
        cameraService.error = nil
        cameraService.recordingMode = recordingMode

        // For screen capture modes, show the picker first, then start countdown
        if recordingMode.needsScreenCapture {
            Task {
                do {
                    if let service = cameraService as? CameraService {
                        let filter = try await service.screenCaptureService.presentPicker()
                        service.pendingScreenFilter = filter

                        // The picker may have interrupted the camera session.
                        // Restart it so movieOutput is ready when recording starts.
                        if self.recordingMode.needsCamera {
                            service.setupAndStartSession()
                        }
                    }
                    await MainActor.run {
                        self.isCountingDown = true
                        self.countdownValue = 3
                        self.performCountdown()
                    }
                } catch ScreenCaptureService.ScreenCaptureError.pickerCancelled {
                    // User cancelled the picker, don't start recording
                } catch {
                    await MainActor.run {
                        self.error = "Screen capture failed: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            isCountingDown = true
            countdownValue = 3
            performCountdown()
        }
    }

    func stopRecording() {
        print("[DEBUG-VM] stopRecording() called. isCountingDown=\(isCountingDown), isRecording=\(isRecording)")
        if isCountingDown {
            print("[DEBUG-VM] isCountingDown=true, calling cancelCountdown() and returning early")
            cancelCountdown()
            return
        }
        print("[DEBUG-VM] Forwarding to cameraService.stopRecording()")
        cameraService.stopRecording()
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        cameraService.pauseRecording()
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        cameraService.resumeRecording()
    }

    func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        isCountingDown = false
        countdownValue = 0
    }

    private func performCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            self.countdownValue -= 1
            if self.countdownValue <= 0 {
                timer.invalidate()
                self.countdownTimer = nil
                self.isCountingDown = false
                self.cameraService.startRecording()
            }
        }
    }

    func generatePreview(
        enableCaptions: Bool,
        enhanceAudio: Bool,
        aspectRatio: AspectRatioOption,
        captionStyle: CaptionStyle,
        language: TranscriptionLanguage,
        preTranscribedCaptions: [TimedCaption],
        exclusionRanges: [CMTimeRange]
    ) {
        guard let sourceURL = recordedVideoURL else { return }

        isGeneratingPreview = true

        Task {
            var captions: [TimedCaption] = []
            if enableCaptions {
                if !preTranscribedCaptions.isEmpty {
                    captions = preTranscribedCaptions
                } else {
                    await MainActor.run {
                        self.isTranscribing = true
                        self.transcriptionProgress = "Transcribing audio..."
                    }
                    captions = (try? await transcriptionService.transcribeAudio(from: sourceURL, locale: language.locale)) ?? []
                    await MainActor.run {
                        self.isTranscribing = false
                        self.transcriptionProgress = ""
                    }
                }
            }

            var processedAudioURL: URL? = nil
            if enhanceAudio {
                if let cached = cachedProcessedAudioURL, cachedAudioSourceURL == sourceURL {
                    processedAudioURL = cached
                } else {
                    await MainActor.run {
                        self.isProcessingAudio = true
                    }
                    do {
                        processedAudioURL = try await audioProcessingService.process(inputURL: sourceURL)
                        cachedProcessedAudioURL = processedAudioURL
                        cachedAudioSourceURL = sourceURL
                    } catch {
                        print("Audio processing failed, falling back to original audio: \(error)")
                    }
                    await MainActor.run {
                        self.isProcessingAudio = false
                    }
                }
            }

            do {
                if recordingMode == .screenAndCamera, let screenURL = screenRecordedVideoURL {
                    let playerItem = try await exportService.buildScreenCameraPreviewPlayerItem(
                        screenURL: screenURL,
                        cameraURL: sourceURL,
                        layout: selectedLayout,
                        bubblePosition: bubblePosition,
                        captions: captions,
                        processedAudioURL: processedAudioURL,
                        captionStyle: captionStyle,
                        exclusionRanges: exclusionRanges
                    )
                    await MainActor.run {
                        self.previewPlayerItem = playerItem
                        self.isGeneratingPreview = false
                    }
                } else {
                    let playerItem = try await exportService.buildPreviewPlayerItem(
                        sourceURL: sourceURL,
                        captions: captions,
                        processedAudioURL: processedAudioURL,
                        aspectRatio: aspectRatio,
                        captionStyle: captionStyle,
                        exclusionRanges: exclusionRanges
                    )
                    await MainActor.run {
                        self.previewPlayerItem = playerItem
                        self.isGeneratingPreview = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isGeneratingPreview = false
                }
            }
        }
    }

    func exportToDownloads(title: String, enableCaptions: Bool = false, enhanceAudio: Bool = false, aspectRatio: AspectRatioOption = .vertical, captionStyle: CaptionStyle = .classic, language: TranscriptionLanguage = .english, preTranscribedCaptions: [TimedCaption] = [], exclusionRanges: [CMTimeRange] = [], completion: @escaping (Bool, String?) -> Void) {
        guard let sourceURL = recordedVideoURL else {
            completion(false, "No video to export")
            return
        }

        isExporting = true

        Task {
            var captions: [TimedCaption] = []
            if enableCaptions {
                if !preTranscribedCaptions.isEmpty {
                    captions = preTranscribedCaptions
                } else {
                    await MainActor.run {
                        self.isTranscribing = true
                        self.transcriptionProgress = "Transcribing audio..."
                    }
                    captions = (try? await transcriptionService.transcribeAudio(from: sourceURL, locale: language.locale)) ?? []
                    await MainActor.run {
                        self.isTranscribing = false
                        self.transcriptionProgress = ""
                    }
                }
            }

            var processedAudioURL: URL? = nil
            if enhanceAudio {
                if let cached = cachedProcessedAudioURL, cachedAudioSourceURL == sourceURL {
                    processedAudioURL = cached
                } else {
                    await MainActor.run {
                        self.isProcessingAudio = true
                    }
                    do {
                        processedAudioURL = try await audioProcessingService.process(inputURL: sourceURL)
                        cachedProcessedAudioURL = processedAudioURL
                        cachedAudioSourceURL = sourceURL
                    } catch {
                        print("Audio processing failed, falling back to original audio: \(error)")
                    }
                    await MainActor.run {
                        self.isProcessingAudio = false
                    }
                }
            }

            if recordingMode == .screenAndCamera, let screenURL = screenRecordedVideoURL {
                exportService.exportScreenCameraComposition(
                    screenURL: screenURL,
                    cameraURL: sourceURL,
                    layout: selectedLayout,
                    bubblePosition: bubblePosition,
                    captions: captions,
                    captionStyle: captionStyle,
                    processedAudioURL: processedAudioURL,
                    exclusionRanges: exclusionRanges,
                    title: title
                ) { [weak self] success, path in
                    guard let self = self else { return }
                    self.isExporting = false
                    if success {
                        self.loadPreviousRecordings()
                    } else {
                        self.error = path ?? "Export failed"
                    }
                    completion(success, path)
                }
            } else {
                exportService.exportToDownloads(sourceURL: sourceURL, title: title, captions: captions, processedAudioURL: processedAudioURL, aspectRatio: aspectRatio, captionStyle: captionStyle, exclusionRanges: exclusionRanges) { [weak self] success, path in
                    guard let self = self else { return }
                    self.isExporting = false
                    if success {
                        self.loadPreviousRecordings()
                    } else {
                        self.error = path ?? "Export failed"
                    }
                    completion(success, path)
                }
            }
        }
    }

    func loadPreviousRecordings() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let recordings = self.recordingsRepository.loadPreviousRecordings()
            DispatchQueue.main.async {
                self.previousRecordings = recordings
            }
        }
    }

    func deleteRecording(_ video: RecordedVideo) {
        recordingsRepository.deleteRecording(video)
        previousRecordings.removeAll { $0.url == video.url }
    }

    func discardRecording() {
        guard let url = recordedVideoURL else { return }
        recordingsRepository.discardRecording(at: url)
        recordedVideoURL = nil
        cachedProcessedAudioURL = nil
        cachedAudioSourceURL = nil
        // Clean up screen recording temp file
        if let screenURL = screenRecordedVideoURL {
            try? FileManager.default.removeItem(at: screenURL)
            screenRecordedVideoURL = nil
        }
    }
}
