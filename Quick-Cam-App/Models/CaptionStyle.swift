import AppKit

struct CaptionFont: Identifiable, Hashable {
    let id: String
    let displayName: String
    let fontName: String

    static let allFonts: [CaptionFont] = [
        CaptionFont(id: "helvetica", displayName: "Helvetica", fontName: "HelveticaNeue-Bold"),
        CaptionFont(id: "avenir", displayName: "Avenir Next", fontName: "AvenirNext-Bold"),
        CaptionFont(id: "futura", displayName: "Futura", fontName: "Futura-Bold"),
        CaptionFont(id: "gillsans", displayName: "Gill Sans", fontName: "GillSans-Bold"),
        CaptionFont(id: "arialrounded", displayName: "Arial Rounded", fontName: "ArialRoundedMTBold"),
        CaptionFont(id: "rockwell", displayName: "Rockwell", fontName: "Rockwell-Bold"),
        CaptionFont(id: "impact", displayName: "Impact", fontName: "Impact"),
        CaptionFont(id: "chalkboard", displayName: "Chalkboard", fontName: "ChalkboardSE-Bold"),
        CaptionFont(id: "markerfelt", displayName: "Marker Felt", fontName: "MarkerFelt-Wide"),
        CaptionFont(id: "typewriter", displayName: "American Typewriter", fontName: "AmericanTypewriter-Bold"),
    ]
}

enum CaptionAnimationType: String, CaseIterable, Identifiable {
    case karaoke
    case popup
    case classic
    case boxed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .karaoke: return "Karaoke"
        case .popup: return "Pop-up"
        case .classic: return "Classic"
        case .boxed: return "Boxed"
        }
    }
}

enum CaptionPosition: String, CaseIterable, Identifiable {
    case top
    case center
    case bottom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: return "Top"
        case .center: return "Center"
        case .bottom: return "Bottom"
        }
    }
}

struct CaptionStyle: Equatable {
    var styleName: String
    var fontName: String
    var fontSize: CGFloat
    var textColor: NSColor
    var highlightColor: NSColor
    var backgroundColor: NSColor
    var position: CaptionPosition
    var animationType: CaptionAnimationType
    var strokeColor: NSColor
    var strokeWidth: CGFloat
    var textHighlighterColor: NSColor

    static func == (lhs: CaptionStyle, rhs: CaptionStyle) -> Bool {
        lhs.styleName == rhs.styleName
            && lhs.fontName == rhs.fontName
            && lhs.fontSize == rhs.fontSize
            && lhs.textColor == rhs.textColor
            && lhs.highlightColor == rhs.highlightColor
            && lhs.backgroundColor == rhs.backgroundColor
            && lhs.position == rhs.position
            && lhs.animationType == rhs.animationType
            && lhs.strokeColor == rhs.strokeColor
            && lhs.strokeWidth == rhs.strokeWidth
            && lhs.textHighlighterColor == rhs.textHighlighterColor
    }

    static let classic = CaptionStyle(
        styleName: "Classic",
        fontName: "HelveticaNeue-Bold",
        fontSize: 72,
        textColor: .white,
        highlightColor: .yellow,
        backgroundColor: NSColor.black.withAlphaComponent(0.6),
        position: .bottom,
        animationType: .classic,
        strokeColor: .black,
        strokeWidth: 0,
        textHighlighterColor: .clear
    )

    static let karaoke = CaptionStyle(
        styleName: "Karaoke",
        fontName: "HelveticaNeue-Bold",
        fontSize: 72,
        textColor: .white,
        highlightColor: .yellow,
        backgroundColor: NSColor.black.withAlphaComponent(0.6),
        position: .bottom,
        animationType: .karaoke,
        strokeColor: .black,
        strokeWidth: 0,
        textHighlighterColor: .clear
    )

    static let popup = CaptionStyle(
        styleName: "Pop-up",
        fontName: "HelveticaNeue-Bold",
        fontSize: 80,
        textColor: .white,
        highlightColor: .cyan,
        backgroundColor: .clear,
        position: .center,
        animationType: .popup,
        strokeColor: .black,
        strokeWidth: 0,
        textHighlighterColor: .clear
    )

    static let boxed = CaptionStyle(
        styleName: "Boxed",
        fontName: "HelveticaNeue-Bold",
        fontSize: 64,
        textColor: .white,
        highlightColor: .yellow,
        backgroundColor: NSColor.black.withAlphaComponent(0.8),
        position: .bottom,
        animationType: .boxed,
        strokeColor: .black,
        strokeWidth: 0,
        textHighlighterColor: .clear
    )

    static let allPresets: [CaptionStyle] = [.classic, .karaoke, .popup, .boxed]
}
