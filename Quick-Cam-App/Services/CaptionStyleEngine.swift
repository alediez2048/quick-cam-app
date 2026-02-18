import AVFoundation
import AppKit
import QuartzCore

class CaptionStyleEngine {

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

        for caption in captions {
            let textLayer = CATextLayer()
            textLayer.string = caption.text
            textLayer.font = style.fontName as CFTypeRef
            textLayer.fontSize = style.fontSize
            textLayer.foregroundColor = style.textColor.cgColor
            textLayer.backgroundColor = style.backgroundColor.cgColor
            textLayer.alignmentMode = .center
            textLayer.contentsScale = 2.0
            textLayer.isWrapped = true
            textLayer.truncationMode = .end

            let yOrigin = positionY(for: style.position, videoSize: videoSize, textHeight: textHeight, padding: padding)
            textLayer.frame = CGRect(x: padding, y: yOrigin, width: textWidth, height: textHeight)

            let startSeconds = CMTimeGetSeconds(caption.startTime)
            let endSeconds = CMTimeGetSeconds(caption.endTime)

            textLayer.opacity = 0
            let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
            opacityAnimation.values = [0, 0, 1, 1, 0, 0]
            opacityAnimation.keyTimes = [
                0,
                NSNumber(value: max(0, startSeconds - 0.01) / totalDuration),
                NSNumber(value: startSeconds / totalDuration),
                NSNumber(value: endSeconds / totalDuration),
                NSNumber(value: min(totalDuration, endSeconds + 0.01) / totalDuration),
                1
            ]
            opacityAnimation.duration = totalDuration
            opacityAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
            opacityAnimation.isRemovedOnCompletion = false
            textLayer.add(opacityAnimation, forKey: "opacity")

            layers.append(textLayer)
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

        for caption in captions {
            let containerLayer = CALayer()
            let yOrigin = positionY(for: style.position, videoSize: videoSize, textHeight: textHeight, padding: padding)
            containerLayer.frame = CGRect(x: padding, y: yOrigin, width: textWidth, height: textHeight)
            containerLayer.backgroundColor = style.backgroundColor.cgColor

            let startSeconds = CMTimeGetSeconds(caption.startTime)
            let endSeconds = CMTimeGetSeconds(caption.endTime)

            containerLayer.opacity = 0
            let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
            opacityAnimation.values = [0, 0, 1, 1, 0, 0]
            opacityAnimation.keyTimes = [
                0,
                NSNumber(value: max(0, startSeconds - 0.01) / totalDuration),
                NSNumber(value: startSeconds / totalDuration),
                NSNumber(value: endSeconds / totalDuration),
                NSNumber(value: min(totalDuration, endSeconds + 0.01) / totalDuration),
                1
            ]
            opacityAnimation.duration = totalDuration
            opacityAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
            opacityAnimation.isRemovedOnCompletion = false
            containerLayer.add(opacityAnimation, forKey: "opacity")

            let words = caption.words.isEmpty
                ? [TimedWord(text: caption.text, startTime: caption.startTime, endTime: caption.endTime)]
                : caption.words

            let font = NSFont(name: style.fontName, size: style.fontSize) ?? NSFont.boldSystemFont(ofSize: style.fontSize)
            var xOffset: CGFloat = 0
            let wordSpacing: CGFloat = style.fontSize * 0.3
            let verticalPadding: CGFloat = (textHeight - style.fontSize * 1.3) / 2

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
                let wordLayer = CATextLayer()
                wordLayer.string = word.text
                wordLayer.font = style.fontName as CFTypeRef
                wordLayer.fontSize = style.fontSize
                wordLayer.foregroundColor = style.textColor.cgColor
                wordLayer.alignmentMode = .left
                wordLayer.contentsScale = 2.0
                wordLayer.frame = CGRect(x: xOffset, y: verticalPadding, width: wordWidths[index] + 4, height: style.fontSize * 1.3)

                let wordStart = CMTimeGetSeconds(word.startTime)
                let wordEnd = CMTimeGetSeconds(word.endTime)

                let colorAnimation = CAKeyframeAnimation(keyPath: "foregroundColor")
                colorAnimation.values = [
                    style.textColor.cgColor,
                    style.textColor.cgColor,
                    style.highlightColor.cgColor,
                    style.highlightColor.cgColor,
                    style.textColor.cgColor,
                    style.textColor.cgColor
                ]
                colorAnimation.keyTimes = [
                    0,
                    NSNumber(value: max(0, wordStart - 0.01) / totalDuration),
                    NSNumber(value: wordStart / totalDuration),
                    NSNumber(value: wordEnd / totalDuration),
                    NSNumber(value: min(totalDuration, wordEnd + 0.01) / totalDuration),
                    1
                ]
                colorAnimation.duration = totalDuration
                colorAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
                colorAnimation.isRemovedOnCompletion = false
                wordLayer.add(colorAnimation, forKey: "foregroundColor")

                containerLayer.addSublayer(wordLayer)
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

        for caption in captions {
            let containerLayer = CALayer()
            let yOrigin = positionY(for: style.position, videoSize: videoSize, textHeight: textHeight, padding: padding)
            containerLayer.frame = CGRect(x: padding, y: yOrigin, width: textWidth, height: textHeight)

            let startSeconds = CMTimeGetSeconds(caption.startTime)
            let endSeconds = CMTimeGetSeconds(caption.endTime)

            containerLayer.opacity = 0
            let containerOpacity = CAKeyframeAnimation(keyPath: "opacity")
            containerOpacity.values = [0, 0, 1, 1, 0, 0]
            containerOpacity.keyTimes = [
                0,
                NSNumber(value: max(0, startSeconds - 0.01) / totalDuration),
                NSNumber(value: startSeconds / totalDuration),
                NSNumber(value: endSeconds / totalDuration),
                NSNumber(value: min(totalDuration, endSeconds + 0.01) / totalDuration),
                1
            ]
            containerOpacity.duration = totalDuration
            containerOpacity.beginTime = AVCoreAnimationBeginTimeAtZero
            containerOpacity.isRemovedOnCompletion = false
            containerLayer.add(containerOpacity, forKey: "opacity")

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
            let verticalPadding: CGFloat = (textHeight - style.fontSize * 1.3) / 2

            for (index, word) in words.enumerated() {
                let wordLayer = CATextLayer()
                wordLayer.string = word.text
                wordLayer.font = style.fontName as CFTypeRef
                wordLayer.fontSize = style.fontSize
                wordLayer.foregroundColor = style.highlightColor.cgColor
                wordLayer.alignmentMode = .center
                wordLayer.contentsScale = 2.0
                wordLayer.frame = CGRect(x: xOffset, y: verticalPadding, width: wordWidths[index] + 4, height: style.fontSize * 1.3)
                wordLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                wordLayer.position = CGPoint(x: xOffset + (wordWidths[index] + 4) / 2, y: verticalPadding + style.fontSize * 1.3 / 2)

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

        for caption in captions {
            let containerLayer = CALayer()
            let yOrigin = positionY(for: style.position, videoSize: videoSize, textHeight: textHeight, padding: padding)
            containerLayer.frame = CGRect(x: padding, y: yOrigin, width: textWidth, height: textHeight)

            let startSeconds = CMTimeGetSeconds(caption.startTime)
            let endSeconds = CMTimeGetSeconds(caption.endTime)

            containerLayer.opacity = 0
            let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
            opacityAnimation.values = [0, 0, 1, 1, 0, 0]
            opacityAnimation.keyTimes = [
                0,
                NSNumber(value: max(0, startSeconds - 0.01) / totalDuration),
                NSNumber(value: startSeconds / totalDuration),
                NSNumber(value: endSeconds / totalDuration),
                NSNumber(value: min(totalDuration, endSeconds + 0.01) / totalDuration),
                1
            ]
            opacityAnimation.duration = totalDuration
            opacityAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
            opacityAnimation.isRemovedOnCompletion = false
            containerLayer.add(opacityAnimation, forKey: "opacity")

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
                let boxLayer = CALayer()
                let boxWidth = wordWidths[index] + boxPadding * 2
                let boxHeight = wordHeight + boxPadding * 2
                boxLayer.frame = CGRect(x: xOffset, y: verticalPadding, width: boxWidth, height: boxHeight)
                boxLayer.backgroundColor = style.backgroundColor.cgColor
                boxLayer.cornerRadius = 8

                let wordLayer = CATextLayer()
                wordLayer.string = word.text
                wordLayer.font = style.fontName as CFTypeRef
                wordLayer.fontSize = style.fontSize
                wordLayer.foregroundColor = style.textColor.cgColor
                wordLayer.alignmentMode = .center
                wordLayer.contentsScale = 2.0
                wordLayer.frame = CGRect(x: 0, y: boxPadding, width: boxWidth, height: wordHeight)

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
