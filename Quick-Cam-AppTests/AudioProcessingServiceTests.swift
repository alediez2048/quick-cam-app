import XCTest
import AVFoundation
@testable import Quick_Cam_App

class MockAudioProcessingStep: AudioProcessingStep {
    let name: String
    var processCallCount = 0
    var lastInputURL: URL?

    // Shared log for tracking cross-step ordering
    static var callLog: [String] = []

    init(name: String) {
        self.name = name
    }

    func process(inputURL: URL) async throws -> URL {
        processCallCount += 1
        lastInputURL = inputURL
        MockAudioProcessingStep.callLog.append(name)
        return inputURL
    }
}

final class AudioProcessingServiceTests: XCTestCase {
    var testAudioURL: URL!

    override func setUp() {
        super.setUp()
        MockAudioProcessingStep.callLog = []
        testAudioURL = createTestWAVFile()
    }

    override func tearDown() {
        if let url = testAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        testAudioURL = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testProcessReturnsOutputURL() async throws {
        let service = AudioProcessingService(steps: [])
        let outputURL = try await service.process(inputURL: testAudioURL)
        XCTAssertNotNil(outputURL)
    }

    func testProcessedFileExists() async throws {
        let service = AudioProcessingService(steps: [])
        let outputURL = try await service.process(inputURL: testAudioURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path),
                       "Processed file should exist on disk")
    }

    func testPipelineExecutesAllSteps() async throws {
        let step1 = MockAudioProcessingStep(name: "Step1")
        let step2 = MockAudioProcessingStep(name: "Step2")
        let service = AudioProcessingService(steps: [step1, step2])

        _ = try await service.process(inputURL: testAudioURL)

        XCTAssertEqual(step1.processCallCount, 1, "Step1 should be called once")
        XCTAssertEqual(step2.processCallCount, 1, "Step2 should be called once")
    }

    func testStepsExecuteInOrder() async throws {
        let denoise = MockAudioProcessingStep(name: "Denoise")
        let normalize = MockAudioProcessingStep(name: "Normalize")
        let service = AudioProcessingService(steps: [denoise, normalize])

        _ = try await service.process(inputURL: testAudioURL)

        XCTAssertEqual(MockAudioProcessingStep.callLog, ["Denoise", "Normalize"],
                       "Denoise should run before Normalize")
    }

    func testEmptyPipelineReturnsCopy() async throws {
        let service = AudioProcessingService(steps: [])
        let outputURL = try await service.process(inputURL: testAudioURL)

        XCTAssertNotEqual(outputURL, testAudioURL,
                          "Output URL should differ from input (it's extracted audio)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path),
                       "Output copy should exist on disk")
    }

    // MARK: - DenoiseStep Tests

