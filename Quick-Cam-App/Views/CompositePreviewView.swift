import SwiftUI

struct CompositePreviewView: View {
    @ObservedObject var cameraViewModel: CameraViewModel
    let screenImage: CGImage?
    let layout: ScreenCameraLayout
    let bubblePosition: CameraBubblePosition

    var body: some View {
        ZStack {
            Color.black

            switch layout {
            case .sideBySide:
                sideBySideLayout
            case .circleBubble:
                bubbleLayout(isCircle: true)
            case .squareBubble:
                bubbleLayout(isCircle: false)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .cornerRadius(12)
    }

    @ViewBuilder
    private var sideBySideLayout: some View {
        HStack(spacing: 0) {
            // Screen on the left
            if let screenImage = screenImage {
                Image(decorative: screenImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "display")
                            .font(.system(size: 30))
                            .foregroundColor(.gray)
                    )
            }

            // Camera on the right
            CameraPreviewView(cameraViewModel: cameraViewModel)
        }
    }

    @ViewBuilder
    private func bubbleLayout(isCircle: Bool) -> some View {
        ZStack {
            // Screen fills the background
            if let screenImage = screenImage {
                Image(decorative: screenImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "display")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                    )
            }

            // Camera bubble overlay
            GeometryReader { geometry in
                let bubbleSize = min(geometry.size.width, geometry.size.height) * 0.28
                let padding: CGFloat = 12
                let position = bubbleOffset(containerSize: geometry.size, bubbleSize: bubbleSize, padding: padding)

                CameraPreviewView(cameraViewModel: cameraViewModel)
                    .frame(width: bubbleSize, height: bubbleSize)
                    .clipShape(isCircle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12)))
                    .overlay(
                        Group {
                            if isCircle {
                                Circle().stroke(Color.white, lineWidth: 2)
                            } else {
                                RoundedRectangle(cornerRadius: 12).stroke(Color.white, lineWidth: 2)
                            }
                        }
                    )
                    .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                    .position(position)
            }
            .allowsHitTesting(false)
        }
        .clipped()
    }

    private func bubbleOffset(containerSize: CGSize, bubbleSize: CGFloat, padding: CGFloat) -> CGPoint {
        let halfBubble = bubbleSize / 2
        switch bubblePosition {
        case .topLeft:
            return CGPoint(x: padding + halfBubble, y: padding + halfBubble)
        case .topRight:
            return CGPoint(x: containerSize.width - padding - halfBubble, y: padding + halfBubble)
        case .bottomLeft:
            return CGPoint(x: padding + halfBubble, y: containerSize.height - padding - halfBubble)
        case .bottomRight:
            return CGPoint(x: containerSize.width - padding - halfBubble, y: containerSize.height - padding - halfBubble)
        }
    }
}
