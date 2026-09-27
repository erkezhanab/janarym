import Foundation
import Combine
import SwiftUI
import AVFoundation

// MARK: - UserProfile

struct UserProfile: Codable, Equatable {
    var language:       Language       = .kazakh
    var name:           String         = ""
    var formality:      Formality      = .formal
    var ageRange:       AgeRange       = .age26_35
    var occupation:     Occupation     = .other
    var city:           String         = ""
    var purpose:        Purpose        = .all
    var hobbies:        String         = ""
    var responseLength:         ResponseLength = .short
    var speechRate:             SpeechRate     = .normal
    var focusMode:              FocusMode      = .all
    var gptVoice:               GPTVoice       = .ember
    /// AVSpeechSynthesisVoice identifier — nil means auto-select best available
    var selectedVoiceIdentifier: String?       = nil

    init() {}

    enum CodingKeys: String, CodingKey {
        case language
        case name
        case formality
        case ageRange
        case occupation
        case city
        case purpose
        case hobbies
        case responseLength
        case speechRate
        case focusMode
        case gptVoice
        case selectedVoiceIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(Language.self, forKey: .language) ?? .kazakh
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        formality = try container.decodeIfPresent(Formality.self, forKey: .formality) ?? .formal
        ageRange = try container.decodeIfPresent(AgeRange.self, forKey: .ageRange) ?? .age26_35
        occupation = try container.decodeIfPresent(Occupation.self, forKey: .occupation) ?? .other
        city = try container.decodeIfPresent(String.self, forKey: .city) ?? ""
        purpose = try container.decodeIfPresent(Purpose.self, forKey: .purpose) ?? .all
        hobbies = try container.decodeIfPresent(String.self, forKey: .hobbies) ?? ""
        responseLength = try container.decodeIfPresent(ResponseLength.self, forKey: .responseLength) ?? .short
        speechRate = try container.decodeIfPresent(SpeechRate.self, forKey: .speechRate) ?? .normal
        focusMode = try container.decodeIfPresent(FocusMode.self, forKey: .focusMode) ?? .all
        gptVoice = try container.decodeIfPresent(GPTVoice.self, forKey: .gptVoice) ?? .ember
        selectedVoiceIdentifier = try container.decodeIfPresent(String.self, forKey: .selectedVoiceIdentifier)
    }

    // MARK: Enums

    enum Language: String, Codable, CaseIterable, Equatable {
        case kazakh = "kk"
        case russian = "ru"
        case english = "en"
        var displayName: String {
            switch self {
            case .kazakh:  return "Қазақша"
            case .russian: return "Орысша"
            case .english: return "English"
            }
        }
        var shortLabel: String {
            switch self {
            case .kazakh:  return "KZ"
            case .russian: return "RU"
            case .english: return "EN"
            }
        }
        var languageSubtitle: String {
            switch self {
            case .kazakh:  return "Қазақ тілі"
            case .russian: return "Русский язык"
            case .english: return "English language"
            }
        }
        var flagEmoji: String {
            switch self {
            case .kazakh:  return "🇰🇿"
            case .russian: return "🇷🇺"
            case .english: return "🇬🇧"
            }
        }
        var isKazakh: Bool { self == .kazakh }
        var detectedLanguage: DetectedLanguage {
            switch self {
            case .kazakh:  return .kazakh
            case .russian: return .russian
            case .english: return .english
            }
        }
        var assistantLanguageName: String {
            switch self {
            case .kazakh:  return "Kazakh"
            case .russian: return "Russian"
            case .english: return "English"
            }
        }
    }

    enum Formality: String, Codable, CaseIterable, Equatable {
        case formal, informal
        func display(_ lang: Language) -> String {
            switch (self, lang) {
            case (.formal,   .kazakh):  return "Сіз"
            case (.informal, .kazakh):  return "Сен"
            case (.formal,   .russian): return "Вы"
            case (.informal, .russian): return "ты"
            case (.formal,   .english): return "Formal"
            case (.informal, .english): return "Casual"
            }
        }
        func formalityLabel(kk: Bool) -> String {
            switch (self, kk) {
            case (.formal,   true):  return "ресми"
            case (.formal,   false): return "официально"
            case (.informal, true):  return "жайлы"
            case (.informal, false): return "неформально"
            }
        }
    }

