import Speech
import AVFoundation

// MARK: - Command enum

enum RecognizedVoiceCommand: Equatable {
    // Navigation / UI
    case settings
    case medCard
    case readMedCard
    case back
    case whereIsParent
    case sos
    case navigation          // навигация режимін қос
    case arGlasses           // AR көзілдірік режимін қос
    case whereAmI            // мен қайдамын / где я
    // Camera actions
    case describeScene       // алдымда не бар
    case scanMedicine        // дәрі сканерле
    case readText            // мәтін оқы
    case scanBarcode         // штрих-код сканерле
    case startVideoRecording // видеоға түсір
    case stopVideoRecording  // видеоны тоқтат
    // Torch
    case torchOn
    case torchOff
    case torchToggle
    // Utility
    case askTime
    case wakeWord
    // Customization — voice-driven settings
    case setFocusAll
    case setFocusPeople
    case setFocusText
    case setFocusObjects
    case setSpeechRateSlow
    case setSpeechRateNormal
    case setSpeechRateFast
    case setResponseShort
    case setResponseMedium
    case setResponseLong
    case setVoiceMale
    case setVoiceFemale
    case setFormalityFormal
    case setFormalityInformal
}

// MARK: - Service

final class VoiceCommandService: NSObject, ObservableObject {
    
    @Published private(set) var isListening = false
    @Published private(set) var lastCommand: RecognizedVoiceCommand?
    
    // MARK: - Private
    
    private var recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    
    private var isActive  = false
    private var isPaused  = false
    private var restartTimer: Timer?
    
    // Prevent the same command from re-firing on partial transcripts.
    private var lastFiredCommand: RecognizedVoiceCommand?
    private var lastFiredAt:  Date = .distantPast
    private let commandDebounceWindow: TimeInterval = 0.9
    
    private let wakeWordKeywords = ["жанарым", "janarym"]

