import Speech
import CoreMedia

class TranscriptionService {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    func transcribeAudio(from videoURL: URL) async -> [TimedCaption] {
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

                    var captions: [TimedCaption] = []
                    var currentWords: [String] = []
                    var segmentStart: CMTime?

                    for segment in result.bestTranscription.segments {
                        if segmentStart == nil {
                            segmentStart = CMTime(seconds: segment.timestamp, preferredTimescale: 600)
                        }

                        currentWords.append(segment.substring)

                        if currentWords.count >= 5, let start = segmentStart {
                            let endTime = CMTime(seconds: segment.timestamp + segment.duration, preferredTimescale: 600)
                            let caption = TimedCaption(
                                text: currentWords.joined(separator: " "),
                                startTime: start,
                                endTime: endTime
                            )
                            captions.append(caption)
                            currentWords = []
                            segmentStart = nil
                        }
                    }

                    if !currentWords.isEmpty, let start = segmentStart,
                       let lastSegment = result.bestTranscription.segments.last {
                        let endTime = CMTime(seconds: lastSegment.timestamp + lastSegment.duration, preferredTimescale: 600)
                        let caption = TimedCaption(
                            text: currentWords.joined(separator: " "),
                            startTime: start,
                            endTime: endTime
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
