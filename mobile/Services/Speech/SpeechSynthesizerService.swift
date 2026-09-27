import AVFoundation

enum SystemVoiceGender {
    case male
    case female
}

enum SystemVoiceResolver {
    private static let maleHints = [
        "aaron", "alex", "daniel", "grandpa", "rocko", "reed", "nicky",
        "oleg", "yuri", "yuriy", "maxim", "damir", "nurlan", "sergey", "timur"
    ]
    private static let femaleHints = [
        "alice", "allison", "ava", "grandma", "joelle", "karen", "kathy", "moira",
        "samantha", "sandy", "shelley", "tessa", "victoria", "anna", "daria", "irina",
        "katya", "milena", "oksana", "tatyana", "yelena", "aliya", "aigul", "dina"
    ]

    static func availableVoices(for language: UserProfile.Language) -> [AVSpeechSynthesisVoice] {
        let codes = acceptableLanguageCodes(for: language)
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in matchesAnyPreferredCode(voice.language, codes: codes) }
            .sorted(by: compareVoices)
    }

    static func resolveVoice(
        language: UserProfile.Language,
        selectedIdentifier: String?,
        preferredGender: SystemVoiceGender? = nil
    ) -> AVSpeechSynthesisVoice? {
        resolveVoice(languageCodes: preferredLanguageCodes(for: language),
                     selectedIdentifier: selectedIdentifier,
                     preferredGender: preferredGender)
    }

    static func resolveVoice(
        language: DetectedLanguage,
        selectedIdentifier: String?,
        preferredGender: SystemVoiceGender? = nil
    ) -> AVSpeechSynthesisVoice? {
        resolveVoice(languageCodes: preferredLanguageCodes(for: language),
                     selectedIdentifier: selectedIdentifier,
                     preferredGender: preferredGender)
    }

    static func voiceMatchesLanguage(
        _ voice: AVSpeechSynthesisVoice,
        language: UserProfile.Language
    ) -> Bool {
        matchesAnyPreferredCode(voice.language, codes: exactLanguageCodes(for: language))
    }

    private static func resolveVoice(
        languageCodes: [String],
        selectedIdentifier: String?,
        preferredGender: SystemVoiceGender?
    ) -> AVSpeechSynthesisVoice? {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()

        if let selectedIdentifier,
           !selectedIdentifier.isEmpty,
           let selectedVoice = AVSpeechSynthesisVoice(identifier: selectedIdentifier),
           matchesAnyPreferredCode(selectedVoice.language, codes: languageCodes),
           preferredGender == nil || matchesGender(selectedVoice, preferredGender!) {
            return selectedVoice
        }

        for code in languageCodes {
            let matching = allVoices
                .filter { languageMatchesCode($0.language, preferredCode: code) }
                .sorted { compareVoices($0, $1, preferredGender: preferredGender) }

            if let preferredGender,
               let genderedVoice = matching.first(where: { matchesGender($0, preferredGender) }) {
                return genderedVoice
            }
        }

        for code in languageCodes {
            let matching = allVoices
                .filter { languageMatchesCode($0.language, preferredCode: code) }
                .sorted { compareVoices($0, $1, preferredGender: preferredGender) }
            if let preferred = matching.first {
                return preferred
            }
        }

        return AVSpeechSynthesisVoice(language: languageCodes.first ?? "ru-RU")
    }

    private static func exactLanguageCodes(for language: UserProfile.Language) -> [String] {
        switch language {
        case .kazakh:
            return ["kk-KZ"]
        case .russian:
            return ["ru-RU"]
        case .english:
            return ["en-US"]
        }
    }

    private static func acceptableLanguageCodes(for language: UserProfile.Language) -> [String] {
        switch language {
        case .kazakh:
            return ["kk-KZ", "ru-RU"]
        case .russian:
            return ["ru-RU"]
        case .english:
            return ["en-US"]
        }
    }

    private static func preferredLanguageCodes(for language: UserProfile.Language) -> [String] {
        switch language {
        case .kazakh:
            return ["kk-KZ", "ru-RU"]
        case .russian:
            return ["ru-RU"]
        case .english:
            return ["en-US"]
        }
    }

    private static func preferredLanguageCodes(for language: DetectedLanguage) -> [String] {
        switch language {
        case .kazakh:
            return ["kk-KZ", "ru-RU"]
        case .russian:
            return ["ru-RU"]
        case .english:
            return ["en-US"]
        }
    }

    private static func compareVoices(_ lhs: AVSpeechSynthesisVoice, _ rhs: AVSpeechSynthesisVoice) -> Bool {
        compareVoices(lhs, rhs, preferredGender: nil)
    }

    private static func compareVoices(
        _ lhs: AVSpeechSynthesisVoice,
        _ rhs: AVSpeechSynthesisVoice,
        preferredGender: SystemVoiceGender?
    ) -> Bool {
        let lhsScore = score(for: lhs, preferredGender: preferredGender)
        let rhsScore = score(for: rhs, preferredGender: preferredGender)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private static func score(for voice: AVSpeechSynthesisVoice, preferredGender: SystemVoiceGender?) -> Int {
        var value = voice.quality.rawValue * 100
        if let preferredGender, matchesGender(voice, preferredGender) {
            value += 75
        }
        if isSiriMaleVoice(voice) {
            value += 50
        } else if isMaleVoice(voice) {
            value += 25
        }
        return value
    }

    private static func isSiriMaleVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let haystack = searchableVoiceDescription(for: voice)
        return haystack.contains("siri") && maleHints.contains(where: haystack.contains)
    }

    private static func isMaleVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let haystack = searchableVoiceDescription(for: voice)
        return maleHints.contains(where: haystack.contains)
    }

    private static func isFemaleVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let haystack = searchableVoiceDescription(for: voice)
        return femaleHints.contains(where: haystack.contains)
    }

    private static func matchesGender(_ voice: AVSpeechSynthesisVoice, _ gender: SystemVoiceGender) -> Bool {
        switch gender {
        case .male:
            return isMaleVoice(voice)
        case .female:
            return isFemaleVoice(voice)
        }
    }

    private static func searchableVoiceDescription(for voice: AVSpeechSynthesisVoice) -> String {
        "\(voice.name) \(voice.identifier)".lowercased()
    }

    private static func matchesAnyPreferredCode(_ voiceLanguage: String, codes: [String]) -> Bool {
        codes.contains { languageMatchesCode(voiceLanguage, preferredCode: $0) }
    }

    private static func languageMatchesCode(_ voiceLanguage: String, preferredCode: String) -> Bool {
        let normalizedVoice = normalizedLanguageCode(voiceLanguage)
        let normalizedPreferred = normalizedLanguageCode(preferredCode)

        if normalizedVoice == normalizedPreferred {
            return true
        }

        let preferredBase = normalizedPreferred.split(separator: "-", maxSplits: 1).first.map(String.init) ?? normalizedPreferred
        let voiceBase = normalizedVoice.split(separator: "-", maxSplits: 1).first.map(String.init) ?? normalizedVoice

        return voiceBase == preferredBase
    }

    private static func normalizedLanguageCode(_ code: String) -> String {
        code.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}

