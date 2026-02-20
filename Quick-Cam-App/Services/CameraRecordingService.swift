import AVFoundation
import CoreMedia

class CameraRecordingService {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var isWriting = false
    private var sessionStarted = false
    private var didLogFailure = false
    var isPaused = false
    private(set) var outputURL: URL?

    /// Set to true when recording should start; the writer is initialized
    /// lazily from the first video frame's actual dimensions.
    private var pendingStart = false

    /// Audio samples that arrive before the first video frame initializes
    /// the writer. Flushed once the session starts to keep A/V in sync.
    private var pendingAudioBuffers: [CMSampleBuffer] = []

    private let writerQueue = DispatchQueue(label: "camera.recording.writer")

    /// Signals that recording should begin. The AVAssetWriter is created
    /// lazily when the first video frame arrives (so we use the real dimensions).
    func startRecording() {
        writerQueue.async { [weak self] in
            guard let self = self else { return }
            self.pendingStart = true
            self.isPaused = false
            self.sessionStarted = false
            self.didLogFailure = false
            self.isWriting = false
            self.assetWriter = nil
            self.videoInput = nil
            self.audioInput = nil
            self.outputURL = nil
            self.pendingAudioBuffers = []
        }
    }

    /// Called on writerQueue only. Creates the AVAssetWriter with the actual
    /// frame dimensions and audio format detected from buffered samples.
    private func initializeWriter(width: Int, height: Int) throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "QuickCam_Camera_\(Date().timeIntervalSince1970).mov"
        let fileURL = tempDir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)

        let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ]

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true

        // Detect actual audio format from buffered samples to avoid sample rate mismatch
        var sampleRate: Double = 48000
        var channelCount: UInt32 = 1
        if let firstAudio = pendingAudioBuffers.first,
           let formatDesc = CMSampleBufferGetFormatDescription(firstAudio),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee {
            sampleRate = asbd.mSampleRate
            channelCount = asbd.mChannelsPerFrame
            print("[DEBUG-WRITER] Detected audio format: \(sampleRate) Hz, \(channelCount) ch")
        }

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: 128_000
        ]
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        aInput.expectsMediaDataInRealTime = true

        if writer.canAdd(vInput) {
            writer.add(vInput)
        }
        if writer.canAdd(aInput) {
            writer.add(aInput)
        }

        self.assetWriter = writer
        self.videoInput = vInput
        self.audioInput = aInput
        self.outputURL = fileURL
        self.sessionStarted = false

        guard writer.startWriting() else {
            print("[DEBUG-WRITER] startWriting() failed: \(writer.error?.localizedDescription ?? "unknown")")
            throw writer.error ?? NSError(domain: "CameraRecordingService", code: -1)
        }

        isWriting = true
        pendingStart = false
        print("[DEBUG-WRITER] Writer initialized: \(width)x\(height), audio=\(sampleRate)Hz/\(channelCount)ch, status=\(writer.status.rawValue)")
    }

    func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            guard let self = self else { return }

            // Auto-initialize writer from the first frame's actual dimensions
            if self.pendingStart && !self.isWriting {
                guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
                let dims = CMVideoFormatDescriptionGetDimensions(formatDesc)
                do {
                    try self.initializeWriter(width: Int(dims.width), height: Int(dims.height))
                } catch {
                    print("[DEBUG-WRITER] Failed to initialize writer: \(error)")
                    self.pendingStart = false
                    self.pendingAudioBuffers = []
                    return
                }
            }

            guard self.isWriting,
                  !self.isPaused,
                  let writer = self.assetWriter,
                  let input = self.videoInput,
                  writer.status == .writing else {
                if let writer = self.assetWriter, writer.status == .failed, !self.didLogFailure {
                    self.didLogFailure = true
                    print("[DEBUG-WRITER] Writer failed: \(writer.error?.localizedDescription ?? "unknown")")
                }
                return
            }

            if !self.sessionStarted {
                let videoPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                // Use the earliest timestamp between buffered audio and this video frame
                // so that no samples are trimmed by the writer.
                var sessionStart = videoPTS
                if let firstAudio = self.pendingAudioBuffers.first {
                    let audioPTS = CMSampleBufferGetPresentationTimeStamp(firstAudio)
                    if CMTimeCompare(audioPTS, sessionStart) < 0 {
                        sessionStart = audioPTS
                    }
                }

                writer.startSession(atSourceTime: sessionStart)
                self.sessionStarted = true
                print("[DEBUG-WRITER] Session started at \(CMTimeGetSeconds(sessionStart))s (video PTS=\(CMTimeGetSeconds(videoPTS))s, buffered audio=\(self.pendingAudioBuffers.count))")

                // Flush buffered audio
                if let audioInput = self.audioInput {
                    for buffered in self.pendingAudioBuffers {
                        if audioInput.isReadyForMoreMediaData {
                            audioInput.append(buffered)
                        }
                    }
                }
                self.pendingAudioBuffers = []
            }

            if input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
        }
    }

    func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            guard let self = self else { return }

            // Buffer audio while waiting for the first video frame to initialize the writer
            if self.pendingStart || (self.isWriting && !self.sessionStarted) {
                self.pendingAudioBuffers.append(sampleBuffer)
                return
            }

            guard self.isWriting,
                  !self.isPaused,
                  self.sessionStarted,
                  let writer = self.assetWriter,
                  let input = self.audioInput,
                  writer.status == .writing else { return }

            if input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
        }
    }

    func stopRecording() async -> URL? {
        guard pendingStart || isWriting else { return nil }

        return await withCheckedContinuation { continuation in
            writerQueue.async {
                self.pendingAudioBuffers = []

                guard self.isWriting, let writer = self.assetWriter else {
                    self.pendingStart = false
                    continuation.resume(returning: nil)
                    return
                }
                self.isWriting = false
                self.pendingStart = false

                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()
                writer.finishWriting {
                    if writer.status == .completed {
                        print("[DEBUG-WRITER] Writer finished successfully: \(self.outputURL?.lastPathComponent ?? "nil")")
                        continuation.resume(returning: self.outputURL)
                    } else {
                        print("[DEBUG-WRITER] Writer finished with status=\(writer.status.rawValue), error=\(writer.error?.localizedDescription ?? "none")")
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}
