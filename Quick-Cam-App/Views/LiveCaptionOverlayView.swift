import SwiftUI
import AVFoundation

struct LiveCaptionOverlayView: View {
    let player: AVPlayer
    let captions: [TimedCaption]
    let captionStyle: CaptionStyle
    let videoAspectRatio: CGFloat

    @State private var currentTime: Double = 0
    @State private var timeObserver: Any?
    @State private var observedPlayer: AVPlayer?

    private var activeCaption: TimedCaption? {
        captions.first { caption in
            let start = CMTimeGetSeconds(caption.startTime)
            let end = CMTimeGetSeconds(caption.endTime)
            return currentTime >= start && currentTime <= end
        }
    }

    /// Compute the rect where the video is actually displayed (letterboxed with .resizeAspect)
    private func videoRect(in viewSize: CGSize) -> CGRect {
        let viewAspect = viewSize.width / viewSize.height
        let videoWidth: CGFloat
        let videoHeight: CGFloat

        if videoAspectRatio > viewAspect {
            // Video is wider than view → pillarboxed top/bottom
            videoWidth = viewSize.width
            videoHeight = viewSize.width / videoAspectRatio
        } else {
            // Video is taller than view → letterboxed left/right
            videoHeight = viewSize.height
            videoWidth = viewSize.height * videoAspectRatio
        }

        let x = (viewSize.width - videoWidth) / 2
        let y = (viewSize.height - videoHeight) / 2
        return CGRect(x: x, y: y, width: videoWidth, height: videoHeight)
    }

    var body: some View {
        GeometryReader { geometry in
            let videoFrame = videoRect(in: geometry.size)
            let scale = videoFrame.width / 2160.0
            let fontSize = max(10, captionStyle.fontSize * scale)
            let insetPadding = 16.0 * scale

            if let caption = activeCaption {
                captionView(caption: caption, fontSize: fontSize, wordSpacing: fontSize * 0.2)
                    .frame(maxWidth: videoFrame.width - insetPadding * 2)
                    .position(
                        x: videoFrame.midX,
                        y: captionY(videoFrame: videoFrame)
                    )
            }
        }
        .onAppear {
            // Store the player that owns this observer so we remove from the correct instance
            let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
            observedPlayer = player
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                currentTime = CMTimeGetSeconds(time)
            }
        }
        .onDisappear {
            if let observer = timeObserver {
                observedPlayer?.removeTimeObserver(observer)
                timeObserver = nil
                observedPlayer = nil
            }
        }
    }

    private func captionY(videoFrame: CGRect) -> CGFloat {
        switch captionStyle.position {
        case .top:
            return videoFrame.minY + videoFrame.height * 0.12
        case .center:
            return videoFrame.midY
        case .bottom:
            return videoFrame.minY + videoFrame.height * 0.88
        }
    }

    @ViewBuilder
    private func captionView(caption: TimedCaption, fontSize: CGFloat, wordSpacing: CGFloat) -> some View {
        switch captionStyle.animationType {
        case .classic:
            classicCaption(caption: caption, fontSize: fontSize)
        case .karaoke:
            karaokeCaption(caption: caption, fontSize: fontSize, wordSpacing: wordSpacing)
        case .popup:
            popupCaption(caption: caption, fontSize: fontSize, wordSpacing: wordSpacing)
        case .boxed:
            boxedCaption(caption: caption, fontSize: fontSize, wordSpacing: wordSpacing)
        }
    }

    private func classicCaption(caption: TimedCaption, fontSize: CGFloat) -> some View {
        Text(caption.text)
            .font(.custom(captionStyle.fontName, size: fontSize))
            .foregroundColor(Color(nsColor: captionStyle.textColor))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: captionStyle.backgroundColor))
    }

    private func karaokeCaption(caption: TimedCaption, fontSize: CGFloat, wordSpacing: CGFloat) -> some View {
        let words = caption.words.isEmpty
            ? [TimedWord(text: caption.text, startTime: caption.startTime, endTime: caption.endTime)]
            : caption.words

        return FlowLayoutView(spacing: wordSpacing) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                let isActive = {
                    let start = CMTimeGetSeconds(word.startTime)
                    let end = CMTimeGetSeconds(word.endTime)
                    return currentTime >= start && currentTime <= end
                }()
                Text(word.text)
                    .font(.custom(captionStyle.fontName, size: fontSize))
                    .foregroundColor(isActive
                        ? Color(nsColor: captionStyle.highlightColor)
                        : Color(nsColor: captionStyle.textColor))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: captionStyle.backgroundColor))
    }

    private func popupCaption(caption: TimedCaption, fontSize: CGFloat, wordSpacing: CGFloat) -> some View {
        let words = caption.words.isEmpty
            ? [TimedWord(text: caption.text, startTime: caption.startTime, endTime: caption.endTime)]
            : caption.words

        return FlowLayoutView(spacing: wordSpacing) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                let wordStart = CMTimeGetSeconds(word.startTime)
                let appeared = currentTime >= wordStart

                if appeared {
                    Text(word.text)
                        .font(.custom(captionStyle.fontName, size: fontSize))
                        .foregroundColor(Color(nsColor: captionStyle.highlightColor))
                        .transition(.scale)
                }
            }
        }
    }

    private func boxedCaption(caption: TimedCaption, fontSize: CGFloat, wordSpacing: CGFloat) -> some View {
        let words = caption.words.isEmpty
            ? [TimedWord(text: caption.text, startTime: caption.startTime, endTime: caption.endTime)]
            : caption.words

        return FlowLayoutView(spacing: wordSpacing) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                Text(word.text)
                    .font(.custom(captionStyle.fontName, size: fontSize))
                    .foregroundColor(Color(nsColor: captionStyle.textColor))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: captionStyle.backgroundColor))
                    .cornerRadius(4)
            }
        }
    }
}

/// Simple wrapping horizontal layout for caption words
private struct FlowLayoutView: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing * 0.5
                rowHeight = 0
            }
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: totalWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowSubviews: [(Subviews.Element, CGSize)] = []

        func placeRow() {
            let rowWidth = rowSubviews.reduce(CGFloat(0)) { $0 + $1.1.width + spacing } - (rowSubviews.isEmpty ? 0 : spacing)
            var rx = bounds.minX + (maxWidth - rowWidth) / 2
            for (subview, size) in rowSubviews {
                subview.place(at: CGPoint(x: rx, y: bounds.minY + y), proposal: ProposedViewSize(size))
                rx += size.width + spacing
            }
            rowSubviews.removeAll()
        }

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                placeRow()
                x = 0
                y += rowHeight + spacing * 0.5
                rowHeight = 0
            }
            rowSubviews.append((subview, size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        placeRow()
    }
}
