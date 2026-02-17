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

    var session: AVCaptureSession { AVCaptureSession() }

    var startRecordingCallCount = 0
    var stopRecordingCallCount = 0

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
}
