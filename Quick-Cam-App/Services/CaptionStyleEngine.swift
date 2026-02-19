import AVFoundation
import AppKit
import CoreText
import QuartzCore

class CaptionStyleEngine {

    // MARK: - Helpers

    /// Convert NSColor to sRGB CGColor for reliable rendering in video composition.
    private func sRGBColor(from nsColor: NSColor) -> CGColor {
        if let converted = nsColor.usingColorSpace(.sRGB) {
            return converted.cgColor
        }
        return CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    }

    /// Pre-render text into a CGImage using Core Text, with optional stroke outline and highlighter background.
    private func renderTextImage(
        text: String,
        fontName: String,
        fontSize: CGFloat,
        textColor: CGColor,
        size: CGSize,
        alignment: CTTextAlignment = .center,
        strokeColor: CGColor? = nil,
        strokeWidth: CGFloat = 0,
        highlighterColor: CGColor? = nil
    ) -> CGImage? {
        let w = Int(size.width)
        let h = Int(size.height)
        guard w > 0, h > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let ctFont = CTFontCreateWithName(fontName as CFString, fontSize, nil)

        var align = alignment
        var alignSetting = CTParagraphStyleSetting(
            spec: .alignment,
            valueSize: MemoryLayout<CTTextAlignment>.size,
            value: &align
        )
        let paragraphStyle = CTParagraphStyleCreate(&alignSetting, 1)

        // --- Highlighter background ---
        if let hlColor = highlighterColor, hlColor.alpha > 0 {
            let measureAttrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle
            ]
            let measureStr = NSAttributedString(string: text, attributes: measureAttrs)
            let framesetter = CTFramesetterCreateWithAttributedString(measureStr as CFAttributedString)
            let constraintSize = CGSize(width: size.width, height: CGFloat.greatestFiniteMagnitude)
            let textSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil, constraintSize, nil)

            let hPad = fontSize * 0.15
            let vPad = fontSize * 0.08
            let hlWidth = textSize.width + hPad * 2
            let hlHeight = textSize.height + vPad * 2
            let hlX = (size.width - hlWidth) / 2
            let hlY = (size.height - hlHeight) / 2
            let hlRect = CGRect(x: hlX, y: hlY, width: hlWidth, height: hlHeight)
            let cornerRadius = fontSize * 0.12

            let hlPath = CGPath(roundedRect: hlRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            ctx.addPath(hlPath)
            ctx.setFillColor(hlColor)
            ctx.fillPath()
        }

