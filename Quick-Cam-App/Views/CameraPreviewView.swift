import SwiftUI
import AVFoundation

struct CameraPreviewView: NSViewRepresentable {
    @ObservedObject var cameraViewModel: CameraViewModel

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.setSession(cameraViewModel.session, sessionQueue: cameraViewModel.cameraService.sessionQueue)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.setMirrored(cameraViewModel.isMirrored)
    }
}

class CameraPreviewNSView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasSetupLayer = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    func setSession(_ session: AVCaptureSession, sessionQueue: DispatchQueue) {
        guard !hasSetupLayer else { return }
        hasSetupLayer = true

        // Create layer without a session to avoid mutating AVCaptureSession
        // on the main thread while startRunning() runs on the session queue.
        let newPreviewLayer = AVCaptureVideoPreviewLayer()
        newPreviewLayer.videoGravity = .resizeAspectFill
        newPreviewLayer.frame = bounds

        layer?.addSublayer(newPreviewLayer)
        previewLayer = newPreviewLayer

        // Set the session on the session queue to serialize with startRunning()
        sessionQueue.async {
            newPreviewLayer.session = session
        }
    }

    func setMirrored(_ enabled: Bool) {
        if enabled {
            previewLayer?.transform = CATransform3DMakeScale(-1, 1, 1)
        } else {
            previewLayer?.transform = CATransform3DIdentity
        }
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}
