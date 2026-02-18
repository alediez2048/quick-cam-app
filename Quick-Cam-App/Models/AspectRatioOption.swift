import CoreGraphics

enum AspectRatioOption: String, CaseIterable, Identifiable {
    case vertical
    case horizontal
    case square
    case portrait

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vertical: return "9:16"
        case .horizontal: return "16:9"
        case .square: return "1:1"
        case .portrait: return "4:5"
        }
    }

    var ratio: CGFloat {
        switch self {
        case .vertical: return 9.0 / 16.0
        case .horizontal: return 16.0 / 9.0
        case .square: return 1.0
        case .portrait: return 4.0 / 5.0
        }
    }

    var outputSize: CGSize {
        switch self {
        case .vertical: return CGSize(width: 2160, height: 3840)
        case .horizontal: return CGSize(width: 3840, height: 2160)
        case .square: return CGSize(width: 2160, height: 2160)
        case .portrait: return CGSize(width: 2160, height: 2700)
        }
    }
}