    enum AgeRange: String, Codable, CaseIterable, Equatable {
        case age0_7 = "0–7"
        case age8_12 = "8–12"
        case age13_17 = "13–17"
        case age18_25 = "18–25"
        case age26_35 = "26–35"
        case age36_50 = "36–50"
        case age50plus = "50+"

        func display(_ lang: Language) -> String {
            switch (self, lang) {
            case (.age0_7, .kazakh): return "0–7 жас"
            case (.age8_12, .kazakh): return "8–12 жас"
            case (.age13_17, .kazakh): return "13–17 жас"
            case (.age18_25, .kazakh): return "18–25 жас"
            case (.age26_35, .kazakh): return "26–35 жас"
            case (.age36_50, .kazakh): return "36–50 жас"
            case (.age50plus, .kazakh): return "50+ жас"
            case (.age0_7, .russian): return "0–7 лет"
            case (.age8_12, .russian): return "8–12 лет"
            case (.age13_17, .russian): return "13–17 лет"
            case (.age18_25, .russian): return "18–25 лет"
            case (.age26_35, .russian): return "26–35 лет"
            case (.age36_50, .russian): return "36–50 лет"
            case (.age50plus, .russian): return "50+ лет"
            case (.age0_7, .english): return "0–7 years"
            case (.age8_12, .english): return "8–12 years"
            case (.age13_17, .english): return "13–17 years"
            case (.age18_25, .english): return "18–25 years"
            case (.age26_35, .english): return "26–35 years"
            case (.age36_50, .english): return "36–50 years"
            case (.age50plus, .english): return "50+ years"
            }
        }
    }

    enum Occupation: String, Codable, CaseIterable, Equatable {
        case student, business, tech, medicine, other
        func display(_ lang: Language) -> String {
            switch lang {
            case .kazakh:
                switch self {
                case .student:  return "Студент"
                case .business: return "Бизнес"
                case .tech:     return "Технология"
                case .medicine: return "Медицина"
                case .other:    return "Өзге"
                }
            case .russian:
                switch self {
                case .student:  return "Студент"
                case .business: return "Бизнес"
                case .tech:     return "Технологии"
                case .medicine: return "Медицина"
                case .other:    return "Другое"
                }
            case .english:
                switch self {
                case .student:  return "Student"
                case .business: return "Business"
                case .tech:     return "Technology"
                case .medicine: return "Medicine"
                case .other:    return "Other"
                }
            }
        }
    }

    enum Purpose: String, Codable, CaseIterable, Equatable {
        case daily, study, entertainment, all
        func display(_ lang: Language) -> String {
            switch lang {
            case .kazakh:
                switch self {
                case .daily:         return "Күнделікті сұрақтар"
                case .study:         return "Оқу / Жұмыс"
                case .entertainment: return "Ойын-сауық"
                case .all:           return "Барлығы"
                }
            case .russian:
                switch self {
                case .daily:         return "Повседневные вопросы"
                case .study:         return "Учёба / Работа"
                case .entertainment: return "Развлечения"
                case .all:           return "Всё"
                }
            case .english:
                switch self {
                case .daily:         return "Daily questions"
                case .study:         return "Study / Work"
                case .entertainment: return "Entertainment"
                case .all:           return "Everything"
                }
            }
        }
    }

    enum ResponseLength: String, Codable, CaseIterable, Equatable {
        case short, medium, long
        func display(_ lang: Language) -> String {
            switch lang {
            case .kazakh:
                switch self {
                case .short:  return "Қысқа"
                case .medium: return "Орташа"
                case .long:   return "Толық"
                }
            case .russian:
                switch self {
                case .short:  return "Кратко"
                case .medium: return "Умеренно"
                case .long:   return "Подробно"
                }
            case .english:
                switch self {
                case .short:  return "Short"
                case .medium: return "Medium"
                case .long:   return "Detailed"
                }
            }
        }
        var icon: String {
            switch self {
            case .short:  return "1.circle.fill"
            case .medium: return "2.circle.fill"
            case .long:   return "3.circle.fill"
            }
        }
    }

