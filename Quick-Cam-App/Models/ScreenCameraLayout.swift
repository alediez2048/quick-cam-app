import Foundation

enum ScreenCameraLayout: String, CaseIterable, Identifiable {
    case sideBySide
    case circleBubble
    case squareBubble

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sideBySide: return "Side by Side"
        case .circleBubble: return "Circle Bubble"
        case .squareBubble: return "Square Bubble"
        }
    }

    var systemImage: String {
        switch self {
        case .sideBySide: return "rectangle.split.2x1"
        case .circleBubble: return "circle.inset.filled"
        case .squareBubble: return "rectangle.inset.filled"
        }
    }

    var isBubbleLayout: Bool {
        self == .circleBubble || self == .squareBubble
    }
}
