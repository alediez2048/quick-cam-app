import AVFoundation
import CoreMedia

@Observable
final class TranscriptPlaybackObserver {
    var currentWordIndex: Int? = nil

    private var timeObserverToken: Any?
    private var allWords: [TimedWord] = []

    func attach(to player: AVPlayer, words: [TimedWord]) {
        allWords = words
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            self?.updateCurrentWord(for: time)
        }
    }

    func detach(from player: AVPlayer) {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        currentWordIndex = nil
    }

    private func updateCurrentWord(for time: CMTime) {
        let seconds = CMTimeGetSeconds(time)
        let newIndex = allWords.firstIndex { word in
            let start = CMTimeGetSeconds(word.startTime)
            let end = CMTimeGetSeconds(word.endTime)
            return seconds >= start && seconds < end
        }
        if newIndex != currentWordIndex {
            currentWordIndex = newIndex
        }
    }
}
