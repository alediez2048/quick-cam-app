import AVFoundation
import AppKit
import Accelerate

protocol CameraServiceProtocol: AnyObject {
    var availableCameras: [AVCaptureDevice] { get }
    var selectedCamera: AVCaptureDevice? { get }
    var isSessionRunning: Bool { get }
    var isAuthorized: Bool { get }
    var isReady: Bool { get }
    var isRecording: Bool { get set }
    var recordedVideoURL: URL? { get set }
    var error: String? { get set }
    var session: AVCaptureSession { get }

    func checkAuthorization()
    func setupAndStartSession()
    func stopSession()
    func switchCamera(to camera: AVCaptureDevice)
    func startRecording()
    func stopRecording()

    var audioLevel: Float { get }
}

class CameraService: NSObject, ObservableObject, CameraServiceProtocol {
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCamera: AVCaptureDevice?
    @Published var isSessionRunning = false
    @Published var isAuthorized = false
    @Published var isReady = false
    @Published var isRecording = false
    @Published var recordedVideoURL: URL?
    @Published var error: String?
    @Published var audioLevel: Float = -160.0

    private let captureSession = AVCaptureSession()
    private var movieOutput = AVCaptureMovieFileOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private var currentInput: AVCaptureDeviceInput?
    let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let audioMeteringQueue = DispatchQueue(label: "camera.audio.metering")
    private var isConfiguring = false
    private var lastAudioLevelUpdate = Date.distantPast

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

        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }

        captureSession.sessionPreset = .high

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

        if captureSession.canSetSessionPreset(.hd4K3840x2160) {
            captureSession.sessionPreset = .hd4K3840x2160
        } else if captureSession.canSetSessionPreset(.hd1920x1080) {
            captureSession.sessionPreset = .hd1920x1080
        }

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

        if captureSession.canAddOutput(audioDataOutput) {
            captureSession.addOutput(audioDataOutput)
            audioDataOutput.setSampleBufferDelegate(self, queue: audioMeteringQueue)
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
        DispatchQueue.main.async {
            self.selectedCamera = camera
            self.isReady = false
        }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            let wasRunning = self.captureSession.isRunning
            if wasRunning {
                self.captureSession.stopRunning()
            }

            self.configureSession()

            if wasRunning {
                self.startRunning()
            }
        }
    }

    func startRecording() {
        guard !isRecording else { return }
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

            guard self.movieOutput.connection(with: .video) != nil else {
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.error = "Video connection not available"
                }
                return
            }

            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "QuickCam_\(Date().timeIntervalSince1970).mov"
            let fileURL = tempDir.appendingPathComponent(fileName)

            try? FileManager.default.removeItem(at: fileURL)

            self.movieOutput.startRecording(to: fileURL, recordingDelegate: self)
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        sessionQueue.async { [weak self] in
            self?.movieOutput.stopRecording()
        }
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel = -160.0
            if let error = error {
                self.error = error.localizedDescription
            } else {
                self.recordedVideoURL = outputFileURL
            }
        }
    }
}

extension CameraService: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isRecording else { return }

        // Throttle updates to ~15-20 per second (~60ms interval)
        let now = Date()
        guard now.timeIntervalSince(lastAudioLevelUpdate) >= 0.06 else { return }
        lastAudioLevelUpdate = now

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        let length = CMBlockBufferGetDataLength(blockBuffer)
        var data = Data(count: length)
        data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
        }

        let format = CMSampleBufferGetFormatDescription(sampleBuffer)
        guard let asbd = format.flatMap({ CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }) else { return }

        let sampleCount: Int
        if asbd.mBitsPerChannel == 16 {
            sampleCount = length / MemoryLayout<Int16>.size
            guard sampleCount > 0 else { return }
            let rms: Float = data.withUnsafeBytes { rawBuffer in
                let samples = rawBuffer.bindMemory(to: Int16.self)
                var sumSquares: Float = 0
                for i in 0..<sampleCount {
                    let sample = Float(samples[i]) / Float(Int16.max)
                    sumSquares += sample * sample
                }
                return sqrt(sumSquares / Float(sampleCount))
            }
            let dbLevel = rms > 0 ? 20 * log10(rms) : -160.0
            let clamped = min(max(dbLevel, -160.0), 0.0)
            DispatchQueue.main.async {
                self.audioLevel = clamped
            }
        } else if asbd.mBitsPerChannel == 32 {
            sampleCount = length / MemoryLayout<Float>.size
            guard sampleCount > 0 else { return }
            let rms: Float = data.withUnsafeBytes { rawBuffer in
                let samples = rawBuffer.bindMemory(to: Float.self)
                var sumSquares: Float = 0
                for i in 0..<sampleCount {
                    sumSquares += samples[i] * samples[i]
                }
                return sqrt(sumSquares / Float(sampleCount))
            }
            let dbLevel = rms > 0 ? 20 * log10(rms) : -160.0
            let clamped = min(max(dbLevel, -160.0), 0.0)
            DispatchQueue.main.async {
                self.audioLevel = clamped
            }
        }
    }
}
