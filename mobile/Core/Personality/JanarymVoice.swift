import Foundation

/// Janarym's personality — warm, casual, like a best friend.
/// Phrase pools rotate: never repeats the same phrase twice in a row.
final class JanarymVoice {

    static let shared = JanarymVoice()
    private init() {}

    // MARK: - Phrase pools

    private let listeningPool  = ["Айта бер", "Тыңдап тұрмын", "Иә?"]
    private let processingPool = ["Ойлап жатырмын...", "Секунд...", "Қараймын"]
    private let successPool    = ["Дайын!", "Міне", "Болды"]
    private let errorPool      = ["Дұрыс түсінбедім, тағы айтшы", "Естімедім, қайтадан"]
    private let strugglePool   = ["Ештеңе етпейді, баяуырақ айта бер"]
    private let cameraIntro    = ["Қарашы,", "Алдыңда", "Міне,"]

    // MARK: - Last-used index trackers

    private var listeningLast  = -1
    private var processingLast = -1
    private var successLast    = -1
    private var errorLast      = -1

    private var consecutiveErrors = 0

    // MARK: - Rotated phrase API

    func listening() -> String  { rotate(listeningPool,  last: &listeningLast) }
    func processing() -> String { rotate(processingPool, last: &processingLast) }
    func success() -> String    { rotate(successPool,    last: &successLast) }

    /// Localized "I'm listening" prompt played right after PTT tap.
    /// Russian pool is separate — UI language drives which one plays.
    func listeningLocalized(kk: Bool) -> String {
        if kk { return rotate(listeningPool, last: &listeningLast) }
        let ru = ["Слушаю", "Да?", "Говори"]
        return ru.randomElement() ?? "Слушаю"
    }

    func listening(language: DetectedLanguage) -> String {
        switch language {
        case .kazakh:
            return listening()
        case .russian:
            return ["Слушаю", "Да?", "Говорите"].randomElement() ?? "Слушаю"
        case .english:
            return ["Listening", "Yes?", "Go ahead"].randomElement() ?? "Listening"
        }
    }

    func error() -> String {
        consecutiveErrors += 1
        if consecutiveErrors >= 3 {
            consecutiveErrors = 0
            return strugglePool.randomElement() ?? "Ештеңе етпейді, баяуырақ айта бер"
        }
        return rotate(errorPool, last: &errorLast)
    }

    func resetErrors() { consecutiveErrors = 0 }

    func cameraDescPrefix() -> String { cameraIntro.randomElement() ?? "Міне," }

    // MARK: - Scenario phrases (fixed, no rotation)

    func time(_ words: String) -> String            { "Қазір \(words)" }
    func time(_ words: String, language: DetectedLanguage) -> String {
        switch language {
        case .kazakh: return "Қазір \(words)"
        case .russian: return "Сейчас \(words)"
        case .english: return "It is \(words)"
        }
    }
    func askReminder() -> String                    { "Ескертпе қоямын ба?" }
    func askWhen() -> String                        { "Қашан?" }
    func reminderSet(_ timeWords: String) -> String { "Жарайды, \(timeWords) еске салам" }
    func reminderFired(_ timeWords: String) -> String { "Эй, \(timeWords) болды! Ескерткен едің" }

    func lowBattery(_ pct: Int) -> String      { "Заряд аздап қалды, \(pct)% — розеткаға қосайық па?" }
    func criticalBattery(_ pct: Int) -> String { "Телефон өшкелі жатыр, \(pct)% қалды!" }

    func torchOn() -> String  { "Фонарик қосылды" }
    func torchOff() -> String { "Фонарик өшірілді" }
    func torchOn(language: DetectedLanguage) -> String {
        switch language {
        case .kazakh: return "Фонарик қосылды"
        case .russian: return "Фонарик включён"
        case .english: return "Flashlight is on"
        }
    }
    func torchOff(language: DetectedLanguage) -> String {
        switch language {
        case .kazakh: return "Фонарик өшірілді"
        case .russian: return "Фонарик выключен"
        case .english: return "Flashlight is off"
        }
    }
    func videoStarted() -> String { "Видео түсіріп жатырмын" }
    func videoStarted(language: DetectedLanguage) -> String {
        switch language {
        case .kazakh: return "Видео түсіріп жатырмын"
        case .russian: return "Идёт запись видео"
        case .english: return "Video recording"
        }
    }
    func videoStartedAnnouncement() -> String { "Видео басталды" }
    func videoStartedAnnouncement(language: DetectedLanguage) -> String {
        switch language {
        case .kazakh: return "Видео басталды"
        case .russian: return "Запись видео началась"
        case .english: return "Video recording started"
        }
    }
    func videoSaved() -> String { "Видео сақталды" }
    func videoSaved(language: DetectedLanguage) -> String {
        switch language {
        case .kazakh: return "Видео сақталды"
        case .russian: return "Видео сохранено"
        case .english: return "Video saved"
        }
    }
    func videoNotRecording() -> String { "Қазір видео түсіріліп жатқан жоқ" }
    func videoAlreadyRecording() -> String { "Видео түсіріп жатырмын" }
    func videoFailed() -> String { "Видеоны түсіре алмадым" }