    private let commandMap: [(keywords: [String], cmd: RecognizedVoiceCommand)] = [
        // SOS — highest safety priority
        (["sos", "сос", "жәрдем", "қауіп", "помощь", "тревога", "спасите"],                  .sos),
         
        // Camera — medicine scan
        (["дәрі сканерле", "дәрілік сканерле", "препарат сканерле",
          "таблетка тексер", "дәрі тексер", "медикамент тексер",
          "сканируй лекарство", "проверь таблетку", "что за лекарство",
          "что за таблетка", "распознай лекарство"],                                        .scanMedicine),

        // Camera — read text
        (["мәтін оқы", "жазуды оқы", "не жазылған", "оқып бер",
          "прочитай текст", "что написано", "прочитай", "прочти"],                         .readText),

        // Camera — scan barcode / product
        (["штрих-код сканерле", "бар-код сканерле", "өнімді тексер",
          "сканируй штрихкод", "считай штрихкод", "что за продукт"],                       .scanBarcode),

        // Camera — record video
        (["видеоны тоқтат", "видео тоқтат", "видеоны сакта", "видеоны сақта",
          "тоқтат видеоны", "видео тоқта", "видеоны тоқта", "видео бітір", "видеоны бітір",
          "останови видео", "стоп видео", "останови съемку", "закончить видео"],           .stopVideoRecording),
        (["видеоға түсір", "видео тусир", "видео түсір", "видеоны түсір", "видеоны тусир",
          "видеоға жаз", "видео жаз", "бейне түсір", "бейнені түсір",
          "бейнежазба жаса", "запиши видео", "сними видео"],                               .startVideoRecording),

        // Camera — describe scene (general)
        (["алдымда не бар", "суретті сипатта", "не көрінеді", "қоршаған ортаны сипатта",
          "опиши что вижу", "что передо мной", "что вокруг", "опиши окружение"],           .describeScene),

        // Navigation / UI
        (["медкартамды оқы", "мед картамды оқы", "медкартаны оқы", "мед картаны оқы",
          "медкартаны оқып бер", "медкартамды айт", "медкарта мәліметін айт",
          "диктуй медкарту", "прочитай медкарту", "озвучь медкарту"],                    .readMedCard),
        (["баптаулар", "настройки", "баптауды аш", "открой настройки"],                     .settings),
        (["медкарта", "медициналық карта", "мед карта", "медкарту", "медицинская карта",
          "мед картаны аш", "медкартаны аш", "открой медкарту", "открой мед карту"],       .medCard),
        (["артқа", "үй", "назад", "домой", "вернись"],                                     .back),
        (["анам қайда", "әкем қайда", "ата-анам қайда", "родители где", "где родители"],  .whereIsParent),

        // Navigation mode
        (["навигация", "навигацияны қос", "жолды көрсет", "маршрут", "маршрутты қос",
          "включи навигацию", "покажи дорогу", "построй маршрут"],                          .navigation),
        (["ar", "ar режим", "ar режім", "ar режимін қос", "ar режимди кос",
          "ar көзілдірік", "ar көзілдірік режимі", "көзілдірік режимі",
          "включи ar", "режим ar", "ar очки", "режим ar очков", "включи ar очки"],         .arGlasses),

        // Where am I
        (["мен қайдамын", "қайдамын", "мен қайдамын қазір", "мекен-жайым",
          "где я", "где я нахожусь", "мой адрес", "какой адрес"],                          .whereAmI),

        // Torch
        (["фонарь қос", "фонарьды қос", "фонарь жақ", "фонарь іске қос",
          "фонарик қос", "фонарикті қос", "фонарик жак", "фонарик кос",
          "включи фонарь", "фонарик включи", "включи фонарик"],                             .torchOn),
        (["фонарь өшір", "фонарьды өшір", "фонарик өшір", "фонарикті өшір",
          "фонарик ошир", "выключи фонарь", "фонарик выключи", "выключи фонарик"],         .torchOff),
        (["фонарь", "фонарик"],                                                             .torchToggle),

        // Time
        (["сағат нешеде", "сағат нешe", "неше сағат", "уақыт",
          "который час", "сколько времени", "который час сейчас"],                          .askTime),

        // Customization — Focus mode
        (["фокус барлығы", "барлығын көрсет", "барлық режим",
          "фокус всё", "режим всё", "покажи всё", "описывай всё"],                          .setFocusAll),
        (["фокус адамдар", "адамдар режимі", "тек адамдарды",
          "фокус люди", "режим людей", "только люди", "показывай людей"],                    .setFocusPeople),
        (["фокус мәтін", "мәтін режимі", "тек мәтін",
          "фокус текст", "режим текста", "только текст", "читай текст"],                     .setFocusText),
        (["фокус заттар", "заттар режимі", "тек заттарды",
          "фокус предметы", "режим предметов", "только предметы"],                           .setFocusObjects),

        // Customization — Speech rate
        (["баяу сөйле", "жылдамдық баяу", "баяу режим",
          "говори медленно", "скорость медленно", "медленная скорость"],                      .setSpeechRateSlow),
        (["қалыпты жылдамдық", "қалыпты сөйле", "жылдамдық қалыпты",
          "обычная скорость", "говори нормально", "скорость нормально"],                      .setSpeechRateNormal),
        (["жылдам сөйле", "жылдамдық жылдам", "жылдам режим",
          "говори быстро", "скорость быстро", "быстрая скорость"],                           .setSpeechRateFast),

        // Customization — Response length
        (["қысқа жауап", "жауапты қысқа", "қысқа режим",
          "короткий ответ", "отвечай кратко", "краткий ответ"],                              .setResponseShort),
        (["орташа жауап", "жауапты орташа",
          "средний ответ", "умеренный ответ", "отвечай умеренно"],                            .setResponseMedium),
        (["толық жауап", "жауапты толық", "ұзын жауап",
          "подробный ответ", "отвечай подробно", "длинный ответ"],                            .setResponseLong),

        // Customization — GPT voice
        (["ер дауыс", "ер адам дауысы", "еркек дауыс",
          "мужской голос", "голос мужской", "включи мужской"],                                .setVoiceMale),
        (["әйел дауыс", "әйел адам дауысы", "әйел дауысы",
          "женский голос", "голос женский", "включи женский"],                                .setVoiceFemale),

        // Customization — Formality
        (["сіз деп жүгін", "ресми жүгін", "ресми сөйле",
          "обращайся на вы", "говори на вы", "формально"],                                   .setFormalityFormal),
        (["сен деп жүгін", "жайлы жүгін", "жайлы сөйле",
          "обращайся на ты", "говори на ты", "неформально"],                                 .setFormalityInformal),
    ]

