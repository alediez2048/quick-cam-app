import AppKit

enum CaptionAnimationType: String, CaseIterable, Identifiable {
    case karaoke
    case popup
    case classic
    case boxed

    var id: String { rawValue }
}

enum CaptionPosition: String, CaseIterable, Identifiable {
    case top
    case center
    case bottom

    var id: String { rawValue }
}

struct CaptionStyle: Equatable {
    let styleName: String
    let fontName: String
    let fontSize: CGFloat
    let textColor: NSColor
    let highlightColor: NSColor
    let backgroundColor: NSColor
    let position: CaptionPosition
    let animationType: CaptionAnimationType

    static func == (lhs: CaptionStyle, rhs: CaptionStyle) -> Bool {
        lhs.styleName == rhs.styleName
            && lhs.fontName == rhs.fontName
            && lhs.fontSize == rhs.fontSize
            && lhs.textColor == rhs.textColor
            && lhs.highlightColor == rhs.highlightColor
            && lhs.backgroundColor == rhs.backgroundColor
            && lhs.position == rhs.position
            && lhs.animationType == rhs.animationType
    }

    static let classic = CaptionStyle(
        styleName: "Classic",
        fontName: "HelveticaNeue-Bold",
        fontSize: 72,
        textColor: .white,
        highlightColor: .yellow,
        backgroundColor: NSColor.black.withAlphaComponent(0.6),
        position: .bottom,
        animationType: .classic
    )

    static let karaoke = CaptionStyle(
        styleName: "Karaoke",
        fontName: "HelveticaNeue-Bold",
        fontSize: 72,
        textColor: .white,
        highlightColor: .yellow,
        backgroundColor: NSColor.black.withAlphaComponent(0.6),
        position: .bottom,
        animationType: .karaoke
    )

    static let popup = CaptionStyle(
        styleName: "Pop-up",
        fontName: "HelveticaNeue-Bold",
        fontSize: 80,
        textColor: .white,
        highlightColor: .cyan,
        backgroundColor: .clear,
        position: .center,
        animationType: .popup
    )

    static let boxed = CaptionStyle(
        styleName: "Boxed",
        fontName: "HelveticaNeue-Bold",
        fontSize: 64,
        textColor: .white,
        highlightColor: .yellow,
        backgroundColor: NSColor.black.withAlphaComponent(0.8),
        position: .bottom,
        animationType: .boxed
    )

    static let allPresets: [CaptionStyle] = [.classic, .karaoke, .popup, .boxed]
}