    func parentLinked(_ name: String = "Апаң") -> String {
        "\(name) қосылды! Енді ол сені көре алады"
    }
    func sosSent() -> String { "Апаңа хабар жібердім, жол келе жатыр!" }
    func sosSent(language: DetectedLanguage) -> String {
        switch language {
        case .kazakh: return "Апаңа хабар жібердім, жол келе жатыр!"
        case .russian: return "SOS отправлен. Близкие уже получили сообщение."
        case .english: return "SOS sent. Your trusted contact has been notified."
        }
    }
    func morning() -> String { "Қайырлы таң! Бүгін қалайсың?" }

    func screenWelcome() -> String {
        "Камераны бастау үшін экранның жоғарғы бөлігін ұстап тұр"
    }
    func screenWelcome(language: DetectedLanguage) -> String {
        switch language {
        case .kazakh:
            return "Камераны бастау үшін экранның жоғарғы бөлігін ұстап тұр"
        case .russian:
            return "Чтобы включить камеру, удерживайте верхнюю часть экрана"
        case .english:
            return "Hold the top of the screen to start the camera"
        }
    }

    func medCardOpened() -> String { "Медициналық карта" }
    func medCardReadoutUnavailable() -> String { "Медкартада оқитын мәлімет жоқ" }
    func settingsOpened() -> String { "Баптаулар" }
    func medCardOpened(language: DetectedLanguage) -> String {
        switch language {
        case .kazakh: return "Медициналық карта"
        case .russian: return "Медицинская карта"
        case .english: return "Medical card"
        }
    }
    func medCardReadoutUnavailable(language: DetectedLanguage) -> String {
        switch language {
        case .kazakh: return "Медкартада оқитын мәлімет жоқ"
        case .russian: return "В медкарте пока нет данных для озвучивания"
        case .english: return "There is no medical card information to read yet"
        }
    }
    func settingsOpened(language: DetectedLanguage) -> String {
        switch language {
        case .kazakh: return "Баптаулар"
        case .russian: return "Настройки"
        case .english: return "Settings"
        }
    }
    func unrecognized() -> String   { error() }

    // MARK: - Time in words (Kazakh)

    /// Converts a Date to Kazakh spoken time: "екі жиырма бес"
    func timeInWords(from date: Date = Date()) -> String {
        let cal  = Calendar.current
        var hour = cal.component(.hour,   from: date)
        let min  = cal.component(.minute, from: date)
        if hour >= 13 { hour -= 12 }
        if hour == 0  { hour = 12 }

        let hourWords: [Int: String] = [
            1: "бір", 2: "екі", 3: "үш", 4: "төрт", 5: "бес",
            6: "алты", 7: "жеті", 8: "сегіз", 9: "тоғыз",
            10: "он", 11: "он бір", 12: "он екі"
        ]
        let minWords: [Int: String] = [
            0: "",  1: "бір",  2: "екі",  3: "үш",  4: "төрт",
            5: "бес", 6: "алты", 7: "жеті", 8: "сегіз", 9: "тоғыз",
            10: "он", 11: "он бір", 12: "он екі", 13: "он үш",
            14: "он төрт", 15: "он бес", 16: "он алты", 17: "он жеті",
            18: "он сегіз", 19: "он тоғыз", 20: "жиырма",
            21: "жиырма бір", 22: "жиырма екі", 23: "жиырма үш",
            24: "жиырма төрт", 25: "жиырма бес", 26: "жиырма алты",
            27: "жиырма жеті", 28: "жиырма сегіз", 29: "жиырма тоғыз",
            30: "отыз", 31: "отыз бір", 32: "отыз екі", 33: "отыз үш",
            34: "отыз төрт", 35: "отыз бес", 36: "отыз алты",
            37: "отыз жеті", 38: "отыз сегіз", 39: "отыз тоғыз",
            40: "қырық", 41: "қырық бір", 42: "қырық екі", 43: "қырық үш",
            44: "қырық төрт", 45: "қырық бес", 46: "қырық алты",
            47: "қырық жеті", 48: "қырық сегіз", 49: "қырық тоғыз",
            50: "елу", 51: "елу бір", 52: "елу екі", 53: "елу үш",
            54: "елу төрт", 55: "елу бес", 56: "елу алты",
            57: "елу жеті", 58: "елу сегіз", 59: "елу тоғыз"
        ]

        let hWord = hourWords[hour] ?? "\(hour)"
        if min == 0 { return hWord }
        let mWord = minWords[min] ?? "\(min)"
        return "\(hWord) \(mWord)"
    }

    // MARK: - Private

    private func rotate(_ pool: [String], last: inout Int) -> String {
        guard !pool.isEmpty else { return "" }
        guard pool.count > 1 else { return pool[0] }
        var next: Int
        repeat { next = Int.random(in: 0..<pool.count) } while next == last
        last = next
        return pool[next]
    }
}
