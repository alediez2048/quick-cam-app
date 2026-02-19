import AppKit

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

struct CaptionFont: Identifiable, Hashable {
    let displayName: String
    let postScriptName: String

    var id: String { postScriptName }

    static let allFonts: [CaptionFont] = [
        CaptionFont(displayName: "Helvetica", postScriptName: "HelveticaNeue-Bold"),
        CaptionFont(displayName: "Avenir Next", postScriptName: "AvenirNext-Bold"),
        CaptionFont(displayName: "Futura", postScriptName: "Futura-Bold"),
        CaptionFont(displayName: "Gill Sans", postScriptName: "GillSans-Bold"),
        CaptionFont(displayName: "Arial Rounded", postScriptName: "ArialRoundedMTBold"),
        CaptionFont(displayName: "Rockwell", postScriptName: "Rockwell-Bold"),
        CaptionFont(displayName: "Impact", postScriptName: "Impact"),
        CaptionFont(displayName: "Chalkboard", postScriptName: "ChalkboardSE-Bold"),
        CaptionFont(displayName: "Marker Felt", postScriptName: "MarkerFelt-Wide"),
        CaptionFont(displayName: "American Typewriter", postScriptName: "AmericanTypewriter-Bold"),
    ]
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
        strokeWidth: 4,
        textHighlighterColor: .clear
    )

    static let popup = CaptionStyle(
        styleName: "Pop-up",
        fontName: "Futura-Bold",
        fontSize: 80,
        textColor: .white,
        highlightColor: .cyan,
        backgroundColor: .clear,
        position: .center,
        animationType: .popup,
        strokeColor: .black,
        strokeWidth: 5,
        textHighlighterColor: .clear
    )

    static let boxed = CaptionStyle(
        styleName: "Boxed",
        fontName: "AvenirNext-Bold",
        fontSize: 64,
        textColor: .white,
        highlightColor: .yellow,
        backgroundColor: .clear,
        position: .bottom,
        animationType: .boxed,
        strokeColor: .black,
        strokeWidth: 0,
        textHighlighterColor: NSColor.yellow.withAlphaComponent(0.85)
    )

    static let allPresets: [CaptionStyle] = [.classic, .karaoke, .popup, .boxed]
}