    // MARK: - Init

    override init() {
        super.init()
    }

    // MARK: - Public API

    func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self, status == .authorized else { return }
            DispatchQueue.main.async {
                self.isActive = true
                self.isPaused = false
                self.startCycle()
            }
        }
    }

    func stop() {
        isActive  = false
        isPaused  = false
        teardown()
        DispatchQueue.main.async { self.isListening = false }
    }

    /// Call before PTT recording starts to avoid AVAudioEngine conflicts
    func pause() {
        guard !isPaused else { return }
        isPaused = true
        teardown()
        DispatchQueue.main.async { self.isListening = false }
    }

    /// Call after PTT recording finishes
    func resume() {
        guard isActive, isPaused else { return }
        isPaused = false
        startCycle()
    }

    // MARK: - Cycle

    private func startCycle() {
        guard isActive, !isPaused else { return }
        teardown()
        configureRecognizerForCurrentLanguage()

        guard let rec = recognizer, rec.isAvailable else {
            scheduleRestart(after: 3); return
        }

        AudioSessionManager.activate(.idle, force: true)
        audioEngine.stop()
        audioEngine.reset()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        req.contextualStrings = Array(Set(commandMap.flatMap(\.keywords) + wakeWordKeywords))
        recognitionRequest = req

        let node = audioEngine.inputNode
        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak req] buf, _ in
            req?.append(buf)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            node.removeTap(onBus: 0)
            audioEngine.stop()
            audioEngine.reset()
            scheduleRestart(after: 2); return
        }

        DispatchQueue.main.async { self.isListening = true }

        recognitionTask = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.match(text: result.bestTranscription.formattedString)
            }
            if error != nil || result?.isFinal == true {
                self.scheduleRestart(after: 0.4)
            }
        }

        // Restart before Apple's 60 s hard limit
        scheduleAutoRestart(after: 50)
    }

    private func match(text: String) {
        let lower = normalized(text)
        let now   = Date()

        let strippedWakeText = stripWakeWords(from: lower)

        if let matched = heuristicCommand(in: strippedWakeText)
            ?? heuristicCommand(in: lower)
            ?? firstMatchingCommand(in: strippedWakeText)
            ?? firstMatchingCommand(in: lower) {
            guard shouldEmit(command: matched, at: now) else { return }
            DispatchQueue.main.async { self.lastCommand = matched }
            return
        }

        guard containsWakeWord(in: lower) else { return }
        guard shouldEmit(command: .wakeWord, at: now) else { return }
        DispatchQueue.main.async { self.lastCommand = .wakeWord }
    }

    // MARK: - Helpers

    private func teardown() {
        restartTimer?.invalidate(); restartTimer = nil
        recognitionTask?.cancel(); recognitionTask = nil
        recognitionRequest?.endAudio(); recognitionRequest = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.reset()
    }

    private func scheduleRestart(after delay: TimeInterval) {
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, self.isActive, !self.isPaused else { return }
            self.startCycle()
        }
    }

    private func scheduleAutoRestart(after delay: TimeInterval) {
        // Only sets if no existing restart is pending
        guard restartTimer == nil else { return }
        restartTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, self.isActive, !self.isPaused else { return }
            self.startCycle()
        }
    }

    private func configureRecognizerForCurrentLanguage() {
        let localeCandidates: [String]
        switch OnboardingStore.shared.currentLanguage {
        case .kazakh:
            localeCandidates = ["kk-KZ", "ru-RU"]
        case .russian:
            localeCandidates = ["ru-RU"]
        case .english:
            localeCandidates = ["en-US"]
        }

        if let recognizer, localeCandidates.contains(recognizer.locale.identifier) {
            return
        }

        recognizer = localeCandidates.lazy
            .compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
            .first(where: \.isAvailable)
            ?? SFSpeechRecognizer(locale: Locale(identifier: localeCandidates[0]))
        recognizer?.delegate = self
    }

    private func firstMatchingCommand(in text: String) -> RecognizedVoiceCommand? {
        guard !text.isEmpty else { return nil }
        for entry in commandMap {
            for kw in entry.keywords where text.contains(normalized(kw)) {
                return entry.cmd
            }
        }
        return nil
    }

    private func heuristicCommand(in text: String) -> RecognizedVoiceCommand? {
        guard !text.isEmpty else { return nil }

        if containsAny(in: text, words: ["фонарик", "фонарикті", "фонарь", "жарық"]) {
            if containsAny(in: text, words: ["қос", "кос", "жақ", "включи"]) {
                return .torchOn
            }
            if containsAny(in: text, words: ["өшір", "ошир", "өшур", "выключи"]) {
                return .torchOff
            }
        }

        let containsVideoStem =
            text.contains("виде") ||
            text.contains("бейне") ||
            text.contains("бейнежаз") ||
            text.contains("бейн")

        if containsVideoStem {
            let wantsStop =
                text.contains("тоқт") ||
                text.contains("токт") ||
                text.contains("стоп") ||
                text.contains("останов") ||
                text.contains("сақ") ||
                text.contains("сак") ||
                text.contains("біт") ||
                text.contains("бит") ||
                text.contains("закон")

            if wantsStop {
                return .stopVideoRecording
            }

            if containsAny(in: text, words: ["түсір", "тусир", "тусір", "түсыр", "түс", "тус", "жаз", "сними", "запиши", "записывай"]) {
                return .startVideoRecording
            }

            // For demo stability, any generic "video" request without stop words starts recording.
            return .startVideoRecording
        }

        if text.contains("мед") && text.contains("карт") {
            if containsAny(in: text, words: ["оқы", "окы", "оқып", "айт", "айтшы", "озвуч", "дикт", "прочитай"]) {
                return .readMedCard
            }
        }

        let hasARStem =
            text.contains(" ar ") ||
            text.hasPrefix("ar ") ||
            text.hasSuffix(" ar") ||
            text == "ar" ||
            text.contains("очки") ||
            text.contains("очк") ||
            text.contains("көзілдір") ||
            text.contains("козилдир")

        if hasARStem,
           containsAny(in: text, words: ["қос", "кос", "режим", "режімі", "режимі", "включи", "mode"]) {
            return .arGlasses
        }

        return nil
    }

    private func containsAny(in text: String, words: [String]) -> Bool {
        words.contains { text.contains(normalized($0)) }
    }

    private func shouldEmit(command: RecognizedVoiceCommand, at now: Date) -> Bool {
        if lastFiredCommand == command, now.timeIntervalSince(lastFiredAt) <= commandDebounceWindow {
            return false
        }
        lastFiredCommand = command
        lastFiredAt = now
        return true
    }

    private func containsWakeWord(in text: String) -> Bool {
        StringNormalizer.containsWakeWord(text)
    }

    private func stripWakeWords(from text: String) -> String {
        let stripped = wakeWordKeywords.reduce(text) { partial, word in
            partial.replacingOccurrences(of: word, with: " ")
        }
        return normalizeSpaces(in: stripped)
    }

    private func normalized(_ text: String) -> String {
        normalizeSpaces(
            in: text
                .lowercased()
                .replacingOccurrences(of: "-", with: " ")
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .joined(separator: " ")
        )
    }

    private func normalizeSpaces(in text: String) -> String {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension VoiceCommandService: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer,
                          availabilityDidChange available: Bool) {
        if available, isActive, !isPaused {
            startCycle()
        }
    }
}