        // --- Build fill attributes ---
        let fillAttributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): textColor,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle
        ]

        let fillString = NSAttributedString(string: text, attributes: fillAttributes)
        let fillFramesetter = CTFramesetterCreateWithAttributedString(fillString as CFAttributedString)

        let constraintSize = CGSize(width: size.width, height: CGFloat.greatestFiniteMagnitude)
        let textSize = CTFramesetterSuggestFrameSizeWithConstraints(fillFramesetter, CFRange(location: 0, length: 0), nil, constraintSize, nil)

        let yOffset = max(0, (size.height - textSize.height) / 2)
        let textRect = CGRect(x: 0, y: yOffset, width: size.width, height: textSize.height)
        let path = CGMutablePath()
        path.addRect(textRect)

        // --- Stroke pass (drawn first, behind fill) ---
        if strokeWidth > 0, let sColor = strokeColor {
            let strokeAttrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
                NSAttributedString.Key(kCTStrokeWidthAttributeName as String): strokeWidth as NSNumber,
                NSAttributedString.Key(kCTStrokeColorAttributeName as String): sColor,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle
            ]
            let strokeStr = NSAttributedString(string: text, attributes: strokeAttrs)
            let strokeFramesetter = CTFramesetterCreateWithAttributedString(strokeStr as CFAttributedString)
            let strokeFrame = CTFramesetterCreateFrame(strokeFramesetter, CFRange(location: 0, length: 0), path, nil)
            CTFrameDraw(strokeFrame, ctx)
        }

        // --- Fill pass (drawn on top) ---
        let fillFrame = CTFramesetterCreateFrame(fillFramesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(fillFrame, ctx)

        return ctx.makeImage()
    }

    func buildCaptionLayers(
        captions: [TimedCaption],
        style: CaptionStyle,
        videoSize: CGSize,
        totalDuration: Double
    ) -> [CALayer] {
        switch style.animationType {
        case .classic:
            return buildClassicLayers(captions: captions, style: style, videoSize: videoSize, totalDuration: totalDuration)
        case .karaoke:
            return buildKaraokeLayers(captions: captions, style: style, videoSize: videoSize, totalDuration: totalDuration)
        case .popup:
            return buildPopupLayers(captions: captions, style: style, videoSize: videoSize, totalDuration: totalDuration)
        case .boxed:
            return buildBoxedLayers(captions: captions, style: style, videoSize: videoSize, totalDuration: totalDuration)
        }
    }

    /// Create a show/hide opacity animation for the given time window.
    private func makeOpacityAnimation(start: Double, end: Double, totalDuration: Double) -> CAKeyframeAnimation {
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [0, 0, 1, 1, 0, 0]
        anim.keyTimes = [
            0,
            NSNumber(value: max(0, start - 0.01) / totalDuration),
            NSNumber(value: start / totalDuration),
            NSNumber(value: end / totalDuration),
            NSNumber(value: min(totalDuration, end + 0.01) / totalDuration),
            1
        ]
        anim.duration = totalDuration
        anim.beginTime = AVCoreAnimationBeginTimeAtZero
        anim.isRemovedOnCompletion = false
        return anim
    }

    // MARK: - Classic

    private func buildClassicLayers(
        captions: [TimedCaption],
        style: CaptionStyle,
        videoSize: CGSize,
        totalDuration: Double
    ) -> [CALayer] {
        var layers: [CALayer] = []
        let padding: CGFloat = 100
        let textHeight: CGFloat = 200
        let textWidth = videoSize.width - (padding * 2)
        let textCGColor = sRGBColor(from: style.textColor)
        let strokeCGColor = sRGBColor(from: style.strokeColor)
        let highlighterCGColor = sRGBColor(from: style.textHighlighterColor)

        for caption in captions {
            let layer = CALayer()
            let yOrigin = positionY(for: style.position, videoSize: videoSize, textHeight: textHeight, padding: padding)
            layer.frame = CGRect(x: padding, y: yOrigin, width: textWidth, height: textHeight)
            layer.backgroundColor = sRGBColor(from: style.backgroundColor)

            if let img = renderTextImage(
                text: caption.text, fontName: style.fontName, fontSize: style.fontSize,
                textColor: textCGColor, size: CGSize(width: textWidth, height: textHeight),
                strokeColor: strokeCGColor, strokeWidth: style.strokeWidth,
                highlighterColor: highlighterCGColor
            ) {
                layer.contents = img
            }

            layer.opacity = 0
            let startSeconds = CMTimeGetSeconds(caption.startTime)
            let endSeconds = CMTimeGetSeconds(caption.endTime)
            layer.add(makeOpacityAnimation(start: startSeconds, end: endSeconds, totalDuration: totalDuration), forKey: "opacity")

            layers.append(layer)
        }
        return layers
    }

    // MARK: - Karaoke

    private func buildKaraokeLayers(
        captions: [TimedCaption],
        style: CaptionStyle,
        videoSize: CGSize,
        totalDuration: Double
    ) -> [CALayer] {
        var layers: [CALayer] = []
        let padding: CGFloat = 100
        let textHeight: CGFloat = 200
        let textWidth = videoSize.width - (padding * 2)

        let textCGColor = sRGBColor(from: style.textColor)
        let highlightCGColor = sRGBColor(from: style.highlightColor)
        let strokeCGColor = sRGBColor(from: style.strokeColor)
        let highlighterCGColor = sRGBColor(from: style.textHighlighterColor)

        for caption in captions {
            let containerLayer = CALayer()
            let yOrigin = positionY(for: style.position, videoSize: videoSize, textHeight: textHeight, padding: padding)
            containerLayer.frame = CGRect(x: padding, y: yOrigin, width: textWidth, height: textHeight)
            containerLayer.backgroundColor = sRGBColor(from: style.backgroundColor)

            let startSeconds = CMTimeGetSeconds(caption.startTime)
            let endSeconds = CMTimeGetSeconds(caption.endTime)

            containerLayer.opacity = 0
            containerLayer.add(makeOpacityAnimation(start: startSeconds, end: endSeconds, totalDuration: totalDuration), forKey: "opacity")

            let words = caption.words.isEmpty
                ? [TimedWord(text: caption.text, startTime: caption.startTime, endTime: caption.endTime)]
                : caption.words

            let font = NSFont(name: style.fontName, size: style.fontSize) ?? NSFont.boldSystemFont(ofSize: style.fontSize)
            var xOffset: CGFloat = 0
            let wordSpacing: CGFloat = style.fontSize * 0.3
            let wordHeight = style.fontSize * 1.3
            let verticalPadding: CGFloat = (textHeight - wordHeight) / 2

            // Measure total width for centering
            var totalTextWidth: CGFloat = 0
            var wordWidths: [CGFloat] = []
            for word in words {
                let attrs: [NSAttributedString.Key: Any] = [.font: font]
                let size = (word.text as NSString).size(withAttributes: attrs)
                wordWidths.append(size.width)
                totalTextWidth += size.width
            }
            totalTextWidth += wordSpacing * CGFloat(max(0, words.count - 1))
            xOffset = max(0, (textWidth - totalTextWidth) / 2)

            for (index, word) in words.enumerated() {
                let wordSize = CGSize(width: wordWidths[index] + 4, height: wordHeight)
                let wordFrame = CGRect(x: xOffset, y: verticalPadding, width: wordSize.width, height: wordSize.height)

                // Base word in text color (always visible)
                let baseLayer = CALayer()
                baseLayer.frame = wordFrame
                if let img = renderTextImage(
                    text: word.text, fontName: style.fontName, fontSize: style.fontSize,
                    textColor: textCGColor, size: wordSize, alignment: .left,
                    strokeColor: strokeCGColor, strokeWidth: style.strokeWidth,
                    highlighterColor: highlighterCGColor
                ) {
                    baseLayer.contents = img
                }
                containerLayer.addSublayer(baseLayer)

                // Highlight word overlay (fades in/out during word timing) — no highlighter to avoid double-drawing
                let highlightLayer = CALayer()
                highlightLayer.frame = wordFrame
                if let img = renderTextImage(
                    text: word.text, fontName: style.fontName, fontSize: style.fontSize,
                    textColor: highlightCGColor, size: wordSize, alignment: .left,
                    strokeColor: strokeCGColor, strokeWidth: style.strokeWidth
                ) {
                    highlightLayer.contents = img
                }
                highlightLayer.opacity = 0

                let wordStart = CMTimeGetSeconds(word.startTime)
                let wordEnd = CMTimeGetSeconds(word.endTime)
                highlightLayer.add(makeOpacityAnimation(start: wordStart, end: wordEnd, totalDuration: totalDuration), forKey: "opacity")

                containerLayer.addSublayer(highlightLayer)
                xOffset += wordWidths[index] + wordSpacing
            }

            layers.append(containerLayer)
        }
        return layers
    }

    // MARK: - Popup

    private func buildPopupLayers(
        captions: [TimedCaption],
        style: CaptionStyle,
        videoSize: CGSize,
        totalDuration: Double
    ) -> [CALayer] {
        var layers: [CALayer] = []
        let padding: CGFloat = 100
        let textHeight: CGFloat = 200
        let textWidth = videoSize.width - (padding * 2)
        let highlightCGColor = sRGBColor(from: style.highlightColor)
        let strokeCGColor = sRGBColor(from: style.strokeColor)
        let highlighterCGColor = sRGBColor(from: style.textHighlighterColor)

        for caption in captions {
            let containerLayer = CALayer()
            let yOrigin = positionY(for: style.position, videoSize: videoSize, textHeight: textHeight, padding: padding)
            containerLayer.frame = CGRect(x: padding, y: yOrigin, width: textWidth, height: textHeight)

            let startSeconds = CMTimeGetSeconds(caption.startTime)
            let endSeconds = CMTimeGetSeconds(caption.endTime)

            containerLayer.opacity = 0
            containerLayer.add(makeOpacityAnimation(start: startSeconds, end: endSeconds, totalDuration: totalDuration), forKey: "opacity")

            let words = caption.words.isEmpty
                ? [TimedWord(text: caption.text, startTime: caption.startTime, endTime: caption.endTime)]
                : caption.words

            let font = NSFont(name: style.fontName, size: style.fontSize) ?? NSFont.boldSystemFont(ofSize: style.fontSize)
            let wordSpacing: CGFloat = style.fontSize * 0.3
            var wordWidths: [CGFloat] = []
            var totalWordsWidth: CGFloat = 0

            for word in words {
                let attrs: [NSAttributedString.Key: Any] = [.font: font]
                let size = (word.text as NSString).size(withAttributes: attrs)
                wordWidths.append(size.width)
                totalWordsWidth += size.width
            }
            totalWordsWidth += wordSpacing * CGFloat(max(0, words.count - 1))

            var xOffset = max(0, (textWidth - totalWordsWidth) / 2)
            let wordHeight = style.fontSize * 1.3
            let verticalPadding: CGFloat = (textHeight - wordHeight) / 2

            for (index, word) in words.enumerated() {
                let wordSize = CGSize(width: wordWidths[index] + 4, height: wordHeight)

                let wordLayer = CALayer()
                wordLayer.frame = CGRect(x: xOffset, y: verticalPadding, width: wordSize.width, height: wordSize.height)
                wordLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                wordLayer.position = CGPoint(x: xOffset + wordSize.width / 2, y: verticalPadding + wordSize.height / 2)

                if let img = renderTextImage(
                    text: word.text, fontName: style.fontName, fontSize: style.fontSize,
                    textColor: highlightCGColor, size: wordSize, alignment: .center,
                    strokeColor: strokeCGColor, strokeWidth: style.strokeWidth,
                    highlighterColor: highlighterCGColor
                ) {
                    wordLayer.contents = img
                }

                let wordStart = CMTimeGetSeconds(word.startTime)

                wordLayer.transform = CATransform3DMakeScale(0, 0, 1)

                let scaleAnimation = CAKeyframeAnimation(keyPath: "transform.scale")
                scaleAnimation.values = [0, 0, 1.2, 1.0]
                scaleAnimation.keyTimes = [
                    0,
                    NSNumber(value: max(0, wordStart - 0.01) / totalDuration),
                    NSNumber(value: min(1.0, (wordStart + 0.08) / totalDuration)),
                    NSNumber(value: min(1.0, (wordStart + 0.15) / totalDuration))
                ]
                scaleAnimation.duration = totalDuration
                scaleAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
                scaleAnimation.isRemovedOnCompletion = false
                scaleAnimation.fillMode = .forwards
                wordLayer.add(scaleAnimation, forKey: "transform.scale")

                containerLayer.addSublayer(wordLayer)
                xOffset += wordWidths[index] + wordSpacing
            }

            layers.append(containerLayer)
        }
        return layers
    }

    // MARK: - Boxed

    private func buildBoxedLayers(
        captions: [TimedCaption],
        style: CaptionStyle,
        videoSize: CGSize,
        totalDuration: Double
    ) -> [CALayer] {
        var layers: [CALayer] = []
        let padding: CGFloat = 100
        let textHeight: CGFloat = 200
        let textWidth = videoSize.width - (padding * 2)
        let textCGColor = sRGBColor(from: style.textColor)
        let strokeCGColor = sRGBColor(from: style.strokeColor)
        let highlighterCGColor = sRGBColor(from: style.textHighlighterColor)

        for caption in captions {
            let containerLayer = CALayer()
            let yOrigin = positionY(for: style.position, videoSize: videoSize, textHeight: textHeight, padding: padding)
            containerLayer.frame = CGRect(x: padding, y: yOrigin, width: textWidth, height: textHeight)

            let startSeconds = CMTimeGetSeconds(caption.startTime)
            let endSeconds = CMTimeGetSeconds(caption.endTime)

            containerLayer.opacity = 0
            containerLayer.add(makeOpacityAnimation(start: startSeconds, end: endSeconds, totalDuration: totalDuration), forKey: "opacity")

            let words = caption.words.isEmpty
                ? [TimedWord(text: caption.text, startTime: caption.startTime, endTime: caption.endTime)]
                : caption.words

            let font = NSFont(name: style.fontName, size: style.fontSize) ?? NSFont.boldSystemFont(ofSize: style.fontSize)
            let wordSpacing: CGFloat = style.fontSize * 0.25
            let boxPadding: CGFloat = 12
            var wordWidths: [CGFloat] = []
            var totalWordsWidth: CGFloat = 0

            for word in words {
                let attrs: [NSAttributedString.Key: Any] = [.font: font]
                let size = (word.text as NSString).size(withAttributes: attrs)
                wordWidths.append(size.width)
                totalWordsWidth += size.width + (boxPadding * 2)
            }
            totalWordsWidth += wordSpacing * CGFloat(max(0, words.count - 1))

            var xOffset = max(0, (textWidth - totalWordsWidth) / 2)
            let wordHeight = style.fontSize * 1.3
            let verticalPadding: CGFloat = (textHeight - wordHeight - boxPadding * 2) / 2

            for (index, word) in words.enumerated() {
                let boxWidth = wordWidths[index] + boxPadding * 2
                let boxHeight = wordHeight + boxPadding * 2

                let boxLayer = CALayer()
                boxLayer.frame = CGRect(x: xOffset, y: verticalPadding, width: boxWidth, height: boxHeight)
                boxLayer.backgroundColor = sRGBColor(from: style.backgroundColor)
                boxLayer.cornerRadius = 8

                let wordLayer = CALayer()
                wordLayer.frame = CGRect(x: 0, y: boxPadding, width: boxWidth, height: wordHeight)
                let wordSize = CGSize(width: boxWidth, height: wordHeight)
                if let img = renderTextImage(
                    text: word.text, fontName: style.fontName, fontSize: style.fontSize,
                    textColor: textCGColor, size: wordSize, alignment: .center,
                    strokeColor: strokeCGColor, strokeWidth: style.strokeWidth,
                    highlighterColor: highlighterCGColor
                ) {
                    wordLayer.contents = img
                }

                boxLayer.addSublayer(wordLayer)
                containerLayer.addSublayer(boxLayer)
                xOffset += boxWidth + wordSpacing
            }

            layers.append(containerLayer)
        }
        return layers
    }

    // MARK: - Position Helper

    private func positionY(for position: CaptionPosition, videoSize: CGSize, textHeight: CGFloat, padding: CGFloat) -> CGFloat {
        switch position {
        case .bottom:
            return padding
        case .center:
            return (videoSize.height - textHeight) / 2
        case .top:
            return videoSize.height - padding - textHeight
        }
    }
}
