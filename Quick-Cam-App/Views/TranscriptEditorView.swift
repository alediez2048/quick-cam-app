import SwiftUI
import AVFoundation
import CoreMedia

struct TranscriptEditorView: View {
    let captions: [TimedCaption]
    let player: AVPlayer
    @Binding var deletedWordIndices: Set<Int>

    @State private var observer = TranscriptPlaybackObserver()

    private var allWords: [TimedWord] {
        captions.flatMap { $0.words }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TRANSCRIPT")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                if !deletedWordIndices.isEmpty {
                    Button {
                        deletedWordIndices.removeAll()
                    } label: {
                        Text("Restore All (\(deletedWordIndices.count))")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("\(allWords.count) words")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    FlowLayout(spacing: 4) {
                        ForEach(Array(allWords.enumerated()), id: \.offset) { index, word in
                            let isDeleted = deletedWordIndices.contains(index)
                            let isCurrent = index == observer.currentWordIndex

                            Text(word.text)
                                .font(.system(size: 13))
                                .strikethrough(isDeleted, color: .red)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .foregroundColor(
                                    isDeleted ? .gray.opacity(0.5)
                                    : isCurrent ? .black
                                    : .white
                                )
                                .background(
                                    isCurrent && !isDeleted
                                        ? Color.accentColor
                                        : Color.clear
                                )
                                .cornerRadius(4)
                                .onTapGesture {
                                    player.seek(
                                        to: word.startTime,
                                        toleranceBefore: .zero,
                                        toleranceAfter: .zero
                                    )
                                }
                                .contextMenu {
                                    if isDeleted {
                                        Button("Restore") {
                                            deletedWordIndices.remove(index)
                                        }
                                    } else {
                                        Button("Delete") {
                                            deletedWordIndices.insert(index)
                                        }
                                    }
                                }
                                .id(index)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 150)
                .onChange(of: observer.currentWordIndex) { _, newIndex in
                    if let newIndex {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.top, 8)
        .onAppear {
            observer.attach(to: player, words: allWords)
        }
        .onDisappear {
            observer.detach(from: player)
        }
    }
}
