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

    let cameraService: any CameraServiceProtocol
    private let exportService = ExportService()
    private let transcriptionService = TranscriptionService()
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
        self.cameraService = cameraService
        if let observableService = cameraService as? CameraService {
            bindCameraService(observableService)
        }
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

        service.$audioLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$audioLevel)
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

    func exportToDownloads(title: String, enableCaptions: Bool = false, completion: @escaping (Bool, String?) -> Void) {
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

            exportService.exportToDownloads(sourceURL: sourceURL, title: title, captions: captions) { [weak self] success, path in
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
