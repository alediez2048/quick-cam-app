import AVFoundation
import CoreImage
import CoreVideo

class ScreenCameraCompositor: NSObject, AVVideoCompositing {
    let sourcePixelBufferAttributes: [String: Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    let requiredPixelBufferAttributesForRenderContext: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    private let renderContext = CIContext(options: [.useSoftwareRenderer: false])
    private var renderSize: CGSize = .zero

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderSize = newRenderContext.size
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? ScreenCameraCompositionInstruction else {
            request.finish(with: NSError(domain: "ScreenCameraCompositor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid instruction"]))
            return
        }

        let outputSize = instruction.outputSize

        guard let screenBuffer = request.sourceFrame(byTrackID: instruction.screenTrackID) else {
            request.finish(with: NSError(domain: "ScreenCameraCompositor", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing screen frame"]))
            return
        }

        let cameraBuffer = request.sourceFrame(byTrackID: instruction.cameraTrackID)

        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "ScreenCameraCompositor", code: -3, userInfo: [NSLocalizedDescriptionKey: "Cannot create output buffer"]))
            return
        }

        CVPixelBufferLockBaseAddress(outputBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(outputBuffer, []) }

        let width = CVPixelBufferGetWidth(outputBuffer)
        let height = CVPixelBufferGetHeight(outputBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(outputBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(outputBuffer) else {
            request.finish(with: NSError(domain: "ScreenCameraCompositor", code: -4, userInfo: nil))
            return
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            request.finish(with: NSError(domain: "ScreenCameraCompositor", code: -5, userInfo: nil))
            return
        }

        // Clear to black
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Draw screen - fill entire output
        let screenImage = CIImage(cvPixelBuffer: screenBuffer)
        if let screenCGImage = renderContext.createCGImage(screenImage, from: screenImage.extent) {
            let screenRect = aspectFillRect(
                imageSize: CGSize(width: screenCGImage.width, height: screenCGImage.height),
                containerRect: CGRect(x: 0, y: 0, width: width, height: height)
            )
            context.draw(screenCGImage, in: screenRect)
        }

        // Draw camera bubble if available
        if let cameraBuffer = cameraBuffer {
            let cameraImage = CIImage(cvPixelBuffer: cameraBuffer)
            if let cameraCGImage = renderContext.createCGImage(cameraImage, from: cameraImage.extent) {
                let bubbleFraction: CGFloat = 0.25
                let bubbleSize = min(CGFloat(width), CGFloat(height)) * bubbleFraction
                let padding: CGFloat = CGFloat(width) * 0.03

                let bubbleRect = bubbleRect(
                    position: instruction.bubblePosition,
                    containerWidth: CGFloat(width),
                    containerHeight: CGFloat(height),
                    bubbleSize: bubbleSize,
                    padding: padding
                )

                // Save state for clipping
                context.saveGState()

                if instruction.layout == .circleBubble {
                    let path = CGPath(ellipseIn: bubbleRect, transform: nil)
                    context.addPath(path)
                    context.clip()
                } else {
                    let path = CGPath(roundedRect: bubbleRect, cornerWidth: bubbleSize * 0.1, cornerHeight: bubbleSize * 0.1, transform: nil)
                    context.addPath(path)
                    context.clip()
                }

                // Draw camera image filling bubble
                let cameraDrawRect = aspectFillRect(
                    imageSize: CGSize(width: cameraCGImage.width, height: cameraCGImage.height),
                    containerRect: bubbleRect
                )
                context.draw(cameraCGImage, in: cameraDrawRect)

                context.restoreGState()

                // Draw border
                context.saveGState()
                context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9))
                context.setLineWidth(3)
                if instruction.layout == .circleBubble {
                    context.addEllipse(in: bubbleRect.insetBy(dx: 1.5, dy: 1.5))
                } else {
                    let borderPath = CGPath(roundedRect: bubbleRect.insetBy(dx: 1.5, dy: 1.5), cornerWidth: bubbleSize * 0.1, cornerHeight: bubbleSize * 0.1, transform: nil)
                    context.addPath(borderPath)
                }
                context.strokePath()
                context.restoreGState()
            }
        }

        request.finish(withComposedVideoFrame: outputBuffer)
    }

    func cancelAllPendingVideoCompositionRequests() {}

    // MARK: - Helpers

    private func bubbleRect(
        position: CameraBubblePosition,
        containerWidth: CGFloat,
        containerHeight: CGFloat,
        bubbleSize: CGFloat,
        padding: CGFloat
    ) -> CGRect {
        // CGContext has origin at bottom-left
        switch position {
        case .topLeft:
            return CGRect(x: padding, y: containerHeight - padding - bubbleSize, width: bubbleSize, height: bubbleSize)
        case .topRight:
            return CGRect(x: containerWidth - padding - bubbleSize, y: containerHeight - padding - bubbleSize, width: bubbleSize, height: bubbleSize)
        case .bottomLeft:
            return CGRect(x: padding, y: padding, width: bubbleSize, height: bubbleSize)
        case .bottomRight:
            return CGRect(x: containerWidth - padding - bubbleSize, y: padding, width: bubbleSize, height: bubbleSize)
        }
    }

    private func aspectFillRect(imageSize: CGSize, containerRect: CGRect) -> CGRect {
        let scaleX = containerRect.width / imageSize.width
        let scaleY = containerRect.height / imageSize.height
        let scale = max(scaleX, scaleY)
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let x = containerRect.origin.x + (containerRect.width - scaledWidth) / 2
        let y = containerRect.origin.y + (containerRect.height - scaledHeight) / 2
        return CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
    }
}
