import SwiftUI
import AVFoundation

struct CameraPreviewView: NSViewRepresentable {
    @ObservedObject var cameraViewModel: CameraViewModel

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.setSession(cameraViewModel.session)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        // Don't update the session - it's already set
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

    func setSession(_ session: AVCaptureSession) {
        guard !hasSetupLayer else { return }
        hasSetupLayer = true

        let newPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
        newPreviewLayer.videoGravity = .resizeAspectFill
        newPreviewLayer.frame = bounds

        layer?.addSublayer(newPreviewLayer)
        previewLayer = newPreviewLayer
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}
