import SwiftUI

struct CameraBubblePositionPicker: View {
    @Binding var selectedPosition: CameraBubblePosition

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera Position")
                .font(.caption)
                .foregroundColor(.gray)

            HStack(spacing: 8) {
                ForEach(CameraBubblePosition.allCases) { position in
                    Button(action: {
                        selectedPosition = position
                    }) {
                        positionPreview(position)
                            .frame(width: 48, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedPosition == position ? Color.accentColor.opacity(0.3) : Color.white.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selectedPosition == position ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func positionPreview(_ position: CameraBubblePosition) -> some View {
        GeometryReader { geometry in
            ZStack {
                // Screen background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: geometry.size.width - 8, height: geometry.size.height - 8)

                // Camera bubble indicator
                let dotSize: CGFloat = 10
                let inset: CGFloat = 8

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: dotSize, height: dotSize)
                    .position(dotPosition(position, in: geometry.size, dotSize: dotSize, inset: inset))
            }
        }
    }

    private func dotPosition(_ position: CameraBubblePosition, in size: CGSize, dotSize: CGFloat, inset: CGFloat) -> CGPoint {
        let halfDot = dotSize / 2
        switch position {
        case .topLeft:
            return CGPoint(x: inset + halfDot, y: inset + halfDot)
        case .topRight:
            return CGPoint(x: size.width - inset - halfDot, y: inset + halfDot)
        case .bottomLeft:
            return CGPoint(x: inset + halfDot, y: size.height - inset - halfDot)
        case .bottomRight:
            return CGPoint(x: size.width - inset - halfDot, y: size.height - inset - halfDot)
        }
    }
}
