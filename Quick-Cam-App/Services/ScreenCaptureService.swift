import ScreenCaptureKit
import CoreMedia
import AppKit

class ScreenCaptureService: NSObject, ObservableObject, SCContentSharingPickerObserver {
    @Published var isAuthorized = false
    @Published var isCapturing = false
    @Published var latestFrame: CGImage?
    @Published var error: String?
    @Published var hasContentFilter = false

    private var stream: SCStream?
    private var streamOutput: ScreenCaptureStreamOutput?
    private var contentFilter: SCContentFilter?
    var sampleBufferHandler: ((CMSampleBuffer) -> Void)?

    private let captureQueue = DispatchQueue(label: "screen.capture.queue")
    private var filterContinuation: CheckedContinuation<SCContentFilter, Error>?
    private var continuationConsumed = false

    override init() {
        super.init()
        let picker = SCContentSharingPicker.shared
        picker.add(self)
    }

    /// Presents the system screen sharing picker. Returns when the user selects content.
    func presentPicker() async throws -> SCContentFilter {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                self.continuationConsumed = false
                self.filterContinuation = continuation

                let picker = SCContentSharingPicker.shared
                picker.isActive = true
                picker.present()
            }
        }
    }

    /// Starts capturing using a previously obtained content filter.
    func startCapture(filter: SCContentFilter, frameRate: Int = 30) async throws {
        let config = SCStreamConfiguration()
        config.width = 1920
        config.height = 1080
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        let output = ScreenCaptureStreamOutput()
        output.onFrame = { [weak self] sampleBuffer, cgImage in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.latestFrame = cgImage
            }
            self.sampleBufferHandler?(sampleBuffer)
        }
        self.streamOutput = output

        let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
        try newStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: captureQueue)
        try await newStream.startCapture()

        self.stream = newStream
        self.contentFilter = filter

        await MainActor.run {
            self.isCapturing = true
            self.isAuthorized = true
            self.hasContentFilter = true
        }
    }

    func stopCapture() async {
        guard let stream = stream else { return }
        do {
            try await stream.stopCapture()
        } catch {
            // Stream may already be stopped
        }
        self.stream = nil
        self.streamOutput = nil
        await MainActor.run {
            self.isCapturing = false
            self.latestFrame = nil
        }
    }

    // MARK: - SCContentSharingPickerObserver

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        picker.isActive = false
        DispatchQueue.main.async {
            self.contentFilter = filter
            self.hasContentFilter = true
            self.isAuthorized = true
        }
        resumeContinuation(with: .success(filter))
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        picker.isActive = false
        resumeContinuation(with: .failure(ScreenCaptureError.pickerCancelled))
    }

    func contentSharingPickerDidCancel(_ picker: SCContentSharingPicker) {
        picker.isActive = false
        resumeContinuation(with: .failure(ScreenCaptureError.pickerCancelled))
    }

    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        SCContentSharingPicker.shared.isActive = false
        resumeContinuation(with: .failure(error))
    }

    // MARK: - Private

    /// Safely resume the continuation exactly once
    private func resumeContinuation(with result: Result<SCContentFilter, Error>) {
        guard !continuationConsumed, let continuation = filterContinuation else { return }
        continuationConsumed = true
        filterContinuation = nil
        continuation.resume(with: result)
    }

    // MARK: - Legacy

    func checkAuthorization() {
        let authorized = CGPreflightScreenCaptureAccess()
        DispatchQueue.main.async {
            self.isAuthorized = authorized
        }
    }

    func requestAuthorization() {
        CGRequestScreenCaptureAccess()
    }

    enum ScreenCaptureError: LocalizedError {
        case noDisplay
        case notAuthorized
        case pickerCancelled

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "No display found for screen capture"
            case .notAuthorized: return "Screen recording not authorized"
            case .pickerCancelled: return "Screen sharing was cancelled"
            }
        }
    }
}

private class ScreenCaptureStreamOutput: NSObject, SCStreamOutput {
    var onFrame: ((CMSampleBuffer, CGImage?) -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard sampleBuffer.isValid else { return }

        var cgImage: CGImage?
        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let ciImage = CIImage(cvImageBuffer: imageBuffer)
            let context = CIContext()
            cgImage = context.createCGImage(ciImage, from: ciImage.extent)
        }

        onFrame?(sampleBuffer, cgImage)
    }
}
