import SwiftUI
import AVFoundation
import CoreMedia

struct TranscriptEditorView: View {
    @Binding var captions: [TimedCaption]
    let player: AVPlayer
    @Binding var deletedWordIndices: Set<Int>

    @State private var observer = TranscriptPlaybackObserver()
    @State private var undoStack: [EditSnapshot] = []
    @State private var redoStack: [EditSnapshot] = []
    @State private var editingWordIndex: Int? = nil
    @State private var editingText: String = ""
    @FocusState private var isEditFieldFocused: Bool

    private struct EditSnapshot {
        let captions: [TimedCaption]
        let deletedWordIndices: Set<Int>
    }

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
                        recordAndApply(newDeletedIndices: [])
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
                            let isEditing = editingWordIndex == index

                            if isEditing {
                                TextField("", text: $editingText, onCommit: {
                                    commitEdit()
                                })
                                .font(.system(size: 13))
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(4)
                                .frame(minWidth: 30)
                                .fixedSize()
                                .focused($isEditFieldFocused)
                                .onExitCommand {
                                    cancelEdit()
                                }
                                .id(index)
                            } else {
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
                                    .onTapGesture(count: 2) {
                                        if !isDeleted {
                                            beginEditing(index: index, word: word)
                                        }
                                    }
                                    .contextMenu {
                                        if isDeleted {
                                            Button("Restore") {
                                                var newSet = deletedWordIndices
                                                newSet.remove(index)
                                                recordAndApply(newDeletedIndices: newSet)
                                            }
                                        } else {
                                            Button("Edit Word") {
                                                beginEditing(index: index, word: word)
                                            }

                                            Button("Delete") {
                                                var newSet = deletedWordIndices
                                                newSet.insert(index)
                                                recordAndApply(newDeletedIndices: newSet)
                                            }

                                            if let loc = captionLocation(for: index), loc.wordIndex > 0 {
                                                Divider()
                                                Button("Split Caption Here") {
                                                    splitCaption(at: index)
                                                }
                                            }

                                            if let loc = captionLocation(for: index),
                                               loc.captionIndex < captions.count - 1 {
                                                Button("Merge with Next Caption") {
                                                    mergeWithNextCaption(at: index)
                                                }
                                            }
                                        }
                                    }
                                    .id(index)
                            }
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
        .onChange(of: captions.count) { _, _ in
            observer.detach(from: player)
            observer.attach(to: player, words: allWords)
        }
    }

    // MARK: - Editing

    private func beginEditing(index: Int, word: TimedWord) {
        editingWordIndex = index
        editingText = word.text
        isEditFieldFocused = true
    }

    private func commitEdit() {
        guard let flatIndex = editingWordIndex else { return }
        let trimmed = editingText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            cancelEdit()
            return
        }

        guard let loc = captionLocation(for: flatIndex) else {
            cancelEdit()
            return
        }

        let oldWord = captions[loc.captionIndex].words[loc.wordIndex]
        guard trimmed != oldWord.text else {
            cancelEdit()
            return
        }

        var newCaptions = captions
        newCaptions[loc.captionIndex].words[loc.wordIndex].text = trimmed
        newCaptions[loc.captionIndex].text = newCaptions[loc.captionIndex].words
            .map { $0.text }
            .joined(separator: " ")

        recordAndApply(newCaptions: newCaptions, newDeletedIndices: deletedWordIndices)
        editingWordIndex = nil
        editingText = ""
    }

    private func cancelEdit() {
        editingWordIndex = nil
        editingText = ""
    }

    // MARK: - Split & Merge

    private func splitCaption(at flatIndex: Int) {
        guard let loc = captionLocation(for: flatIndex), loc.wordIndex > 0 else { return }

        var newCaptions = captions
        let original = newCaptions[loc.captionIndex]
        let firstWords = Array(original.words[..<loc.wordIndex])
        let secondWords = Array(original.words[loc.wordIndex...])

        let firstCaption = TimedCaption(
            text: firstWords.map { $0.text }.joined(separator: " "),
            startTime: original.startTime,
            endTime: secondWords.first!.startTime,
            words: firstWords
        )
        let secondCaption = TimedCaption(
            text: secondWords.map { $0.text }.joined(separator: " "),
            startTime: secondWords.first!.startTime,
            endTime: original.endTime,
            words: secondWords
        )

        newCaptions.replaceSubrange(loc.captionIndex...loc.captionIndex, with: [firstCaption, secondCaption])
        recordAndApply(newCaptions: newCaptions, newDeletedIndices: deletedWordIndices)
    }

    private func mergeWithNextCaption(at flatIndex: Int) {
        guard let loc = captionLocation(for: flatIndex),
              loc.captionIndex < captions.count - 1 else { return }

        var newCaptions = captions
        let current = newCaptions[loc.captionIndex]
        let next = newCaptions[loc.captionIndex + 1]

        let mergedWords = current.words + next.words
        let merged = TimedCaption(
            text: mergedWords.map { $0.text }.joined(separator: " "),
            startTime: current.startTime,
            endTime: next.endTime,
            words: mergedWords
        )

        newCaptions.replaceSubrange(loc.captionIndex...(loc.captionIndex + 1), with: [merged])
        recordAndApply(newCaptions: newCaptions, newDeletedIndices: deletedWordIndices)
    }

    // MARK: - Helpers

    private func captionLocation(for flatIndex: Int) -> (captionIndex: Int, wordIndex: Int)? {
        var offset = 0
        for (ci, caption) in captions.enumerated() {
            if flatIndex < offset + caption.words.count {
                return (ci, flatIndex - offset)
            }
            offset += caption.words.count
        }
        return nil
    }

    // MARK: - Undo / Redo

    private func recordAndApply(newCaptions: [TimedCaption], newDeletedIndices: Set<Int>) {
        undoStack.append(EditSnapshot(captions: captions, deletedWordIndices: deletedWordIndices))
        redoStack.removeAll()
        captions = newCaptions
        deletedWordIndices = newDeletedIndices
    }

    private func recordAndApply(newDeletedIndices: Set<Int>) {
        recordAndApply(newCaptions: captions, newDeletedIndices: newDeletedIndices)
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(EditSnapshot(captions: captions, deletedWordIndices: deletedWordIndices))
        captions = previous.captions
        deletedWordIndices = previous.deletedWordIndices
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(EditSnapshot(captions: captions, deletedWordIndices: deletedWordIndices))
        captions = next.captions
        deletedWordIndices = next.deletedWordIndices
    }
}
