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

    let cameraService = CameraService()
    private let exportService = ExportService()
    private let transcriptionService = TranscriptionService()
    private let recordingsRepository = RecordingsRepository()
    private var cancellables = Set<AnyCancellable>()

    var session: AVCaptureSession {
        cameraService.session
    }

    init() {
        bindCameraService()
    }

    private func bindCameraService() {
        cameraService.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)

        cameraService.$recordedVideoURL
            .receive(on: DispatchQueue.main)
            .assign(to: &$recordedVideoURL)

        cameraService.$availableCameras
            .receive(on: DispatchQueue.main)
            .assign(to: &$availableCameras)

        cameraService.$selectedCamera
            .receive(on: DispatchQueue.main)
            .assign(to: &$selectedCamera)

        cameraService.$error
            .receive(on: DispatchQueue.main)
            .assign(to: &$error)

        cameraService.$isSessionRunning
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSessionRunning)

        cameraService.$isAuthorized
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAuthorized)

        cameraService.$isReady
            .receive(on: DispatchQueue.main)
            .assign(to: &$isReady)
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
        cameraService.startRecording()
    }

    func stopRecording() {
        cameraService.stopRecording()
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
