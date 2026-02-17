import SwiftUI

struct PreviousRecordingsSidebar: View {
    let recordings: [RecordedVideo]
    let onSelect: (RecordedVideo) -> Void
    let onDelete: (RecordedVideo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Previous Recordings")
                .font(.headline)
                .foregroundColor(.white)
                .padding()

            if recordings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                    Text("No recordings yet")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(recordings) { video in
                            PreviousRecordingCard(
                                video: video,
                                onSelect: { onSelect(video) },
                                onDelete: { onDelete(video) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color.black.opacity(0.8))
    }
}