    enum SpeechRate: String, Codable, CaseIterable, Equatable {
        case slow, normal, fast
        func display(_ lang: Language) -> String {
            switch lang {
            case .kazakh:
                switch self {
                case .slow:   return "Баяу"
                case .normal: return "Қалыпты"
                case .fast:   return "Жылдам"
                }
            case .russian:
                switch self {
                case .slow:   return "Медленно"
                case .normal: return "Обычно"
                case .fast:   return "Быстро"
                }
            case .english:
                switch self {
                case .slow:   return "Slow"
                case .normal: return "Normal"
                case .fast:   return "Fast"
                }
            }
        }
        /// OpenAI TTS speed (1.0 = normal)
        var avRate: Float {
            switch self {
            case .slow:   return 0.9
            case .normal: return 1.1
            case .fast:   return 1.3
            }
        }
        /// AVSpeechSynthesizer rate for instant UI preview (0.0–1.0, default 0.5)
        var avPreviewRate: Float {
            switch self {
            case .slow:   return 0.38
            case .normal: return 0.50
            case .fast:   return 0.62
            }
        }
        var icon: String {
            switch self {
            case .slow:   return "tortoise.fill"
            case .normal: return "equal.circle.fill"
            case .fast:   return "hare.fill"
            }
        }
    }

    enum FocusMode: String, Codable, CaseIterable, Equatable {
        case all, people, text, objects

        func displayName(kk: Bool) -> String {
            switch (self, kk) {
            case (.all,     true):  return "Барлығы"
            case (.all,     false): return "Всё"
            case (.people,  true):  return "Адамдар"
            case (.people,  false): return "Люди"
            case (.text,    true):  return "Мәтін"
            case (.text,    false): return "Текст"
            case (.objects, true):  return "Заттар"
            case (.objects, false): return "Предметы"
            }
        }

        func descriptionText(kk: Bool) -> String {
            switch (self, kk) {
            case (.all,     true):  return "Камерадан барлығын сипаттайды"
            case (.all,     false): return "Описывает всё видимое"
            case (.people,  true):  return "Тек адамдар мен олардың орны"
            case (.people,  false): return "Только люди и их положение"
            case (.text,    true):  return "Тек мәтінді оқиды"
            case (.text,    false): return "Только читает текст"
            case (.objects, true):  return "Тек заттар мен кедергілер"
            case (.objects, false): return "Только предметы и препятствия"
            }
        }

        var icon: String {
            switch self {
            case .all:     return "viewfinder"
            case .people:  return "person.2.fill"
            case .text:    return "doc.text.fill"
            case .objects: return "cube.fill"
            }
        }

        func announcementText(kk: Bool) -> String {
            switch (self, kk) {
            case (.all,     true):  return "Барлығы режимі таңдалды"
            case (.all,     false): return "Выбран режим — всё"
            case (.people,  true):  return "Адамдар режимі таңдалды. Камера тек адамдарды сипаттайды"
            case (.people,  false): return "Режим людей выбран. Камера описывает только людей"
            case (.text,    true):  return "Мәтін режимі таңдалды. Камера тек мәтінді оқиды"
            case (.text,    false): return "Режим текста выбран. Камера читает только текст"
            case (.objects, true):  return "Заттар режимі таңдалды. Камера тек заттарды сипаттайды"
            case (.objects, false): return "Режим предметов выбран. Камера описывает только предметы"
            }
        }

        func announcementText(language: Language) -> String {
            switch language {
            case .kazakh:
                return announcementText(kk: true)
            case .russian:
                return announcementText(kk: false)
            case .english:
                switch self {
                case .all:     return "All mode selected"
                case .people:  return "People mode selected. Camera describes only people"
                case .text:    return "Text mode selected. Camera reads only text"
                case .objects: return "Objects mode selected. Camera describes only objects"
                }
            }
        }

