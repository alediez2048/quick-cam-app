import SwiftUI

struct ScreenPermissionView: View {
    let onRequestPermission: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(.yellow)

            Text("Screen Recording Permission Required")
                .font(.headline)
                .foregroundColor(.white)

            Text("Quick Cam needs permission to record your screen. Grant access in System Settings.")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button(action: onRequestPermission) {
                Text("Open System Settings")
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}
