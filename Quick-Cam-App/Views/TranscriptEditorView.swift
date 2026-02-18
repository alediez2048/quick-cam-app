import SwiftUI
import AVFoundation
import CoreMedia

struct TranscriptEditorView: View {
    let captions: [TimedCaption]
    let player: AVPlayer
    @Binding var deletedWordIndices: Set<Int>

    @State private var observer = TranscriptPlaybackObserver()
    @State private var undoStack: [Set<Int>] = []
    @State private var redoStack: [Set<Int>] = []

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

                Button {
                    undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(undoStack.isEmpty)
                .foregroundColor(undoStack.isEmpty ? .gray.opacity(0.5) : .accentColor)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo (⌘Z)")

                Button {
                    redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(redoStack.isEmpty)
                .foregroundColor(redoStack.isEmpty ? .gray.opacity(0.5) : .accentColor)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help("Redo (⇧⌘Z)")

                if !deletedWordIndices.isEmpty {
                    Button {
                        recordAndApply([])
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
                                            var newSet = deletedWordIndices
                                            newSet.remove(index)
                                            recordAndApply(newSet)
                                        }
                                    } else {
                                        Button("Delete") {
                                            var newSet = deletedWordIndices
                                            newSet.insert(index)
                                            recordAndApply(newSet)
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

    private func recordAndApply(_ newValue: Set<Int>) {
        undoStack.append(deletedWordIndices)
        redoStack.removeAll()
        deletedWordIndices = newValue
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(deletedWordIndices)
        deletedWordIndices = previous
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(deletedWordIndices)
        deletedWordIndices = next
    }
}