        func promptInstruction(kk: Bool) -> String {
            switch (self, kk) {
            case (.all, _):
                return ""
            case (.people, true):
                return "\nКамера суретінде ТЕК адамдарды сипатта: саны, орналасуы (сол жақта / оң жақта / алдыңда), қозғалысы. Заттарды, мәтінді, фонды сипаттама."
            case (.people, false):
                return "\nНа снимке с камеры описывай ТОЛЬКО людей: количество, расположение (слева / справа / впереди), движение. Предметы, текст, фон — не описывай."
            case (.text, true):
                return "\nКамера суретіндегі БАРЛЫҚ мәтінді дәл, толық оқы. Заттарды, адамдарды, фонды сипаттама — тек мәтін."
            case (.text, false):
                return "\nЧитай ВЕСЬ текст с камеры дословно и полностью. Предметы, людей, фон — не описывай. Только текст."
            case (.objects, true):
                return "\nКамера суретіндегі ТЕК заттар мен кедергілерді сипатта: не деген зат, қай жақта (сол / оң / алда), жолды бөгей ме. Адамдарды, мәтінді сипаттама."
            case (.objects, false):
                return "\nОписывай на снимке ТОЛЬКО предметы и препятствия: что это, где (слева / справа / впереди), блокирует ли путь. Людей и текст не описывай."
            }
        }

        func promptInstruction(language: Language) -> String {
            switch language {
            case .kazakh:
                return promptInstruction(kk: true)
            case .russian:
                return promptInstruction(kk: false)
            case .english:
                switch self {
                case .all:
                    return ""
                case .people:
                    return "\nIn the camera image, describe ONLY people: count, position (left / right / ahead), and movement. Do not describe objects, text, or background."
                case .text:
                    return "\nRead ALL text in the camera image exactly and completely. Do not describe objects, people, or background — only the text."
                case .objects:
                    return "\nDescribe ONLY objects and obstacles in the camera image: what they are, where they are (left / right / ahead), and whether they block the path. Do not describe people or text."
                }
            }
        }
    }

    enum GPTVoice: String, Codable, CaseIterable, Equatable {
        case ember
        case jupiter

        var openAIVoiceID: String {
            switch self {
            case .ember:
                return "cedar"
            case .jupiter:
                return "marin"
            }
        }

        func title(_ lang: Language) -> String {
            switch (self, lang) {
            case (.ember, .kazakh): return "Ер адам"
            case (.ember, .russian): return "Мужской"
            case (.ember, .english): return "Male"
            case (.jupiter, .kazakh): return "Әйел"
            case (.jupiter, .russian): return "Женский"
            case (.jupiter, .english): return "Female"
            }
        }

        func subtitle(_ lang: Language) -> String {
            switch (self, lang) {
            case (.ember, .kazakh): return "Ember"
            case (.ember, .russian): return "Ember"
            case (.ember, .english): return "Ember"
            case (.jupiter, .kazakh): return "Jupiter"
            case (.jupiter, .russian): return "Jupiter"
            case (.jupiter, .english): return "Jupiter"
            }
        }

        func announcement(_ lang: Language) -> String {
            switch (self, lang) {
            case (.ember, .kazakh): return "Ер адам дауысы таңдалды"
            case (.ember, .russian): return "Выбран мужской голос"
            case (.ember, .english): return "Male voice selected"
            case (.jupiter, .kazakh): return "Әйел дауысы таңдалды"
            case (.jupiter, .russian): return "Выбран женский голос"
            case (.jupiter, .english): return "Female voice selected"
            }
        }
    }
}

// MARK: - OnboardingStore

final class OnboardingStore: ObservableObject {
    static let shared = OnboardingStore()

    @Published private(set) var isCompleted: Bool
    @Published var profile: UserProfile

    private let completedKey = "onboarding_v1_completed"
    private let profileKey   = "onboarding_v1_profile"
    private let persistenceQueue = DispatchQueue(label: "com.janarym.onboarding.persistence", qos: .utility)

