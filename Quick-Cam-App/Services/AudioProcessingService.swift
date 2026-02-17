import AVFoundation

protocol AudioProcessingStep {
    var name: String { get }
    func process(inputURL: URL) async throws -> URL
}

class AudioProcessingService {
    private let steps: [AudioProcessingStep]

    init(steps: [AudioProcessingStep] = AudioProcessingService.defaultSteps()) {
        self.steps = steps
    }

    static func defaultSteps() -> [AudioProcessingStep] {
        [DenoiseStep(), NormalizeStep()]
    }

    func process(inputURL: URL) async throws -> URL {
        let audioURL = try await extractAudio(from: inputURL)

        var currentURL = audioURL
        for step in steps {
            currentURL = try await step.process(inputURL: currentURL)
        }

        return currentURL
    }

    private func extractAudio(from inputURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        // If no video tracks, input is already an audio file — just copy it
        if videoTracks.isEmpty {
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
            return outputURL
        }

        guard let audioTrack = audioTracks.first else {
            // Video with no audio track — copy as fallback
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
            return outputURL
        }

        let reader = try AVAssetReader(asset: asset)
        let readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
        let writerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1
        ]
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
        writer.add(writerInput)

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let extractionQueue = DispatchQueue(label: "audio.extraction")
            nonisolated(unsafe) let writerInput = writerInput
            nonisolated(unsafe) let readerOutput = readerOutput
            writerInput.requestMediaDataWhenReady(on: extractionQueue) {
                while writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(sampleBuffer)
                    } else {
                        writerInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }

        await writer.finishWriting()
        return outputURL
    }
}

// MARK: - Placeholder Steps

class DenoiseStep: AudioProcessingStep {
    let name = "Denoise"

    func process(inputURL: URL) async throws -> URL {
        // Placeholder: returns input unchanged (to be implemented in QC-009)
        return inputURL
    }
}

class NormalizeStep: AudioProcessingStep {
    let name = "Normalize"

    func process(inputURL: URL) async throws -> URL {
        // Placeholder: returns input unchanged (to be implemented in QC-010)
        return inputURL
    }
}