    func testDenoiseStepReturnsNewFile() async throws {
        let step = DenoiseStep()
        let outputURL = try await step.process(inputURL: testAudioURL)

        XCTAssertNotEqual(outputURL, testAudioURL,
                          "Output URL should differ from input")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path),
                       "Output file should exist on disk")
        addTeardownBlock { try? FileManager.default.removeItem(at: outputURL) }
    }

    func testDenoiseStepOutputIsValidAudio() async throws {
        let step = DenoiseStep()
        let outputURL = try await step.process(inputURL: testAudioURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: outputURL) }

        let inputFile = try AVAudioFile(forReading: testAudioURL)
        let outputFile = try AVAudioFile(forReading: outputURL)

        XCTAssertEqual(outputFile.processingFormat.sampleRate,
                       inputFile.processingFormat.sampleRate,
                       "Sample rate should match")
        XCTAssertEqual(outputFile.processingFormat.channelCount,
                       inputFile.processingFormat.channelCount,
                       "Channel count should match")
    }

    func testDenoiseStepPreservesAudioDuration() async throws {
        let step = DenoiseStep()
        let outputURL = try await step.process(inputURL: testAudioURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: outputURL) }

        let inputFile = try AVAudioFile(forReading: testAudioURL)
        let outputFile = try AVAudioFile(forReading: outputURL)

        let tolerance: AVAudioFramePosition = 1024
        XCTAssertEqual(outputFile.length, inputFile.length,
                       accuracy: tolerance,
                       "Frame count should match within tolerance")
    }

    func testDenoiseStepReducesNoiseFloor() async throws {
        let noiseURL = createWhiteNoiseWAVFile(amplitude: 0.05, durationSeconds: 1.0)
        addTeardownBlock { try? FileManager.default.removeItem(at: noiseURL) }

        let step = DenoiseStep()
        let outputURL = try await step.process(inputURL: noiseURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: outputURL) }

        let inputRMS = try rmsOfFile(url: noiseURL)
        let outputRMS = try rmsOfFile(url: outputURL)

        XCTAssertLessThan(outputRMS, inputRMS,
                          "Output RMS (\(outputRMS)) should be lower than input RMS (\(inputRMS))")
    }

    func testDenoiseStepPreservesSpeechLikeTone() async throws {
        let toneURL = createToneWithNoiseWAVFile(toneFrequency: 440,
                                                  toneAmplitude: 0.8,
                                                  noiseAmplitude: 0.05,
                                                  durationSeconds: 1.0)
        addTeardownBlock { try? FileManager.default.removeItem(at: toneURL) }

        let step = DenoiseStep()
        let outputURL = try await step.process(inputURL: toneURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: outputURL) }

        // Measure RMS of the tone portion only (skip 0.6s lead-in)
        let skipSamples = Int(44100 * 0.6)
        let inputRMS = try rmsOfFile(url: toneURL, skipSamples: skipSamples)
        let outputRMS = try rmsOfFile(url: outputURL, skipSamples: skipSamples)

        let preservation = outputRMS / inputRMS
        XCTAssertGreaterThan(preservation, 0.8,
                             "Tone energy should be >80% preserved (got \(preservation * 100)%)")
    }

    // MARK: - NormalizeStep Tests

    func testNormalizeStepReturnsNewFile() async throws {
        let step = NormalizeStep()
        let outputURL = try await step.process(inputURL: testAudioURL)

        XCTAssertNotEqual(outputURL, testAudioURL,
                          "Output URL should differ from input")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path),
                       "Output file should exist on disk")
        addTeardownBlock { try? FileManager.default.removeItem(at: outputURL) }
    }

    func testNormalizeStepOutputIsValidAudio() async throws {
        let quietURL = createSineWAVFile(amplitude: 0.05, frequency: 440, durationSeconds: 1.0)
        addTeardownBlock { try? FileManager.default.removeItem(at: quietURL) }

        let step = NormalizeStep()
        let outputURL = try await step.process(inputURL: quietURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: outputURL) }

        let inputFile = try AVAudioFile(forReading: quietURL)
        let outputFile = try AVAudioFile(forReading: outputURL)

        XCTAssertEqual(outputFile.processingFormat.sampleRate,
                       inputFile.processingFormat.sampleRate,
                       "Sample rate should match")
        XCTAssertEqual(outputFile.processingFormat.channelCount,
                       inputFile.processingFormat.channelCount,
                       "Channel count should match")
    }

    func testNormalizeStepPreservesAudioDuration() async throws {
        let quietURL = createSineWAVFile(amplitude: 0.05, frequency: 440, durationSeconds: 1.0)
        addTeardownBlock { try? FileManager.default.removeItem(at: quietURL) }

        let step = NormalizeStep()
        let outputURL = try await step.process(inputURL: quietURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: outputURL) }

        let inputFile = try AVAudioFile(forReading: quietURL)
        let outputFile = try AVAudioFile(forReading: outputURL)

        XCTAssertEqual(outputFile.length, inputFile.length,
                       "Frame count should match exactly")
    }

    func testNormalizeStepIncreasesQuietAudio() async throws {
        let quietURL = createSineWAVFile(amplitude: 0.05, frequency: 440, durationSeconds: 1.0)
        addTeardownBlock { try? FileManager.default.removeItem(at: quietURL) }

        let step = NormalizeStep()
        let outputURL = try await step.process(inputURL: quietURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: outputURL) }

        let inputRMS = try rmsOfFile(url: quietURL)
        let outputRMS = try rmsOfFile(url: outputURL)

        XCTAssertGreaterThan(outputRMS, inputRMS,
                             "Output RMS (\(outputRMS)) should be greater than input RMS (\(inputRMS))")
    }

    func testNormalizeStepDoesNotClip() async throws {
        let quietURL = createSineWAVFile(amplitude: 0.05, frequency: 440, durationSeconds: 1.0)
        addTeardownBlock { try? FileManager.default.removeItem(at: quietURL) }

        let step = NormalizeStep()
        let outputURL = try await step.process(inputURL: quietURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: outputURL) }

        let peak = try peakOfFile(url: outputURL)
        XCTAssertLessThanOrEqual(peak, 1.0,
                                  "All samples should be within [-1.0, 1.0], peak was \(peak)")
    }

    func testNormalizeStepLimitsLoudAudio() async throws {
        let loudURL = createSineWAVFile(amplitude: 0.95, frequency: 440, durationSeconds: 1.0)
        addTeardownBlock { try? FileManager.default.removeItem(at: loudURL) }

        let step = NormalizeStep()
        let outputURL = try await step.process(inputURL: loudURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: outputURL) }

        let peak = try peakOfFile(url: outputURL)
        XCTAssertLessThanOrEqual(peak, 1.0,
                                  "Peak should not exceed 1.0 after normalization, got \(peak)")
    }

    // MARK: - Helpers

    private func createTestWAVFile() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let sampleRate: Double = 44100
        let channels: AVAudioChannelCount = 1
        let frameCount: AVAudioFrameCount = 44100 // 1 second

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            fatalError("Failed to create audio format/buffer for test")
        }

        buffer.frameLength = frameCount
        // Fill with silence (zeros)
        if let channelData = buffer.floatChannelData {
            for i in 0..<Int(frameCount) {
                channelData[0][i] = 0.0
            }
        }

        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        } catch {
            fatalError("Failed to write test WAV file: \(error)")
        }

        return url
    }

    private func createWhiteNoiseWAVFile(amplitude: Float, durationSeconds: Double) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let sampleRate: Double = 44100
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData {
            for i in 0..<Int(frameCount) {
                channelData[0][i] = Float.random(in: -amplitude...amplitude)
            }
        }

        let file = try! AVAudioFile(forWriting: url, settings: format.settings)
        try! file.write(from: buffer)
        return url
    }

    /// Creates a WAV with noise-only lead-in (0.6s) then tone+noise.
    /// The lead-in matches the denoiser's noise estimation window so the tone is not mistaken for noise.
    private func createToneWithNoiseWAVFile(toneFrequency: Double,
                                             toneAmplitude: Float,
                                             noiseAmplitude: Float,
                                             durationSeconds: Double) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let sampleRate: Double = 44100
        let leadInSeconds = 0.6
        let totalDuration = leadInSeconds + durationSeconds
        let frameCount = AVAudioFrameCount(sampleRate * totalDuration)
        let leadInSamples = Int(sampleRate * leadInSeconds)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData {
            for i in 0..<Int(frameCount) {
                let noise = Float.random(in: -noiseAmplitude...noiseAmplitude)
                if i < leadInSamples {
                    // Noise-only lead-in for noise estimation
                    channelData[0][i] = noise
                } else {
                    let sine = toneAmplitude * sin(Float(2.0 * Double.pi * toneFrequency * Double(i) / sampleRate))
                    channelData[0][i] = sine + noise
                }
            }
        }

        let file = try! AVAudioFile(forWriting: url, settings: format.settings)
        try! file.write(from: buffer)
        return url
    }

    private func createSineWAVFile(amplitude: Float, frequency: Double, durationSeconds: Double) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let sampleRate: Double = 44100
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData {
            for i in 0..<Int(frameCount) {
                channelData[0][i] = amplitude * sin(Float(2.0 * Double.pi * frequency * Double(i) / sampleRate))
            }
        }

        let file = try! AVAudioFile(forWriting: url, settings: format.settings)
        try! file.write(from: buffer)
        return url
    }

    private func peakOfFile(url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            XCTFail("Could not create buffer")
            return 0
        }
        try file.read(into: buffer)

        guard let channelData = buffer.floatChannelData else { return 0 }
        var peak: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            let absSample = abs(channelData[0][i])
            if absSample > peak { peak = absSample }
        }
        return peak
    }

    private func rmsOfFile(url: URL, skipSamples: Int = 0) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            XCTFail("Could not create buffer")
            return 0
        }
        try file.read(into: buffer)

        guard let channelData = buffer.floatChannelData else { return 0 }
        let total = Int(buffer.frameLength)
        let start = min(skipSamples, total)
        let count = total - start
        guard count > 0 else { return 0 }

        var sumSquares: Float = 0
        for i in start..<total {
            let sample = channelData[0][i]
            sumSquares += sample * sample
        }
        return sqrt(sumSquares / Float(count))
    }
}