    private init() {
        isCompleted = UserDefaults.standard.bool(forKey: "onboarding_v1_completed")
        if let data    = UserDefaults.standard.data(forKey: "onboarding_v1_profile"),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = decoded
        } else {
            profile = UserProfile()
        }
    }

    func complete(with p: UserProfile) {
        profile = p
        persistProfile()
        UserDefaults.standard.set(true, forKey: completedKey)
        isCompleted = true
    }

    func updateLanguage(_ language: UserProfile.Language) {
        guard profile.language != language else { return }
        var updated = profile
        updated.language = language
        if let identifier = updated.selectedVoiceIdentifier,
           !identifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: identifier),
           !SystemVoiceResolver.voiceMatchesLanguage(voice, language: language) {
            updated.selectedVoiceIdentifier = nil
        }
        profile = updated
        persistProfile()
    }

    func updateProfile(_ newProfile: UserProfile) {
        profile = newProfile
        persistProfile()
    }

    func reset() {
        profile = UserProfile()
        UserDefaults.standard.removeObject(forKey: completedKey)
        UserDefaults.standard.removeObject(forKey: profileKey)
        isCompleted = false
    }

    var currentLanguage: UserProfile.Language { profile.language }
    var isKazakh: Bool { currentLanguage.isKazakh }

    private func persistProfile() {
        let snapshot = profile
        persistenceQueue.async { [profileKey] in
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: profileKey)
            }
        }
    }

    // MARK: - Dynamic system prompt

    var systemPrompt: String {
        let p  = profile
        let mismatchMessage = AppText.languageMismatchPrompt(for: p.language)

        let langRule: String
        switch p.language {
        case .kazakh:
            langRule = "МАҢЫЗДЫ: ТЕК ҚАЗАҚША сұранысты қабылда және ТЕК ҚАЗАҚША жауап бер. Орысша немесе ағылшынша ҚАБЫЛДАМА, ЖАЗБА."
        case .russian:
            langRule = "ВАЖНО: Принимай ТОЛЬКО русскую речь и отвечай ТОЛЬКО по-русски. Казахский и английский НЕ ПРИНИМАТЬ и НЕ ИСПОЛЬЗОВАТЬ."
        case .english:
            langRule = "IMPORTANT: Accept ONLY English speech and answer ONLY in English. Do NOT accept or use Kazakh or Russian."
        }

        let nameClause = p.name.isEmpty ? ""
            : AppText.pick(
                " Пайдаланушының аты — \(p.name).",
                " Пользователя зовут \(p.name).",
                en: " The user's name is \(p.name).",
                language: p.language
            )

        let formalClause = AppText.pick(
            "Пайдаланушыға '\(p.formality.display(.kazakh))' деп жүгін.",
            "Обращайся к пользователю на '\(p.formality.display(.russian))'.",
            en: "Use a \(p.formality.display(.english).lowercased()) tone with the user.",
            language: p.language
        )

        // Хобби — тек сәйкес болса пайдалану, мәжбүрлемеу
        let hobbyClause = p.hobbies.isEmpty ? ""
            : AppText.pick(
                "\nПайдаланушының қызығушылықтары: \(p.hobbies). Тек пайдаланушы өзі сол тақырыпты бастаса немесе сұраса ғана айт — басқа кезде мәжбүрлеп кіргізбе.",
                "\nИнтересы пользователя: \(p.hobbies). Упоминай только если пользователь сам поднял тему — не вставляй насильно.",
                en: "\nUser interests: \(p.hobbies). Mention them only if the user brings up that topic or asks about it.",
                language: p.language
            )

        let lengthRule: String
        switch (p.responseLength, p.language) {
        case (.short, .kazakh):
            lengthRule = "Әдетте 2 қысқа сөйлеммен жауап бер. Бірінші сөйлемде негізгі жауапты айт, екінші сөйлемде бір нақты пайдалы деталь не жақын объектіні қос."
        case (.short, .russian):
            lengthRule = "Обычно отвечай 2 короткими предложениями. В первом дай прямой ответ, во втором добавь одну полезную конкретную деталь или ближайший объект."
        case (.short, .english):
            lengthRule = "Usually answer in 2 short sentences. Give the direct answer first, then add one concrete useful detail or nearby object."
        case (.medium, .kazakh):
            lengthRule = "Әдетте 2 қысқа сөйлеммен жауап бер, тек қажет болса сәл кеңейт."
        case (.medium, .russian):
            lengthRule = "Обычно отвечай 2 короткими предложениями, расширяй ответ только если это действительно нужно."
        case (.medium, .english):
            lengthRule = "Usually answer in 2 short sentences, expanding only when it is truly needed."
        case (.long, .kazakh):
            lengthRule = "Негізгі жауап бәрібір 2 түсінікті сөйлемнен басталсын, содан кейін ғана қажет болса толықтыр."
        case (.long, .russian):
            lengthRule = "Основной ответ всё равно начинай с 2 понятных предложений, и только потом при необходимости расширяй."
        case (.long, .english):
            lengthRule = "Still start with 2 clear sentences, then add detail only if needed."
        }

        let focusModeInstruction = p.focusMode.promptInstruction(language: p.language)
        let visionRule = AppText.pick(
            "Әрбір сұрақпен бірге пайдаланушының камерасынан түсірілген сурет жіберілуі мүмкін. Сен сол суретті КӨРЕ АЛАСЫҢ. 'Алдымда не тұр?', 'бұл не?', 'қарашы' деген сұрақтарға суретті талдап нақты жауап бер. Сурет анық болмаса, оны тура айт.",
            "К каждому вопросу может прилагаться снимок с камеры пользователя. Ты МОЖЕШЬ ВИДЕТЬ этот снимок. На вопросы 'что передо мной?', 'что это?', 'посмотри' — анализируй снимок и отвечай конкретно. Если кадр неясный, скажи об этом прямо.",
            en: "Each question may include a camera image from the user. You CAN SEE that image. For questions like 'what is in front of me?', 'what is this?', or 'look at this', analyze the image and answer concretely. If the frame is unclear, say that directly.",
            language: p.language
        ) + focusModeInstruction

        let base: String
        switch p.language {
        case .kazakh:
            base = """
Сен — Жанарым, нашар көретін немесе мүлде көрмейтін адамдарға арналған дауыстық AI-ассистентсің.\(nameClause)
\(langRule)
Егер пайдаланушы басқа тілде сөйлесе, дәл былай жауап бер: \(mismatchMessage)
\(formalClause)
\(lengthRule)
\(visionRule)\(hobbyClause)
Тек нақты сұрақ туралы жауап бер. Сұрамаған ешбір қосымша ақпарат, кеңес, жалғасты сөз БЕРМE.
Жауапты ешқашан "Жарайды", "Кемел", "Сәлем", "Мен дайынмын", "Міне", "Бастайық" деген кіріспелермен БАСТАМА — тікелей жауапқа кір.
Ешқашан өзіңнің не жасап жатқаныңды түсіндірме ("Суретті талдап жатырмын", "Сізге жауап береін" — БҰЛАЙ ДЕМА).
Пайдаланушы жай сөз айтса (мысалы "сәлем") — қысқа, табиғи жауап бер, ұзақ таныстыру жасама.
Сөйлемнің соңын жұтып қойма, сөздерді қысқартпа, объект атауларын толық айт.
Markdown, тізімдер, жұлдызшалар ПАЙДАЛАНБА — жауап TTS үшін. Тек табиғи сөйлеу.
"""
        case .russian:
            base = """
Ты — Жанарым, голосовой AI-ассистент для людей с плохим зрением или полной потерей зрения.\(nameClause)
\(langRule)
Если пользователь говорит на другом языке, ответь точно так: \(mismatchMessage)
\(formalClause)
\(lengthRule)
\(visionRule)\(hobbyClause)
Отвечай строго по теме запроса. Никакой лишней информации, советов, продолжений, которые не просили.
Никогда не начинай ответ с "Конечно!", "Хорошо!", "Отлично!", "Разумеется!", "Здравствуйте" — сразу переходи к сути.
Никогда не объясняй что ты делаешь ("Анализирую изображение", "Сейчас отвечу" — НЕ ГОВОРИ ТАК).
Если пользователь просто поздоровался — ответь коротко и естественно, без длинного представления.
Не обрывай конец фразы, не проглатывай последние слова, произноси названия объектов полностью.
Не используй markdown, списки и звёздочки — ответ предназначен для TTS. Говори естественно.
"""
        case .english:
            base = """
You are Janarym, a voice AI assistant for people with low vision or complete vision loss.\(nameClause)
\(langRule)
If the user speaks another language, answer exactly this: \(mismatchMessage)
\(formalClause)
\(lengthRule)
\(visionRule)\(hobbyClause)
Answer strictly on the requested topic. Do not add extra information, advice, or continuations the user did not ask for.
Never start with "Sure!", "Okay!", "Great!", "Of course!", or "Hello" — go straight to the answer.
Never explain what you are doing ("I am analyzing the image", "I will answer now" — DO NOT say that).
If the user only greets you, answer briefly and naturally without a long introduction.
Do not cut off the end of phrases, do not swallow final words, and pronounce object names fully.
Do not use markdown, lists, or asterisks — the answer is for TTS. Speak naturally.
"""
        }
        return base
    }

    // MARK: - Mode-specific prompt addition

    func modePrompt(for mode: AppMode) -> String {
        switch mode {
        case .general:
            return ""  // базалық prompt жеткілікті

        case .navigation:
            return AppText.pick(
                "Сен қазір НАВИГАЦИЯ режимінде жұмыс жасайсың. Пайдаланушыға орналасуын, жақын жерлерді, маршрутты анық дауыстық нұсқаулармен түсіндір. Солға, оңға, алға, артқа деп нақты бағыт бер.",
                "Ты в режиме НАВИГАЦИИ. Давай пользователю чёткие голосовые инструкции: налево, направо, прямо, назад. Указывай расстояния в метрах.",
                en: "You are in NAVIGATION mode. Give clear voice guidance: left, right, straight ahead, back. Mention distances in meters.",
                language: profile.language
            )

        case .security:
            return AppText.pick(
                """
Сен қазір АЛАЯҚТЫҚҚА ҚАРСЫ режимінде жұмыс жасайсың. Камерадан көрінген нәрсені алаяқтық белгілері үшін талда:
- Жалған банкноттар: номиналды оқы, "Банк приколов", "сувенир", "образец" жазуларын іздес
- Жалған құжаттар: паспорт, куәлік, диплом, сертификат — мөр, қол, реквизиттерді тексер
- Күдікті QR кодтар мен сілтемелер
- Фишинг SMS/хабарламалар
- Жалған лотерея, жеңіс хабарламалары
Алаяқтық белгісі тапсаң — ДЕРЕУ ескерт. Таппасаң — "Алаяқтық белгісі байқалмады" де.
"""
                ,
                """
Ты в режиме АНТИМОШЕННИЧЕСТВА. Анализируй изображение с камеры на признаки мошенничества:
- Фальшивые купюры: читай номинал, ищи надписи "Банк приколов", "сувенир", "образец"
- Поддельные документы: паспорт, удостоверение, диплом — проверяй печати, подписи
- Подозрительные QR-коды и ссылки
- Фишинговые SMS/сообщения
- Фальшивые лотереи, уведомления о "выигрыше"
Нашёл признак мошенничества — НЕМЕДЛЕННО предупреди. Если всё чисто — скажи "Признаков мошенничества не обнаружено".
"""
                ,
                en: """
You are in ANTI-FRAUD mode. Analyze the camera image for signs of fraud:
- Fake banknotes: read the denomination and look for novelty or sample markings
- Fake documents: passport, ID, diploma, certificate — check stamps, signatures, and details
- Suspicious QR codes and links
- Phishing SMS/messages
- Fake lottery or "prize" notices
If you find a fraud sign, warn immediately. If it looks clean, say "No signs of fraud detected."
""",
                language: profile.language
            )

        case .shopping:
            return AppText.pick(
                "Сен қазір САУДА режимінде жұмыс жасайсың. Камерадан өнімді тани: атауы, брендi, құрамы, срок годности, баға (егер көрінсе). Аллергендерді ерекше айт. Пайдаланушы салыстыруды сұраса — екі өнімнің айырмашылығын айт.",
                "Ты в режиме ПОКУПОК. Распознавай товары с камеры: название, бренд, состав, срок годности, цену (если видна). Обязательно выделяй аллергены. Если просят сравнить — объясни разницу.",
                en: "You are in SHOPPING mode. Recognize products from the camera: name, brand, ingredients, expiry date, and price if visible. Clearly mention allergens. If asked to compare, explain the difference.",
                language: profile.language
            )

        case .reading:
            return AppText.pick(
                "Сен қазір ОҚЫТУ режимінде жұмыс жасайсың. Камерадан барлық мәтінді оқы: кітап, газет, мәзір, жапсырма, хабарландыру, форма. Мәтінді дәл, нақты, толық оқы — ештеңені өткізіп жібермe. Сан, дата, мекенжайды дауыстап айт.",
                "Ты в режиме ЧТЕНИЯ. Читай весь текст с камеры: книга, газета, меню, этикетка, объявление, форма. Читай точно, полностью — ничего не пропускай. Числа, даты, адреса произноси вслух.",
                en: "You are in READING mode. Read all text from the camera: books, newspapers, menus, labels, notices, and forms. Read accurately and completely. Say numbers, dates, and addresses aloud.",
                language: profile.language
            )

        case .arGlasses:
            return AppText.pick(
                "Сен қазір AR КӨЗІЛДІРІК режимінде жұмыс жасайсың. Суреттер ESP32-CAM көзілдіріктен келеді — пайдаланушының нақты көзқарасынан. Алдындағы ортаны нақты, қысқа және пайдалы сипатта: адамдар, заттар, мәтін, қауіп, қашықтық. 1-2 сөйлемде жауап бер.",
                "Ты в режиме AR ОЧКОВ. Изображения поступают с ESP32-CAM очков — это реальный взгляд пользователя. Описывай окружение точно, кратко и полезно: люди, предметы, текст, опасности, расстояния. Отвечай 1-2 предложениями.",
                en: "You are in AR GLASSES mode. Images come from ESP32-CAM glasses, which is the user's real viewpoint. Describe the surroundings accurately, briefly, and usefully: people, objects, text, danger, and distance. Answer in 1-2 sentences.",
                language: profile.language
            )
        }
    }

    func assistantPrompt(for mode: AppMode) -> String {
        let modePrompt = modePrompt(for: mode)
        guard !modePrompt.isEmpty else { return systemPrompt }
        return "\(systemPrompt)\n\(modePrompt)"
    }
}

