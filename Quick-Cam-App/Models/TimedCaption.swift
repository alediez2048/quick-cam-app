import CoreMedia

struct TimedWord {
    var text: String
    let startTime: CMTime
    let endTime: CMTime
}

struct TimedCaption {
    var text: String
    var startTime: CMTime
    var endTime: CMTime
    var words: [TimedWord]

    init(text: String, startTime: CMTime, endTime: CMTime, words: [TimedWord] = []) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.words = words
    }
}
