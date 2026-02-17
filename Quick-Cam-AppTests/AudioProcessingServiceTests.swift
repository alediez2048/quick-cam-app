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
}