enum AppText {
    /// Backward-compatible: `en` defaults to `ru` when not provided,
    /// so existing 2-arg call sites keep working.
    static func pick(_ kk: String, _ ru: String, en: String? = nil, language: UserProfile.Language = OnboardingStore.shared.currentLanguage) -> String {
        switch language {
        case .kazakh:  return kk
        case .russian: return ru
        case .english: return en ?? ru
        }
    }

    static func languageMismatchPrompt(for language: UserProfile.Language) -> String {
        pick(
            "Қайталап айтыңыз, тек қазақша сөйлеп сұраңыз.",
            "Повторите, пожалуйста, только по-русски.",
            en: "Please repeat in English only.",
            language: language
        )
    }
}

extension UserRole {
    var label: String {
        let language = OnboardingStore.shared.currentLanguage
        switch self {
        case .developer:
            return AppText.pick("Әзірлеуші", "Разработчик", en: "Developer", language: language)
        case .admin:
            return AppText.pick("Әкімші", "Админ", en: "Admin", language: language)
        case .mentor:
            return AppText.pick("Ментор", "Ментор", en: "Mentor", language: language)
        case .parent:
            return AppText.pick("Ата-ана", "Родитель", en: "Parent", language: language)
        case .child:
            return AppText.pick("Бала", "Ребенок", en: "Child", language: language)
        case .member:
            return AppText.pick("Мүше", "Участник", en: "Member", language: language)
        }
    }
}

extension ApplicationStatus {
    var label: String {
        let language = OnboardingStore.shared.currentLanguage
        switch self {
        case .pending:
            return AppText.pick("Күтуде", "Ожидание", en: "Pending", language: language)
        case .approved:
            return AppText.pick("Бекітілді", "Одобрено", en: "Approved", language: language)
        case .rejected:
            return AppText.pick("Қабылданбады", "Отклонено", en: "Rejected", language: language)
        }
    }

    var color: Color {
        switch self {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }
}
