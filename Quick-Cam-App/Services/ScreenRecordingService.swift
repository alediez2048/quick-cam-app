import AVFoundation
import CoreMedia

class ScreenRecordingService {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var isWriting = false
    private var sessionStarted = false
    private(set) var outputURL: URL?

    private let writerQueue = DispatchQueue(label: "screen.recording.writer")

    func startRecording() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "QuickCam_Screen_\(Date().timeIntervalSince1970).mov"
        let fileURL = tempDir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)

        let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1920,
            AVVideoHeightKey: 1080,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )

        if writer.canAdd(input) {
            writer.add(input)
        }

        self.assetWriter = writer
        self.videoInput = input
        self.pixelBufferAdaptor = adaptor
        self.outputURL = fileURL
        self.sessionStarted = false

        writer.startWriting()

        isWriting = true
        return fileURL
    }

    func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            guard let self = self,
                  self.isWriting,
                  let writer = self.assetWriter,
                  let input = self.videoInput,
                  writer.status == .writing else { return }

            if !self.sessionStarted {
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                writer.startSession(atSourceTime: timestamp)
                self.sessionStarted = true
            }

            if input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
        }
    }

    func stopRecording() async -> URL? {
        guard isWriting, let writer = assetWriter else { return nil }
        isWriting = false

        return await withCheckedContinuation { continuation in
            writerQueue.async {
                self.videoInput?.markAsFinished()
                writer.finishWriting {
                    continuation.resume(returning: writer.status == .completed ? self.outputURL : nil)
                }
            }
        }
    }

    func discardRecording() {
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        outputURL = nil
        assetWriter = nil
        videoInput = nil
        pixelBufferAdaptor = nil
        isWriting = false
        sessionStarted = false
    }
}
