import Foundation

enum DetectedLanguage: String {
    case kazakh = "kk"
    case russian = "ru"
    case english = "en"

    var ttsLocaleIdentifier: String {
        switch self {
        case .kazakh:  return "kk-KZ"
        case .russian: return "ru-RU"
        case .english: return "en-US"
        }
    }
}

enum LanguageResolver {

    private static let kazakhSpecificChars: Set<Character> = [
        "ә", "і", "ң", "ғ", "ү", "ұ", "қ", "ө", "һ",
        "Ә", "І", "Ң", "Ғ", "Ү", "Ұ", "Қ", "Ө", "Һ"
    ]

    private static let kazakhTokens: Set<String> = [
        "сәлем", "рахмет", "калай", "қалай", "кайда", "қайда", "не", "неге", "қашан",
        "мен", "маған", "маган", "сіз", "сен", "жоқ", "ия", "иә", "алдында", "алдымда",
        "көріп", "көмек", "жәрдем", "қайталап", "айтшы", "берші", "тұр", "болсын"
    ]

    private static let russianTokens: Set<String> = [
        "привет", "спасибо", "пожалуйста", "что", "как", "где", "когда", "почему",
        "мне", "меня", "передо", "смотри", "посмотри", "помоги", "повтори", "скажи",
        "это", "есть", "нет", "да", "впереди"
    ]

    private static let cyrillicRange = UnicodeScalar("А")...UnicodeScalar("я")

    static func resolve(text: String, whisperLanguage: String? = nil) -> DetectedLanguage {
        // 1. If upstream voice input already provided a language code
        if let lang = whisperLanguage?.lowercased() {
            if lang.hasPrefix("kk") || lang.hasPrefix("kaz") { return .kazakh }
            if lang.hasPrefix("ru") || lang.hasPrefix("rus") { return .russian }
            if lang.hasPrefix("en") || lang.hasPrefix("eng") { return .english }
        }

        // 2. Check for Kazakh-specific characters
        if text.contains(where: { kazakhSpecificChars.contains($0) }) {
            return .kazakh
        }

        let normalized = text
            .lowercased()
            .replacingOccurrences(of: "[^\\p{L}\\p{N}\\s]", with: " ", options: .regularExpression)
        let tokens = Set(normalized.split(whereSeparator: \.isWhitespace).map(String.init))
        let kazakhScore = tokens.intersection(kazakhTokens).count
        let russianScore = tokens.intersection(russianTokens).count

        if kazakhScore > russianScore, kazakhScore > 0 {
            return .kazakh
        }

        if russianScore > kazakhScore, russianScore > 0 {
            return .russian
        }

        // 3. Ambiguous Cyrillic follows the selected app language.
        // This keeps Kazakh replies with no Kazakh-specific letters from being
        // read with a Russian voice.
        if text.unicodeScalars.contains(where: { cyrillicRange.contains($0) }) {
            let preferred = OnboardingStore.shared.currentLanguage.detectedLanguage
            return preferred == .english ? .russian : preferred
        }

        // 4. Fallback → user's preferred language
        return OnboardingStore.shared.currentLanguage.detectedLanguage
    }
}
