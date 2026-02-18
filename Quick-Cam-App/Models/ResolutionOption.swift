import AVFoundation

enum ResolutionOption: String, CaseIterable, Identifiable {
    case hd720p
    case hd1080p
    case uhd4K

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hd720p: return "720p"
        case .hd1080p: return "1080p"
        case .uhd4K: return "4K"
        }
    }

    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .hd720p: return .hd1280x720
        case .hd1080p: return .hd1920x1080
        case .uhd4K: return .hd4K3840x2160
        }
    }
}
