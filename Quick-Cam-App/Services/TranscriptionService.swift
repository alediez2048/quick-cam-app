import Speech
import CoreMedia

class TranscriptionService {
    func transcribeAudio(from videoURL: URL, locale: Locale = Locale(identifier: "en-US")) async -> [TimedCaption] {
        let speechRecognizer = SFSpeechRecognizer(locale: locale)
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            return []
        }

        return await withCheckedContinuation { continuation in
            var hasResumed = false

            SFSpeechRecognizer.requestAuthorization { status in
                guard status == .authorized else {
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(returning: [])
                    return
                }

                let request = SFSpeechURLRecognitionRequest(url: videoURL)
                request.shouldReportPartialResults = false

                recognizer.recognitionTask(with: request) { result, error in
                    guard !hasResumed else { return }

                    guard let result = result, result.isFinal else {
                        if error != nil {
                            hasResumed = true
                            continuation.resume(returning: [])
                        }
                        return
                    }

                    let segments = result.bestTranscription.segments
                    let formattedWords = result.bestTranscription.formattedString
                        .components(separatedBy: .whitespaces)
                        .filter { !$0.isEmpty }

                    // Map punctuated words from formattedString back to segments by index
                    var punctuatedTexts: [String] = []
                    for i in 0..<segments.count {
                        if i < formattedWords.count {
                            punctuatedTexts.append(formattedWords[i])
                        } else {
                            punctuatedTexts.append(segments[i].substring)
                        }
                    }

                    let maxWordsPerCaption = 12
                    var captions: [TimedCaption] = []
                    var currentWords: [String] = []
                    var currentTimedWords: [TimedWord] = []
                    var segmentStart: CMTime?

                    for (i, segment) in segments.enumerated() {
                        let punctuatedText = punctuatedTexts[i]

                        if segmentStart == nil {
                            segmentStart = CMTime(seconds: segment.timestamp, preferredTimescale: 600)
                        }

                        currentWords.append(punctuatedText)
                        currentTimedWords.append(TimedWord(
                            text: punctuatedText,
                            startTime: CMTime(seconds: segment.timestamp, preferredTimescale: 600),
                            endTime: CMTime(seconds: segment.timestamp + segment.duration, preferredTimescale: 600)
                        ))

                        let endsWithSentencePunctuation = punctuatedText.last == "."
                            || punctuatedText.last == "!"
                            || punctuatedText.last == "?"
                        let atMaxLength = currentWords.count >= maxWordsPerCaption

                        if (endsWithSentencePunctuation || atMaxLength), let start = segmentStart {
                            let endTime = CMTime(seconds: segment.timestamp + segment.duration, preferredTimescale: 600)
                            let caption = TimedCaption(
                                text: currentWords.joined(separator: " "),
                                startTime: start,
                                endTime: endTime,
                                words: currentTimedWords
                            )
                            captions.append(caption)
                            currentWords = []
                            currentTimedWords = []
                            segmentStart = nil
                        }
                    }

                    if !currentWords.isEmpty, let start = segmentStart,
                       let lastSegment = segments.last {
                        let endTime = CMTime(seconds: lastSegment.timestamp + lastSegment.duration, preferredTimescale: 600)
                        let caption = TimedCaption(
                            text: currentWords.joined(separator: " "),
                            startTime: start,
                            endTime: endTime,
                            words: currentTimedWords
                        )
                        captions.append(caption)
                    }

                    hasResumed = true
                    continuation.resume(returning: captions)
                }
            }
        }
    }
}
