import Speech
import CoreMedia

class TranscriptionService {

    /// Check current authorization without triggering a TCC prompt.
    static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Request speech recognition authorization.
    /// Returns true if authorized, false otherwise.
    /// Only call this from an Xcode-debugged launch the first time;
    /// subsequent runs (including standalone) will use the cached grant.
    static func requestAuthorizationIfNeeded() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { newStatus in
                    continuation.resume(returning: newStatus == .authorized)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func transcribeAudio(from videoURL: URL, locale: Locale = Locale(identifier: "en-US")) async -> [TimedCaption] {
        let speechRecognizer = SFSpeechRecognizer(locale: locale)
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            return []
        }

        // Check authorization before touching the TCC-protected API.
        // If already authorized (cached from a previous grant), this is safe
        // even for ad-hoc signed standalone launches.
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            break
        case .notDetermined:
            let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { newStatus in
                    continuation.resume(returning: newStatus == .authorized)
                }
            }
            guard granted else { return [] }
        case .denied, .restricted:
            return []
        @unknown default:
            return []
        }

        // Perform transcription — authorization is confirmed
        return await withCheckedContinuation { continuation in
            var hasResumed = false

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
