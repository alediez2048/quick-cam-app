import AVFoundation
import Accelerate

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

// MARK: - Processing Steps

class DenoiseStep: AudioProcessingStep {
    let name = "Denoise"

    private let fftSize: Int = 2048
    private let hopSize: Int = 512
    private let noiseEstimationSeconds: Double = 0.5
    private let gateThresholdMultiplier: Float = 1.5
    private let attenuationFactor: Float = 0.1

    func process(inputURL: URL) async throws -> URL {
        let inputFile = try AVAudioFile(forReading: inputURL)
        let format = inputFile.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = AVAudioFrameCount(inputFile.length)

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw DenoiseError.bufferCreationFailed
        }
        try inputFile.read(into: inputBuffer)

        guard let channelData = inputBuffer.floatChannelData else {
            throw DenoiseError.noChannelData
        }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(inputBuffer.frameLength)))
        let denoised = try spectralGate(samples: samples, sampleRate: sampleRate)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw DenoiseError.bufferCreationFailed
        }
        outputBuffer.frameLength = totalFrames

        if let outData = outputBuffer.floatChannelData {
            let count = min(denoised.count, Int(totalFrames))
            for i in 0..<count {
                outData[0][i] = denoised[i]
            }
        }

        let outputFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        try outputFile.write(from: outputBuffer)

        return outputURL
    }

    private func spectralGate(samples: [Float], sampleRate: Double) throws -> [Float] {
        let n = samples.count
        guard n > 0 else { return [] }

        let log2n = vDSP_Length(log2(Float(fftSize)))
        let numBins = fftSize

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            throw DenoiseError.fftSetupFailed
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Create Hann window
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        let numFrames = max(1, (n - fftSize) / hopSize + 1)

        // Allocate FFT buffers (full complex FFT, so fftSize elements each)
        let realp = UnsafeMutablePointer<Float>.allocate(capacity: fftSize)
        let imagp = UnsafeMutablePointer<Float>.allocate(capacity: fftSize)
        defer { realp.deallocate(); imagp.deallocate() }

        // Store FFT results and magnitudes per frame
        var allReal = [[Float]](repeating: [Float](repeating: 0, count: numBins), count: numFrames)
        var allImag = [[Float]](repeating: [Float](repeating: 0, count: numBins), count: numFrames)
        var allMagnitudes = [[Float]](repeating: [Float](repeating: 0, count: numBins), count: numFrames)

        for frameIdx in 0..<numFrames {
            let start = frameIdx * hopSize

            // Load windowed frame into real part, zero imaginary
            for i in 0..<fftSize {
                let idx = start + i
                realp[i] = idx < n ? samples[idx] * window[i] : 0
                imagp[i] = 0
            }

            // Forward complex FFT
            var split = DSPSplitComplex(realp: realp, imagp: imagp)
            vDSP_fft_zip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))

            // Copy out and compute magnitudes
            for bin in 0..<numBins {
                allReal[frameIdx][bin] = realp[bin]
                allImag[frameIdx][bin] = imagp[bin]
                allMagnitudes[frameIdx][bin] = sqrt(realp[bin] * realp[bin] + imagp[bin] * imagp[bin])
            }
        }

        // Estimate noise profile from first ~0.5s
        let noiseFrameCount = max(1, Int(noiseEstimationSeconds * sampleRate) / hopSize)
        let framesToAverage = min(noiseFrameCount, numFrames)
        var noiseProfile = [Float](repeating: 0, count: numBins)

        for frameIdx in 0..<framesToAverage {
            vDSP_vadd(noiseProfile, 1, allMagnitudes[frameIdx], 1, &noiseProfile, 1, vDSP_Length(numBins))
        }
        var divisor = Float(framesToAverage)
        vDSP_vsdiv(noiseProfile, 1, &divisor, &noiseProfile, 1, vDSP_Length(numBins))

        // Threshold = noiseProfile × gateThresholdMultiplier
        var threshold = [Float](repeating: 0, count: numBins)
        var multiplier = gateThresholdMultiplier
        vDSP_vsmul(noiseProfile, 1, &multiplier, &threshold, 1, vDSP_Length(numBins))

        // Apply spectral gate and inverse STFT with overlap-add
        var output = [Float](repeating: 0, count: n)
        // vDSP_fft_zip round-trip scaling: forward * inverse = N * input
        let scale = 1.0 / Float(fftSize)

        for frameIdx in 0..<numFrames {
            // Load gated FFT data
            for bin in 0..<numBins {
                let gain: Float = allMagnitudes[frameIdx][bin] < threshold[bin] ? attenuationFactor : 1.0
                realp[bin] = allReal[frameIdx][bin] * gain
                imagp[bin] = allImag[frameIdx][bin] * gain
            }

            // Inverse complex FFT
            var split = DSPSplitComplex(realp: realp, imagp: imagp)
            vDSP_fft_zip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Inverse))

            // Scale, apply synthesis window, and overlap-add (use real part only)
            let start = frameIdx * hopSize
            for i in 0..<fftSize where start + i < n {
                output[start + i] += realp[i] * scale * window[i]
            }
        }

        // Normalize by overlap-add gain of squared Hann window.
        // Compute the per-sample window sum-of-squares and clamp to the steady-state
        // value to avoid edge amplification where few windows overlap.
        var windowSumSq = [Float](repeating: 0, count: n)
        for frameIdx in 0..<numFrames {
            let start = frameIdx * hopSize
            for i in 0..<fftSize where start + i < n {
                windowSumSq[start + i] += window[i] * window[i]
            }
        }
        // Steady-state value for Hann window with 75% overlap is ~1.5
        let steadyState = windowSumSq[min(fftSize, n - 1)]
        let minNorm = max(steadyState * 0.5, 1e-8)
        for i in 0..<n {
            let norm = max(windowSumSq[i], minNorm)
            output[i] /= norm
        }

        return output
    }

    enum DenoiseError: Error {
        case bufferCreationFailed
        case noChannelData
        case fftSetupFailed
    }
}

class NormalizeStep: AudioProcessingStep {
    let name = "Normalize"

    func process(inputURL: URL) async throws -> URL {
        // Placeholder: returns input unchanged (to be implemented in QC-010)
        return inputURL
    }
}
