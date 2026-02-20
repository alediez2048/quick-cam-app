import AVFoundation
import AppKit
import Accelerate
import ScreenCaptureKit

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

    var sessionQueue: DispatchQueue { get }

    func checkAuthorization()
    func setupAndStartSession()
    func stopSession()
    func switchCamera(to camera: AVCaptureDevice)
    func startRecording()
    func stopRecording()

    var isPaused: Bool { get set }
    var audioLevel: Float { get }

    var selectedResolution: ResolutionOption { get set }
    var recordingMode: RecordingMode { get set }
    var screenRecordedVideoURL: URL? { get set }

    func pauseRecording()
    func resumeRecording()
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
    @Published var isPaused = false
    @Published var audioLevel: Float = -160.0
    @Published var selectedResolution: ResolutionOption = .hd1080p
    @Published var recordingMode: RecordingMode = .cameraOnly
    @Published var screenRecordedVideoURL: URL?

    private let captureSession = AVCaptureSession()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var currentInput: AVCaptureDeviceInput?
    let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let audioMeteringQueue = DispatchQueue(label: "camera.audio.metering")
    private let videoDataQueue = DispatchQueue(label: "camera.video.data")
    private var isConfiguring = false
    private var lastAudioLevelUpdate = Date.distantPast

    let screenCaptureService = ScreenCaptureService()
    private let screenRecordingService = ScreenRecordingService()
    private let cameraRecordingService = CameraRecordingService()
    var pendingScreenFilter: SCContentFilter?

    var session: AVCaptureSession {
        captureSession
    }

    override init() {
        super.init()
        discoverCameras()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceConnected),
            name: AVCaptureDevice.wasConnectedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceDisconnected),
            name: AVCaptureDevice.wasDisconnectedNotification,
            object: nil
        )
    }

    @objc private func deviceConnected(_ notification: Notification) {
        DispatchQueue.main.async {
            self.discoverCameras()
        }
    }

    @objc private func deviceDisconnected(_ notification: Notification) {
        let disconnected = notification.object as? AVCaptureDevice
        DispatchQueue.main.async {
            self.discoverCameras()
            if let disconnected, self.selectedCamera?.uniqueID == disconnected.uniqueID {
                self.selectedCamera = self.availableCameras.first
                self.setupAndStartSession()
            }
        }
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

        let fallbackOrder: [ResolutionOption]
        switch selectedResolution {
        case .uhd4K:
            fallbackOrder = [.uhd4K, .hd1080p, .hd720p]
        case .hd1080p:
            fallbackOrder = [.hd1080p, .hd720p]
        case .hd720p:
            fallbackOrder = [.hd720p]
        }

        var didSet = false
        for option in fallbackOrder {
            if captureSession.canSetSessionPreset(option.sessionPreset) {
                captureSession.sessionPreset = option.sessionPreset
                let actualResolution = option
                if actualResolution != selectedResolution {
                    DispatchQueue.main.async {
                        self.selectedResolution = actualResolution
                    }
                }
                didSet = true
                break
            }
        }
        if !didSet {
            captureSession.sessionPreset = .high
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

        // Use the camera's native pixel format (420v YCbCr) — avoids double
        // conversion (native→BGRA→YUV) that adds latency and drops frames.
        videoDataOutput.videoSettings = [:]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataQueue)
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

        let mode = recordingMode
        let filter = pendingScreenFilter
        pendingScreenFilter = nil

        if mode == .screenOnly {
            // Screen-only: just start screen capture
            guard let filter = filter else {
                DispatchQueue.main.async {
                    self.error = "No screen content selected"
                    self.isRecording = false
                }
                return
            }
            Task {
                do {
                    try await screenCaptureService.startCapture(filter: filter)
                    let _ = try screenRecordingService.startRecording()
                    screenCaptureService.sampleBufferHandler = { [weak self] sampleBuffer in
                        self?.screenRecordingService.appendSampleBuffer(sampleBuffer)
                    }
                } catch {
                    await MainActor.run {
                        self.error = "Screen capture failed: \(error.localizedDescription)"
                        self.isRecording = false
                    }
                }
            }
        } else if mode == .screenAndCamera {
            // Screen + Camera: use AVAssetWriter for camera (bypasses movieOutput issues)
            guard let filter = filter else {
                DispatchQueue.main.async {
                    self.error = "No screen content selected"
                    self.isRecording = false
                }
                return
            }

            // Start camera recording (writer initializes lazily from first frame)
            cameraRecordingService.startRecording()
            print("[DEBUG-SVC] CameraRecordingService prepared (screenAndCamera)")

            // Start screen capture
            Task {
                do {
                    try await self.screenCaptureService.startCapture(filter: filter)
                    let _ = try self.screenRecordingService.startRecording()
                    self.screenCaptureService.sampleBufferHandler = { [weak self] sampleBuffer in
                        self?.screenRecordingService.appendSampleBuffer(sampleBuffer)
                    }
                    print("[DEBUG-SVC] Screen capture started")
                } catch {
                    await MainActor.run {
                        self.error = "Screen capture failed: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            // Camera-only mode — use AVAssetWriter (writer initializes lazily from first frame)
            cameraRecordingService.startRecording()
            print("[DEBUG-SVC] CameraRecordingService prepared (cameraOnly)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isPaused = false

        let mode = recordingMode

        if mode == .screenAndCamera {
            // Stop both screen and camera (AVAssetWriter-based)
            Task {
                let screenURL = await screenRecordingService.stopRecording()
                await screenCaptureService.stopCapture()
                let cameraURL = await cameraRecordingService.stopRecording()
                print("[DEBUG-SVC] stopRecording screenAndCamera: screenURL=\(screenURL?.lastPathComponent ?? "nil"), cameraURL=\(cameraURL?.lastPathComponent ?? "nil")")

                await MainActor.run {
                    self.screenRecordedVideoURL = screenURL
                    self.recordedVideoURL = cameraURL
                    self.isRecording = false
                    self.audioLevel = -160.0
                    if cameraURL == nil {
                        self.error = "Camera recording failed"
                    }
                    if screenURL == nil {
                        self.error = "Screen recording failed"
                    }
                }
            }
        } else if mode == .screenOnly {
            Task {
                let screenURL = await screenRecordingService.stopRecording()
                await screenCaptureService.stopCapture()

                await MainActor.run {
                    self.screenRecordedVideoURL = screenURL
                    self.isRecording = false
                    self.audioLevel = -160.0
                    if screenURL != nil {
                        self.recordedVideoURL = screenURL
                    } else {
                        self.error = "Screen recording failed"
                    }
                }
            }
        } else {
            // Camera only — uses CameraRecordingService
            Task {
                let cameraURL = await cameraRecordingService.stopRecording()
                await MainActor.run {
                    self.isRecording = false
                    self.isPaused = false
                    self.audioLevel = -160.0
                    if let url = cameraURL {
                        self.recordedVideoURL = url
                    } else {
                        self.error = "Camera recording failed"
                    }
                }
            }
        }
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        cameraRecordingService.isPaused = true
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        isPaused = false
        cameraRecordingService.isPaused = false
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === videoDataOutput {
            handleVideoOutput(sampleBuffer)
        } else {
            handleAudioOutput(sampleBuffer)
        }
    }

    private func handleVideoOutput(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, recordingMode != .screenOnly else { return }
        cameraRecordingService.appendVideoSampleBuffer(sampleBuffer)
    }

    private func handleAudioOutput(_ sampleBuffer: CMSampleBuffer) {
        // Forward audio to camera writer when recording with camera
        if isRecording, recordingMode != .screenOnly {
            cameraRecordingService.appendAudioSampleBuffer(sampleBuffer)
        }

        // Audio metering
        guard isRecording else { return }

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
