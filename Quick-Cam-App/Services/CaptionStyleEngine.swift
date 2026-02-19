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

    /// Pre-render text into a CGImage using Core Text.
    /// CATextLayer doesn't reliably render in AVVideoCompositionCoreAnimationTool's offscreen context,
    /// so we draw text into a bitmap and use it as a plain CALayer's contents.
    private func renderTextImage(
        text: String,
        fontName: String,
        fontSize: CGFloat,
        textColor: CGColor,
        size: CGSize,
        alignment: CTTextAlignment = .center
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

        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): textColor,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle
        ]

        let attrString = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attrString as CFAttributedString)

        // Measure text height for vertical centering
        let constraintSize = CGSize(width: size.width, height: CGFloat.greatestFiniteMagnitude)
        let textSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil, constraintSize, nil)

        // CTFrame draws in CG coordinates (y-up): first line starts at top of path rect
        let yOffset = max(0, (size.height - textSize.height) / 2)
        let textRect = CGRect(x: 0, y: yOffset, width: size.width, height: textSize.height)
        let path = CGMutablePath()
        path.addRect(textRect)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)

        CTFrameDraw(frame, ctx)

        return ctx.makeImage()
    }

    /// Render text with a stroke (outline) behind fill using Core Text.
    /// Completely separate from renderTextImage to avoid breaking the default path.
    private func renderTextImageWithStroke(
        text: String,
        fontName: String,
        fontSize: CGFloat,
        textColor: CGColor,
        strokeColor: CGColor,
        strokeWidth: CGFloat,
        size: CGSize,
        alignment: CTTextAlignment = .center
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

        // Stroke pass: positive kCTStrokeWidthAttributeName draws stroke only (no fill)
        let strokeAttributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): strokeColor,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle,
            NSAttributedString.Key(kCTStrokeWidthAttributeName as String): strokeWidth as CFNumber,
            NSAttributedString.Key(kCTStrokeColorAttributeName as String): strokeColor
        ]

        let fillAttributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): textColor,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle
        ]

        // Measure using fill attributes (no stroke expansion)
        let fillAttrString = NSAttributedString(string: text, attributes: fillAttributes)
        let framesetter = CTFramesetterCreateWithAttributedString(fillAttrString as CFAttributedString)
        let constraintSize = CGSize(width: size.width, height: CGFloat.greatestFiniteMagnitude)
        let textSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil, constraintSize, nil)
        let yOffset = max(0, (size.height - textSize.height) / 2)
        let textRect = CGRect(x: 0, y: yOffset, width: size.width, height: textSize.height)
        let path = CGMutablePath()
        path.addRect(textRect)

        // Draw stroke first (behind)
        let strokeAttrString = NSAttributedString(string: text, attributes: strokeAttributes)
        let strokeFramesetter = CTFramesetterCreateWithAttributedString(strokeAttrString as CFAttributedString)
        let strokeFrame = CTFramesetterCreateFrame(strokeFramesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(strokeFrame, ctx)

        // Draw fill on top
        let fillFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(fillFrame, ctx)

        return ctx.makeImage()
    }

    /// Render text using stroke path if strokeWidth > 0, otherwise use the original renderTextImage.
    private func renderText(
        text: String, style: CaptionStyle, textColor: CGColor, size: CGSize, alignment: CTTextAlignment = .center
    ) -> CGImage? {
        if style.strokeWidth > 0 {
            return renderTextImageWithStroke(
                text: text, fontName: style.fontName, fontSize: style.fontSize,
                textColor: textColor, strokeColor: sRGBColor(from: style.strokeColor),
                strokeWidth: style.strokeWidth, size: size, alignment: alignment
            )
        } else {
            return renderTextImage(
                text: text, fontName: style.fontName, fontSize: style.fontSize,
                textColor: textColor, size: size, alignment: alignment
            )
        }
    }

    /// Create a highlighter background layer with rounded corners.
    /// Returns nil when the highlighter color is fully transparent.
    private func makeHighlighterLayer(frame: CGRect, style: CaptionStyle) -> CALayer? {
        let hlColor = style.textHighlighterColor
        var alpha: CGFloat = 0
        if let converted = hlColor.usingColorSpace(.sRGB) {
            alpha = converted.alphaComponent
        }
        guard alpha > 0.01 else { return nil }

        let layer = CALayer()
        layer.frame = frame
        layer.backgroundColor = sRGBColor(from: hlColor)
        layer.cornerRadius = 6
        return layer
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

        for caption in captions {
            let layer = CALayer()
            let yOrigin = positionY(for: style.position, videoSize: videoSize, textHeight: textHeight, padding: padding)
            layer.frame = CGRect(x: padding, y: yOrigin, width: textWidth, height: textHeight)
            layer.backgroundColor = sRGBColor(from: style.backgroundColor)

            if let hlLayer = makeHighlighterLayer(frame: CGRect(x: 0, y: 0, width: textWidth, height: textHeight), style: style) {
                layer.addSublayer(hlLayer)
            }

            let textLayer = CALayer()
            textLayer.frame = CGRect(x: 0, y: 0, width: textWidth, height: textHeight)
            if let img = renderText(text: caption.text, style: style, textColor: textCGColor, size: CGSize(width: textWidth, height: textHeight)) {
                textLayer.contents = img
            }
            layer.addSublayer(textLayer)

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

                // Highlighter background behind word
                if let hlLayer = makeHighlighterLayer(frame: wordFrame, style: style) {
                    containerLayer.addSublayer(hlLayer)
                }

                // Base word in text color (always visible)
                let baseLayer = CALayer()
                baseLayer.frame = wordFrame
                if let img = renderText(text: word.text, style: style, textColor: textCGColor, size: wordSize, alignment: .left) {
                    baseLayer.contents = img
                }
                containerLayer.addSublayer(baseLayer)

                // Highlight word overlay (fades in/out during word timing)
                let highlightLayer = CALayer()
                highlightLayer.frame = wordFrame
                if let img = renderText(text: word.text, style: style, textColor: highlightCGColor, size: wordSize, alignment: .left) {
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

                // Highlighter background (renders behind contents)
                if let converted = style.textHighlighterColor.usingColorSpace(.sRGB), converted.alphaComponent > 0.01 {
                    wordLayer.backgroundColor = sRGBColor(from: style.textHighlighterColor)
                    wordLayer.cornerRadius = 6
                }

                if let img = renderText(text: word.text, style: style, textColor: highlightCGColor, size: wordSize, alignment: .center) {
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

                // Highlighter behind text within the box
                if let hlLayer = makeHighlighterLayer(frame: CGRect(x: 0, y: boxPadding, width: boxWidth, height: wordHeight), style: style) {
                    boxLayer.addSublayer(hlLayer)
                }

                let wordLayer = CALayer()
                wordLayer.frame = CGRect(x: 0, y: boxPadding, width: boxWidth, height: wordHeight)
                let wordSize = CGSize(width: boxWidth, height: wordHeight)
                if let img = renderText(text: word.text, style: style, textColor: textCGColor, size: wordSize, alignment: .center) {
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
