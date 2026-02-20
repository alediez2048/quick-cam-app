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

    private var pendingStart = false
    private var pendingAudioBuffers: [CMSampleBuffer] = []

    /// The absolute PTS of the first sample — subtracted from all subsequent
    /// timestamps so the output file starts at T=0.  This avoids precision
    /// issues with large absolute capture-clock values (700 000+ seconds).
    private var timebaseOffset: CMTime?

    /// Fixed delay added to audio PTS so audio doesn't play ahead of video.
    /// Tune this value if A/V sync is still off.
    private let audioSyncDelay = CMTime(seconds: 1.0, preferredTimescale: 600)

    private let writerQueue = DispatchQueue(label: "camera.recording.writer")

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
            self.timebaseOffset = nil
        }
    }

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

        // Detect actual audio format from buffered samples
        var sampleRate: Double = 48000
        var channelCount: UInt32 = 1
        if let firstAudio = pendingAudioBuffers.first,
           let formatDesc = CMSampleBufferGetFormatDescription(firstAudio),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee {
            sampleRate = asbd.mSampleRate
            channelCount = asbd.mChannelsPerFrame
        }

        // Use Apple Lossless for the temp recording — zero encoder delay,
        // so audio track duration matches video exactly. Gets re-encoded
        // to AAC during export. AAC's 2112-sample priming delay was causing
        // the audio track to be ~0.6s shorter than video.
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitDepthHintKey: 16
        ]
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        aInput.expectsMediaDataInRealTime = true

        if writer.canAdd(vInput) { writer.add(vInput) }
        if writer.canAdd(aInput) { writer.add(aInput) }

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
        print("[DEBUG-WRITER] Writer initialized: \(width)x\(height), audio=\(sampleRate)Hz/\(channelCount)ch")
    }

    /// Adjust a sample buffer's PTS to be relative to our timebase offset (start at 0),
    /// with an optional extra delay added to the PTS.
    private func adjustedBuffer(_ sampleBuffer: CMSampleBuffer, offset: CMTime, extraDelay: CMTime = .zero) -> CMSampleBuffer? {
        let originalPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let adjustedPTS = CMTimeAdd(CMTimeSubtract(originalPTS, offset), extraDelay)
        let duration = CMSampleBufferGetDuration(sampleBuffer)

        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: adjustedPTS,
            decodeTimeStamp: .invalid
        )
        var newBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &newBuffer
        )
        if status != noErr {
            print("[DEBUG-WRITER] Failed to adjust buffer timing: \(status)")
            return nil
        }
        return newBuffer
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

                // Determine the earliest timestamp to use as our zero-point
                var earliest = videoPTS
                if let firstAudio = self.pendingAudioBuffers.first {
                    let audioPTS = CMSampleBufferGetPresentationTimeStamp(firstAudio)
                    if CMTimeCompare(audioPTS, earliest) < 0 {
                        earliest = audioPTS
                    }
                }
                self.timebaseOffset = earliest

                // Start session at T=0 (all timestamps will be offset)
                writer.startSession(atSourceTime: .zero)
                self.sessionStarted = true
                print("[DEBUG-WRITER] Session started at T=0 (offset=\(CMTimeGetSeconds(earliest))s, buffered audio=\(self.pendingAudioBuffers.count))")

                // Flush buffered audio with adjusted timestamps + sync delay
                if let audioInput = self.audioInput {
                    for buffered in self.pendingAudioBuffers {
                        if audioInput.isReadyForMoreMediaData,
                           let adjusted = self.adjustedBuffer(buffered, offset: earliest, extraDelay: self.audioSyncDelay) {
                            audioInput.append(adjusted)
                        }
                    }
                }
                self.pendingAudioBuffers = []
            }

            guard let offset = self.timebaseOffset else { return }

            if input.isReadyForMoreMediaData,
               let adjusted = self.adjustedBuffer(sampleBuffer, offset: offset) {
                input.append(adjusted)
            }
        }
    }

    func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            guard let self = self else { return }

            // Buffer audio while waiting for the first video frame
            if self.pendingStart || (self.isWriting && !self.sessionStarted) {
                self.pendingAudioBuffers.append(sampleBuffer)
                return
            }

            guard self.isWriting,
                  !self.isPaused,
                  self.sessionStarted,
                  let writer = self.assetWriter,
                  let input = self.audioInput,
                  let offset = self.timebaseOffset,
                  writer.status == .writing else { return }

            if input.isReadyForMoreMediaData,
               let adjusted = self.adjustedBuffer(sampleBuffer, offset: offset, extraDelay: self.audioSyncDelay) {
                input.append(adjusted)
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

                let outputURL = self.outputURL
                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()
                writer.finishWriting {
                    if writer.status == .completed {
                        print("[DEBUG-WRITER] Writer finished successfully: \(outputURL?.lastPathComponent ?? "nil")")
                        // Inspect raw file A/V sync
                        if let url = outputURL {
                            Task { await Self.inspectRawFile(url: url) }
                        }
                        continuation.resume(returning: outputURL)
                    } else {
                        print("[DEBUG-WRITER] Writer finished with status=\(writer.status.rawValue), error=\(writer.error?.localizedDescription ?? "none")")
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    private static func inspectRawFile(url: URL) async {
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            print("[DEBUG-RAW-FILE] Duration: \(CMTimeGetSeconds(duration))s")
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            for (i, track) in videoTracks.enumerated() {
                let tr = try await track.load(.timeRange)
                print("[DEBUG-RAW-FILE] Video[\(i)]: start=\(CMTimeGetSeconds(tr.start))s duration=\(CMTimeGetSeconds(tr.duration))s")
            }
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            for (i, track) in audioTracks.enumerated() {
                let tr = try await track.load(.timeRange)
                print("[DEBUG-RAW-FILE] Audio[\(i)]: start=\(CMTimeGetSeconds(tr.start))s duration=\(CMTimeGetSeconds(tr.duration))s")
            }
            if let vt = videoTracks.first, let at = audioTracks.first {
                let vr = try await vt.load(.timeRange)
                let ar = try await at.load(.timeRange)
                print("[DEBUG-RAW-FILE] Audio-Video duration diff: \(CMTimeGetSeconds(ar.duration) - CMTimeGetSeconds(vr.duration))s")
            }
        } catch {
            print("[DEBUG-RAW-FILE] Inspection failed: \(error)")
        }
    }
}