final class SpeechSynthesizerService: NSObject, ObservableObject {

    @Published var isSpeaking = false

    var onFinished: (() -> Void)?

    private let synth = AVSpeechSynthesizer()
    private var speechStartWatchdogTask: DispatchWorkItem?
    private var hasStartedCurrentUtterance = false
    private var didAttemptDefaultFallback = false
    private var pendingText = ""
    private var pendingLanguage: DetectedLanguage = .russian

    override init() {
        super.init()
        synth.delegate = self
    }

    // MARK: - Public

    func speak(_ text: String, language: DetectedLanguage) {
        guard !text.isEmpty else { onFinished?(); return }
        cancelStartWatchdog()
        // Caller (speakLocally) already set up the audio session.
        // Stop any in-progress utterance immediately before queuing a new one.
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        isSpeaking = true
        hasStartedCurrentUtterance = false
        didAttemptDefaultFallback = false
        pendingText = text
        pendingLanguage = language

        enqueueUtterance(text: text, language: language, voice: selectedVoice(for: language))
        scheduleStartWatchdog()
    }

    func stop() {
        cancelStartWatchdog()
        if synth.isSpeaking { synth.stopSpeaking(at: .word) }
        isSpeaking = false
        hasStartedCurrentUtterance = false
        didAttemptDefaultFallback = false
    }

    // MARK: - Available voices (for Settings UI)

    static func availableVoices(for language: DetectedLanguage) -> [AVSpeechSynthesisVoice] {
        switch language {
        case .kazakh:
            return SystemVoiceResolver.availableVoices(for: .kazakh)
        case .russian:
            return SystemVoiceResolver.availableVoices(for: .russian)
        case .english:
            return SystemVoiceResolver.availableVoices(for: .english)
        }
    }

    static var kazakhVoices: [AVSpeechSynthesisVoice] {
        availableVoices(for: .kazakh)
    }

    // MARK: - Voice selection (user pick → identifier stored in profile)

    private func selectedVoice(for language: DetectedLanguage) -> AVSpeechSynthesisVoice? {
        let profile = OnboardingStore.shared.profile
        return SystemVoiceResolver.resolveVoice(
            language: language,
            selectedIdentifier: profile.selectedVoiceIdentifier,
            preferredGender: profile.gptVoice.preferredSystemVoiceGender
        )
    }

    private func enqueueUtterance(text: String, language: DetectedLanguage, voice: AVSpeechSynthesisVoice?) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = OnboardingStore.shared.profile.speechRate.avPreviewRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.04
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: language.ttsLocaleIdentifier)
        synth.speak(utterance)
    }

    private func scheduleStartWatchdog() {
        cancelStartWatchdog()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isSpeaking, !self.hasStartedCurrentUtterance else { return }

            if !self.didAttemptDefaultFallback {
                self.didAttemptDefaultFallback = true
                self.synth.stopSpeaking(at: .immediate)
                self.enqueueUtterance(
                    text: self.pendingText,
                    language: self.pendingLanguage,
                    voice: AVSpeechSynthesisVoice(language: self.pendingLanguage.ttsLocaleIdentifier)
                )
                self.scheduleStartWatchdog()
                return
            }

            self.isSpeaking = false
            self.onFinished?()
        }
        speechStartWatchdogTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: task)
    }

    private func cancelStartWatchdog() {
        speechStartWatchdogTask?.cancel()
        speechStartWatchdogTask = nil
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechSynthesizerService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.hasStartedCurrentUtterance = true
            self.cancelStartWatchdog()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.cancelStartWatchdog()
            self.isSpeaking = false
            self.hasStartedCurrentUtterance = false
            self.didAttemptDefaultFallback = false
            self.onFinished?()
        }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.cancelStartWatchdog()
            self.isSpeaking = false
            self.hasStartedCurrentUtterance = false
            self.didAttemptDefaultFallback = false
            self.onFinished?()
        }
    }
}

private extension UserProfile.GPTVoice {
    var preferredSystemVoiceGender: SystemVoiceGender {
        switch self {
        case .ember:
            return .male
        case .jupiter:
            return .female
        }
    }
}
