import Foundation

enum RecordingMode: String, CaseIterable, Identifiable {
    case cameraOnly
    case screenOnly
    case screenAndCamera

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cameraOnly: return "Camera"
        case .screenOnly: return "Screen"
        case .screenAndCamera: return "Both"
        }
    }

    var systemImage: String {
        switch self {
        case .cameraOnly: return "camera.fill"
        case .screenOnly: return "display"
        case .screenAndCamera: return "rectangle.inset.filled.and.person.filled"
        }
    }

    var needsScreenCapture: Bool {
        self == .screenOnly || self == .screenAndCamera
    }

    var needsCamera: Bool {
        self == .cameraOnly || self == .screenAndCamera
    }
}
