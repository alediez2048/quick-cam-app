import Speech

enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case english = "en-US"
    case spanish = "es-ES"
    case portuguese = "pt-BR"
    case french = "fr-FR"
    case german = "de-DE"
    case japanese = "ja-JP"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Spanish"
        case .portuguese: return "Portuguese"
        case .french: return "French"
        case .german: return "German"
        case .japanese: return "Japanese"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var isAvailable: Bool {
        SFSpeechRecognizer(locale: locale)?.isAvailable ?? false
    }
}
