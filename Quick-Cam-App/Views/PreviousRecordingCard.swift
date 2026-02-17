import SwiftUI

struct PreviousRecordingCard: View {
    let video: RecordedVideo
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                // Thumbnail
                ZStack {
                    if let thumbnail = video.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(9/16, contentMode: .fill)
                            .frame(height: 120)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .aspectRatio(9/16, contentMode: .fill)
                            .frame(height: 120)
                            .overlay(
                                Image(systemName: "video")
                                    .foregroundColor(.gray)
                            )
                    }

                    // Play icon overlay
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white.opacity(0.8))

                    // Delete button
                    if isHovering {
                        VStack {
                            HStack {
                                Spacer()
                                Button(action: onDelete) {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white)
                                        .padding(6)
                                        .background(Color.red)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .padding(4)
                            }
                            Spacer()
                        }
                    }
                }
                .cornerRadius(8)

                // Title and date
                Text(video.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(video.date, style: .date)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
