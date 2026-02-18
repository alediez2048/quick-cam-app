import CoreMedia

struct TimedWord {
    let text: String
    let startTime: CMTime
    let endTime: CMTime
}

struct TimedCaption {
    let text: String
    let startTime: CMTime
    let endTime: CMTime
    let words: [TimedWord]

    init(text: String, startTime: CMTime, endTime: CMTime, words: [TimedWord] = []) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.words = words
    }
}
