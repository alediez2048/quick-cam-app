import AppKit

struct RecordedVideo: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let thumbnail: NSImage?
    let date: Date
    let title: String

    static func == (lhs: RecordedVideo, rhs: RecordedVideo) -> Bool {
        lhs.url == rhs.url
    }
}
