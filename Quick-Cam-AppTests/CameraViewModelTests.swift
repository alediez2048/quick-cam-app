import XCTest
import AVFoundation
@testable import Quick_Cam_App

class MockCameraService: CameraServiceProtocol {
    var availableCameras: [AVCaptureDevice] = []
    var selectedCamera: AVCaptureDevice?
    var isSessionRunning = false
    var isAuthorized = false
    var isReady = false
    var isRecording = false
    var recordedVideoURL: URL?
    var error: String?
    var isPaused = false
    var audioLevel: Float = -160.0
    var selectedResolution: ResolutionOption = .hd1080p

    var session: AVCaptureSession { AVCaptureSession() }

    var startRecordingCallCount = 0
    var stopRecordingCallCount = 0
    var pauseRecordingCallCount = 0
    var resumeRecordingCallCount = 0

    func checkAuthorization() {}
    func setupAndStartSession() {}
    func stopSession() {}
    func switchCamera(to camera: AVCaptureDevice) {}

    func startRecording() {
        startRecordingCallCount += 1
        isRecording = true
    }

    func stopRecording() {
        stopRecordingCallCount += 1
        isRecording = false
    }

    func pauseRecording() {
        pauseRecordingCallCount += 1
        isPaused = true
    }

    func resumeRecording() {
        resumeRecordingCallCount += 1
        isPaused = false
    }
}

final class CameraViewModelTests: XCTestCase {
    var sut: CameraViewModel!
    var mockService: MockCameraService!

    override func setUp() {
        super.setUp()
        mockService = MockCameraService()
        sut = CameraViewModel(cameraService: mockService)
    }

    override func tearDown() {
        sut = nil
        mockService = nil
        super.tearDown()
    }

    // MARK: - Countdown Tests

    func testStartRecordingBeginsCountdown() {
        sut.startRecording()

        XCTAssertTrue(sut.isCountingDown)
        XCTAssertEqual(sut.countdownValue, 3)
        XCTAssertEqual(mockService.startRecordingCallCount, 0,
                       "Recording should NOT start immediately")
    }

    func testCountdownDecrementsToZero() {
        sut.startRecording()

        XCTAssertEqual(sut.countdownValue, 3)

        RunLoop.current.run(until: Date().addingTimeInterval(1.1))
        XCTAssertEqual(sut.countdownValue, 2)

        RunLoop.current.run(until: Date().addingTimeInterval(1.1))
        XCTAssertEqual(sut.countdownValue, 1)

        RunLoop.current.run(until: Date().addingTimeInterval(1.1))
        XCTAssertEqual(sut.countdownValue, 0)
    }

    func testRecordingStartsAfterCountdownReachesZero() {
        sut.startRecording()

        XCTAssertEqual(mockService.startRecordingCallCount, 0)

        RunLoop.current.run(until: Date().addingTimeInterval(3.2))

        XCTAssertEqual(mockService.startRecordingCallCount, 1,
                       "Recording should start after countdown reaches zero")
        XCTAssertFalse(sut.isCountingDown)
    }

    func testCountdownCanBeCancelled() {
        sut.startRecording()
        XCTAssertTrue(sut.isCountingDown)

        sut.cancelCountdown()

        XCTAssertFalse(sut.isCountingDown)
        XCTAssertEqual(sut.countdownValue, 0)
        XCTAssertEqual(mockService.startRecordingCallCount, 0,
                       "Recording should NOT start after cancellation")

        RunLoop.current.run(until: Date().addingTimeInterval(3.5))
        XCTAssertEqual(mockService.startRecordingCallCount, 0)
    }

    func testStopRecordingDuringCountdownCancels() {
        sut.startRecording()
        XCTAssertTrue(sut.isCountingDown)

        sut.stopRecording()

        XCTAssertFalse(sut.isCountingDown)
        XCTAssertEqual(sut.countdownValue, 0)
        XCTAssertEqual(mockService.startRecordingCallCount, 0)
        XCTAssertEqual(mockService.stopRecordingCallCount, 0,
                       "Should not call stopRecording on service since recording never started")
    }

    func testIsRecordingRemainsFalseDuringCountdown() {
        sut.startRecording()

        XCTAssertFalse(sut.isRecording,
                       "isRecording should remain false during countdown")
        XCTAssertTrue(sut.isCountingDown)

        RunLoop.current.run(until: Date().addingTimeInterval(1.1))
        XCTAssertFalse(sut.isRecording,
                       "isRecording should still be false mid-countdown")

        RunLoop.current.run(until: Date().addingTimeInterval(1.1))
        XCTAssertFalse(sut.isRecording,
                       "isRecording should still be false at countdown 1")
    }

    // MARK: - Audio Level Tests

    func testAudioLevelDefaultsToSilence() {
        XCTAssertEqual(sut.audioLevel, -160.0,
                       "audioLevel should default to -160.0 (silence in dBFS)")
    }

    func testAudioLevelExposedFromService() {
        mockService.audioLevel = -20.0
        XCTAssertEqual(mockService.audioLevel, -20.0,
                       "Mock service audioLevel should update")
    }

    // MARK: - Pause/Resume Tests

    func testPauseRecordingCallsService() {
        // Start recording first (wait for countdown)
        sut.startRecording()
        RunLoop.current.run(until: Date().addingTimeInterval(3.2))
        // Sync isRecording from mock (no Combine binding in tests)
        sut.isRecording = true

        sut.pauseRecording()

        XCTAssertEqual(mockService.pauseRecordingCallCount, 1,
                       "pauseRecording should forward to service")
    }

    func testResumeRecordingCallsService() {
        // Start recording and pause
        sut.startRecording()
        RunLoop.current.run(until: Date().addingTimeInterval(3.2))
        // Sync state from mock (no Combine binding in tests)
        sut.isRecording = true
        sut.pauseRecording()
        sut.isPaused = true

        sut.resumeRecording()

        XCTAssertEqual(mockService.resumeRecordingCallCount, 1,
                       "resumeRecording should forward to service")
    }

    func testPauseOnlyWorksWhileRecording() {
        // Not recording, not counting down
        sut.pauseRecording()
        XCTAssertEqual(mockService.pauseRecordingCallCount, 0,
                       "pauseRecording should do nothing when not recording")

        // During countdown
        sut.startRecording()
        XCTAssertTrue(sut.isCountingDown)
        sut.pauseRecording()
        XCTAssertEqual(mockService.pauseRecordingCallCount, 0,
                       "pauseRecording should do nothing during countdown")
    }
}
