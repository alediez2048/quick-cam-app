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

    let cameraService: any CameraServiceProtocol
    private let exportService = ExportService()
    private let transcriptionService = TranscriptionService()
    private let audioProcessingService = AudioProcessingService()
    private let recordingsRepository = RecordingsRepository()
    private var cancellables = Set<AnyCancellable>()
    private var countdownTimer: Timer?

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
    }

    func checkAuthorization() {
        cameraService.checkAuthorization()
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
        isCountingDown = true
        countdownValue = 3
        performCountdown()
    }

    func stopRecording() {
        if isCountingDown {
            cancelCountdown()
            return
        }
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

    func exportToDownloads(title: String, enableCaptions: Bool = false, enhanceAudio: Bool = false, aspectRatio: AspectRatioOption = .vertical, captionStyle: CaptionStyle = .classic, completion: @escaping (Bool, String?) -> Void) {
        guard let sourceURL = recordedVideoURL else {
            completion(false, "No video to export")
            return
        }

        isExporting = true

        Task {
            var captions: [TimedCaption] = []
            if enableCaptions {
                await MainActor.run {
                    self.isTranscribing = true
                    self.transcriptionProgress = "Transcribing audio..."
                }
                captions = await transcriptionService.transcribeAudio(from: sourceURL)
                await MainActor.run {
                    self.isTranscribing = false
                    self.transcriptionProgress = ""
                }
            }

            var processedAudioURL: URL? = nil
            if enhanceAudio {
                await MainActor.run {
                    self.isProcessingAudio = true
                }
                do {
                    processedAudioURL = try await audioProcessingService.process(inputURL: sourceURL)
                } catch {
                    print("Audio processing failed, falling back to original audio: \(error)")
                }
                await MainActor.run {
                    self.isProcessingAudio = false
                }
            }

            exportService.exportToDownloads(sourceURL: sourceURL, title: title, captions: captions, processedAudioURL: processedAudioURL, aspectRatio: aspectRatio, captionStyle: captionStyle) { [weak self] success, path in
                guard let self = self else { return }
                self.isExporting = false
                if success {
                    self.loadPreviousRecordings()
                }
                completion(success, path)
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
    }
}
