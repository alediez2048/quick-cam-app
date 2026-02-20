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
    private let movieFileOutput = AVCaptureMovieFileOutput()
    private var currentInput: AVCaptureDeviceInput?
    let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let audioMeteringQueue = DispatchQueue(label: "camera.audio.metering")
    private var isConfiguring = false
    private var lastAudioLevelUpdate = Date.distantPast

    /// Tracks whether handleCameraRecordingFinished has already been called
    /// to prevent double-handling if the delegate fires unexpectedly.
    private var didHandleCameraStop = false

    let screenCaptureService = ScreenCaptureService()
    private let screenRecordingService = ScreenRecordingService()
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted),
            name: .AVCaptureSessionWasInterrupted,
            object: captureSession
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError),
            name: .AVCaptureSessionRuntimeError,
            object: captureSession
        )
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        print("[DEBUG-SVC] ⚠️ Session interrupted! userInfo=\(notification.userInfo ?? [:])")
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
        print("[DEBUG-SVC] ⚠️ Session runtime error: \(error?.localizedDescription ?? "unknown")")
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
        print("[DEBUG-SVC] configureSession() called, isRecording=\(isRecording)")

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

        // Movie file output handles A/V sync automatically — replaces
        // the manual AVAssetWriter approach that had persistent desync.
        if captureSession.canAddOutput(movieFileOutput) {
            captureSession.addOutput(movieFileOutput)
        }

        // Audio data output stays for real-time metering only
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

    private func startCameraMovieRecording() {
        didHandleCameraStop = false

        // Must run on sessionQueue to avoid racing with configureSession()
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            let outputs = self.captureSession.outputs
            let running = self.captureSession.isRunning
            let hasMovieOutput = outputs.contains(self.movieFileOutput)

            print("[DEBUG-SVC] startCameraMovieRecording: session.isRunning=\(running), outputs=\(outputs.count), hasMovieOutput=\(hasMovieOutput)")

            guard hasMovieOutput else {
                print("[DEBUG-SVC] movieFileOutput not in session — cannot record")
                DispatchQueue.main.async {
                    self.error = "Camera recording not available"
                    self.isRecording = false
                }
                return
            }

            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "QuickCam_Camera_\(Date().timeIntervalSince1970).mov"
            let fileURL = tempDir.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)

            self.movieFileOutput.startRecording(to: fileURL, recordingDelegate: self)

            // Check if recording actually started
            let isNowRecording = self.movieFileOutput.isRecording
            print("[DEBUG-SVC] movieFileOutput.startRecording → \(fileName), isRecording=\(isNowRecording)")

            if !isNowRecording {
                print("[DEBUG-SVC] WARNING: movieFileOutput failed to start recording!")
                // Check connections
                for conn in self.movieFileOutput.connections {
                    print("[DEBUG-SVC]   connection: active=\(conn.isActive), enabled=\(conn.isEnabled)")
                }
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
            guard let filter = filter else {
                DispatchQueue.main.async {
                    self.error = "No screen content selected"
                    self.isRecording = false
                }
                return
            }

            // Start camera via movieFileOutput (handles A/V sync automatically)
            startCameraMovieRecording()

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
            // Camera-only mode — movieFileOutput handles A/V sync automatically
            startCameraMovieRecording()
        }
    }

    /// Called when the camera movie file output finishes (from delegate).
    /// Handles the result and triggers screen stop if in screenAndCamera mode.
    private func handleCameraRecordingFinished(url: URL?) {
        // Guard against being called twice (delegate + manual fallback)
        guard !didHandleCameraStop else {
            print("[DEBUG-SVC] handleCameraRecordingFinished already called — ignoring")
            return
        }
        didHandleCameraStop = true

        let mode = self.recordingMode

        if mode == .screenAndCamera {
            Task {
                let screenURL = await self.screenRecordingService.stopRecording()
                await self.screenCaptureService.stopCapture()
                print("[DEBUG-SVC] stopRecording screenAndCamera: screenURL=\(screenURL?.lastPathComponent ?? "nil"), cameraURL=\(url?.lastPathComponent ?? "nil")")

                await MainActor.run {
                    self.screenRecordedVideoURL = screenURL
                    self.recordedVideoURL = url
                    self.isRecording = false
                    self.audioLevel = -160.0
                    if url == nil {
                        self.error = "Camera recording failed"
                    }
                    if screenURL == nil {
                        self.error = "Screen recording failed"
                    }
                }
            }
        } else {
            // Camera-only
            DispatchQueue.main.async {
                self.isRecording = false
                self.isPaused = false
                self.audioLevel = -160.0
                if let url = url {
                    self.recordedVideoURL = url
                } else {
                    self.error = "Camera recording failed"
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isPaused = false

        let mode = recordingMode

        if mode == .screenOnly {
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
            // Camera-only or screenAndCamera — stop the movie output.
            // The delegate (fileOutput didFinishRecordingTo) calls
            // handleCameraRecordingFinished which drives the rest.
            print("[DEBUG-SVC] stopRecording: calling movieFileOutput.stopRecording() (isRecording=\(movieFileOutput.isRecording))")
            if movieFileOutput.isRecording {
                movieFileOutput.stopRecording()
                // delegate will call handleCameraRecordingFinished
            } else {
                // Not recording — delegate won't fire, handle directly
                print("[DEBUG-SVC] movieFileOutput not recording — handling directly")
                handleCameraRecordingFinished(url: nil)
            }
        }
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        if recordingMode != .screenOnly {
            movieFileOutput.pauseRecording()
        }
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        isPaused = false
        if recordingMode != .screenOnly {
            movieFileOutput.resumeRecording()
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate (movieFileOutput)

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        print("[DEBUG-SVC] movieFileOutput didStartRecording: \(fileURL.lastPathComponent)")
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        // AVCaptureMovieFileOutput reports a "successful stop" as an error with
        // AVErrorRecordingSuccessfullyFinishedKey = true. Check for that.
        var success = (error == nil)
        if let err = error as NSError? {
            if err.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true {
                success = true
            }
        }

        let url: URL? = success ? outputFileURL : nil
        print("[DEBUG-SVC] movieFileOutput delegate didFinish: success=\(success), url=\(url?.lastPathComponent ?? "nil"), error=\(error?.localizedDescription ?? "none")")

        // Always deliver via handleCameraRecordingFinished.
        // If stopRecording() already called movieFileOutput.stopRecording(), this
        // fires as expected. If it fired early (error during recording), we handle
        // it the same way — stop everything and update the UI.
        handleCameraRecordingFinished(url: url)
    }
}

// MARK: - Audio metering via AVCaptureAudioDataOutput

extension CameraService: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Audio metering only — recording is handled by movieFileOutput
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
