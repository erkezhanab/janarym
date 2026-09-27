import AVFoundation
import Foundation
import Speech

enum OpenAIRealtimeState: Equatable {
    case disconnected
    case connecting
    case idle
    case recording
    case processing
    case speaking
}

final class OpenAIRealtimeService: NSObject, ObservableObject {

    private enum RequestTimeout {
        static let cameraDescription: TimeInterval = 180
        static let assistTurn: TimeInterval = 180
        static let proxy: TimeInterval = 180
        static let transcription: TimeInterval = 180
        static let chat: TimeInterval = 180
        static let tts: TimeInterval = 180
    }

    @Published private(set) var state: OpenAIRealtimeState = .disconnected
    @Published private(set) var isConnected = false
    @Published var errorMessage: String?

    var activeMode: AppMode = .general
    var onResponseText: ((String) -> Void)?
    var onTranscription:  ((String) -> Void)?
    var onFailure:        ((String) -> Void)?
    /// Called synchronously on main actor right before AVSpeechSynthesizer starts.
    /// Use this to pause AVAudioEngine-based services (VoiceCommandService) to avoid conflicts.
    var onWillSpeak: (() -> Void)?
    /// Called when any speech output fully finishes. `true` means the speech owned the
    /// main assistant UI state; `false` means it was an auxiliary announcement.
    var onDidFinishSpeaking: ((Bool) -> Void)?
    /// Extra context appended to the user prompt (e.g. location for navigation mode).
    var extraContextProvider: (() -> String)?

    /// Shared SpeechSynthesizerService (owned by AssistantCoordinator).
    /// Single instance prevents the dual-synth delegate race that muted AI voice.
    weak var speechService: SpeechSynthesizerService?

    private var recorder: AVAudioRecorder?
    private var player:   AVAudioPlayer?
    private var currentRecordingURL: URL?
    private var capturedFrameAtPTTStart: Data?
    private var cameraDescribeTask: Task<Void, Never>?

    // MARK: - STT (SFSpeechRecognizer-based PTT)
    private let sttEngine  = AVAudioEngine()
    private var sttRequest: SFSpeechAudioBufferRecognitionRequest?
    private var sttTask:    SFSpeechRecognitionTask?
    private var sttStopContinuation: CheckedContinuation<String, Never>?
    private var sttStopTimeoutTask: Task<Void, Never>?
    private var speechWatchdogTask: Task<Void, Never>?
    private var isSpeechOutputActive = false
    private var activeSpeechAffectsState = true
    private var bestSTTTranscript = ""
    private let networkSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = RequestTimeout.proxy
        configuration.timeoutIntervalForResource = RequestTimeout.proxy
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        if #available(iOS 13.0, *) {
            configuration.allowsConstrainedNetworkAccess = true
            configuration.allowsExpensiveNetworkAccess = true
        }
        return URLSession(configuration: configuration)
    }()

    private var currentLanguage: UserProfile.Language { OnboardingStore.shared.currentLanguage }
    private var currentPrompt:   String               { OnboardingStore.shared.assistantPrompt(for: activeMode) }
    private var currentGPTVoice: String               { OnboardingStore.shared.profile.gptVoice.openAIVoiceID }
    private var prefersLocalAssistantSpeech: Bool {
        return false // Always use the local API server's TTS (MMS TTS)
    }
    private var prefersServerSTTForCurrentLanguage: Bool {
        AppConfig.preferServerSTTForKazakhRussian && currentLanguage != .english && useProxy
    }

    // MARK: - Mode

    /// All AI traffic goes through the authenticated proxy; there is no direct mode.
    private var useProxy: Bool { !AppConfig.openAIProxyURL.isEmpty }

    override init() {
        super.init()
    }

    /// Called by AssistantCoordinator when the shared TTS finishes.
    /// Returns realtime state to .idle so the UI can show the next prompt.
    func markSpeechFinished() {
        runOnMain {
            self.finishSpeechOutput()
        }
    }

    // MARK: - Lifecycle

    func connect() {
        guard state == .disconnected || !isConnected else { return }
        guard useProxy else {
            publishError(AppError.missingAPIKey.localizedDescription)
            return
        }
        clearError()
        updateConnectionState(.idle, connected: true)
    }

    func disconnect() {
        stopRecording()
        stopPlayback()
        currentRecordingURL = nil
        capturedFrameAtPTTStart = nil
        updateConnectionState(.disconnected, connected: false)
    }

    func handleLanguageChange() {
        let shouldReconnect = isConnected
        disconnect()
        publishTranscription("")
        publishResponseText("")
        if shouldReconnect { connect() }
    }

    @MainActor
    func speakText(_ text: String, affectsState: Bool = true) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard state != .recording && state != .processing else { return }
        guard useProxy else { return }

        clearError()
        stopPlayback()

        if prefersLocalAssistantSpeech {
            speakLocally(text: trimmed, affectsState: affectsState)
            return
        }

        do {
            let audioBase64 = try await withTimeout(seconds: RequestTimeout.tts) {
                try await self.synthesiseSpeechViaProxy(text: trimmed)
            }
            try await outputSpeech(text: trimmed, audioBase64: audioBase64, affectsState: affectsState)
        } catch {
            speakLocally(text: trimmed, affectsState: affectsState)
        }
    }

    // MARK: - Camera-only description (no audio input)

    /// Captures GPT description of current camera frame and plays it via TTS.
    /// Called by ChildMainView or voice commands. promptOverride replaces default prompt when set.
    func describeCamera(frameJPEG: Data?, promptOverride: String? = nil) async {
        guard isConnected, state == .idle else { return }
        guard useProxy else { return }
        updateConnectionState(.processing, connected: true)

        do {
            let language = OnboardingStore.shared.profile.language
            let focusInstruction = OnboardingStore.shared.profile.focusMode.promptInstruction(language: language)
            let defaultPrompt: String
            switch language {
            case .kazakh:
                defaultPrompt = "Алдымда не тұр? Толық соқыр адамға арналған қысқа сипаттама бер. Заттардың қайда екенін айт: алдыңда, солда, оңда, аяғыңның алдында. Қашықтықты қадаммен айт (1 қадам ≈ 0.7 м). Мысалы: 'Алдыңда 2 қадамда үстел тұр, оң жақта қабырға.' Панике болдырма, тыныш тілде айт. Тек 1–2 сөйлем.\(focusInstruction)"
            case .russian:
                defaultPrompt = "Что передо мной? Дай краткое описание для полностью слепого человека. Говори где находится объект: впереди, слева, справа, у ног. Расстояние в шагах (1 шаг ≈ 0.7 м). Например: 'Впереди в 2 шагах стол, справа стена.' Говори спокойно, не паникуй. Только 1–2 предложения.\(focusInstruction)"
            case .english:
                defaultPrompt = "What is in front of me? Give a short description for a completely blind person. Say where objects are: ahead, left, right, or at my feet. Estimate distance in steps (1 step is about 0.7 m). Example: 'Ahead in 2 steps there is a table, with a wall on the right.' Speak calmly. Only 1-2 sentences.\(focusInstruction)"
            }
            let promptBase = promptOverride ?? defaultPrompt

            let response = try await withTimeout(seconds: RequestTimeout.cameraDescription) {
                try await self.describeCameraViaProxy(promptText: promptBase, frameJPEG: frameJPEG)
            }
            let responseText = response.responseText
            publishResponseText(responseText)
            try await outputSpeech(text: responseText, audioBase64: nil, affectsState: true)
        } catch {
            updateConnectionState(.idle, connected: true)
        }
    }

    /// Cancel any in-progress camera description and reset to idle
    func stopDescribing() {
        cameraDescribeTask?.cancel()
        cameraDescribeTask = nil
        stopPlayback()
        if state == .processing || state == .speaking {
            updateConnectionState(.idle, connected: true)
        }
    }

    @MainActor
    func startPTT(frameJPEG: Data? = nil) {
        clearError()
        capturedFrameAtPTTStart = frameJPEG
        publishTranscription("")
        publishResponseText("")
        if !isConnected { connect() }
        guard isConnected || state == .idle else { return }
        stopPlayback()
        beginSTTRecording()
    }

    @MainActor
    func stopPTTAndRespond(frameJPEG: Data? = nil) {
        guard state == .recording else { return }
        updateConnectionState(.processing, connected: true)
        let responseFrame = frameJPEG ?? capturedFrameAtPTTStart
        capturedFrameAtPTTStart = nil

        if recorder != nil {
            Task { [weak self] in
                await self?.finishTurn(frameJPEG: responseFrame)
            }
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let transcript = await self.collectFinalSTTTranscript()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !transcript.isEmpty {
                await self.finishTurnWithSTT(transcript: transcript, frameJPEG: responseFrame)
                return
            }

            guard responseFrame != nil else {
                self.updateConnectionState(.idle, connected: true)
                return
            }

            await self.finishTurnWithSTT(
                transcript: self.defaultSceneFallbackPrompt(),
                frameJPEG: responseFrame
            )
        }
    }

    // MARK: - STT Recording (SFSpeechRecognizer)

    @MainActor
    private func beginSTTRecording() {
        bestSTTTranscript = ""

        if prefersServerSTTForCurrentLanguage {
            beginRecording()
            return
        }

        // Check speech recognition authorization
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        guard authStatus == .authorized else {
            if authStatus == .notDetermined {
                SFSpeechRecognizer.requestAuthorization { [weak self] status in
                    DispatchQueue.main.async {
                        if status == .authorized {
                            self?.beginSTTRecording()
                        } else {
                            self?.beginRecording()
                        }
                    }
                }
            } else {
                beginRecording()
            }
            return
        }

        let languageCandidates: [String]
        switch currentLanguage {
        case .kazakh:
            languageCandidates = ["kk-KZ", "ru-RU"]
        case .russian:
            languageCandidates = ["ru-RU"]
        case .english:
            languageCandidates = ["en-US"]
        }
        let recognizer = languageCandidates.lazy
            .compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
            .first(where: \.isAvailable)
            ?? SFSpeechRecognizer(locale: Locale(identifier: languageCandidates[0]))

        guard recognizer?.isAvailable == true else {
            beginRecording()   // Fallback to AVAudioRecorder + Whisper
            return
        }

        AudioSessionManager.activate(.recording)
        sttEngine.stop()
        sttEngine.reset()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        if #available(iOS 16, *) { req.addsPunctuation = false }
        sttRequest = req

        let node = sttEngine.inputNode
        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak req] buf, _ in
            req?.append(buf)
        }

        sttEngine.prepare()
        do {
            try sttEngine.start()
        } catch {
            node.removeTap(onBus: 0)
            sttEngine.stop()
            sttEngine.reset()
            beginRecording()
            return
        }

        sttTask = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                if !text.isEmpty {
                    self.bestSTTTranscript = text
                    self.publishTranscription(text)
                }
                if result.isFinal {
                    self.completeSTTCollection(with: text)
                }
            }

            if error != nil {
                self.completeSTTCollection(with: self.bestSTTTranscript)
            }
        }

        updateConnectionState(.recording, connected: true)
    }

    private func stopSTTRecording() {
        sttStopTimeoutTask?.cancel()
        sttStopTimeoutTask = nil
        sttRequest?.endAudio()
        sttRequest = nil
        sttTask?.cancel()
        sttTask = nil
        sttEngine.inputNode.removeTap(onBus: 0)
        if sttEngine.isRunning { sttEngine.stop() }
        sttEngine.reset()
        if let continuation = sttStopContinuation {
            sttStopContinuation = nil
            continuation.resume(returning: bestSTTTranscript)
        }
    }

    // MARK: - STT → GPT finish turn

    private func finishTurnWithSTT(transcript: String, frameJPEG: Data?) async {
        do {
            publishTranscription(transcript)
            let response = try await withTimeout(seconds: RequestTimeout.assistTurn) {
                guard self.useProxy else { throw AppError.missingAPIKey }
                return try await self.sendViaProxy(
                    audioData: Data(),   // unused in text-only proxy path
                    frameJPEG: frameJPEG,
                    textOverride: transcript
                )
            }
            publishResponseText(response.responseText.trimmingCharacters(in: .whitespacesAndNewlines))
            try await outputSpeech(
                text: response.responseText.trimmingCharacters(in: .whitespacesAndNewlines),
                audioBase64: response.audioBase64,
                affectsState: true
            )
        } catch {
            publishError(error.localizedDescription)
            updateConnectionState(.idle, connected: true)
        }
    }

    private func collectFinalSTTTranscript() async -> String {
        await withCheckedContinuation { continuation in
            runOnMain {
                self.sttStopContinuation?.resume(returning: self.bestSTTTranscript)
                self.sttStopContinuation = continuation

                self.sttRequest?.endAudio()
                self.sttEngine.inputNode.removeTap(onBus: 0)
                if self.sttEngine.isRunning {
                    self.sttEngine.stop()
                }

                self.sttStopTimeoutTask?.cancel()
                self.sttStopTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    self?.completeSTTCollection(with: self?.bestSTTTranscript ?? "")
                }

                if self.sttTask == nil {
                    self.completeSTTCollection(with: self.bestSTTTranscript)
                }
            }
        }
    }

    private func completeSTTCollection(with transcript: String) {
        runOnMain {
            self.sttStopTimeoutTask?.cancel()
            self.sttStopTimeoutTask = nil
            self.sttRequest = nil
            self.sttTask?.cancel()
            self.sttTask = nil

            guard let continuation = self.sttStopContinuation else { return }
            self.sttStopContinuation = nil
            continuation.resume(returning: transcript)
        }
    }

    private func defaultSceneFallbackPrompt() -> String {
        switch currentLanguage {
        case .kazakh:
            return "Алдымда не тұр? Қысқа әрі нақты сипаттап бер."
        case .russian:
            return "Что передо мной? Опиши коротко и понятно."
        case .english:
            return "What is in front of me? Describe it briefly and clearly."
        }
    }

    // MARK: - Recording (AVAudioRecorder fallback)

    @MainActor
    private func beginRecording() {
        let url = makeRecordingURL()
        currentRecordingURL = url
        do {
            try configureRecordingSession()
            let settings: [String: Any] = [
                AVFormatIDKey:            Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey:          AppConfig.assistantAudioSampleRate,
                AVNumberOfChannelsKey:    1,
                AVEncoderBitRateKey:      AppConfig.assistantAudioBitRate,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = false
            recorder.prepareToRecord()
            guard recorder.record(forDuration: AppConfig.maxRecordingDuration) else {
                throw AppError.recordingFailed("Unable to start the recorder")
            }
            self.recorder = recorder
            updateConnectionState(.recording, connected: true)
        } catch {
            publishError(AppError.recordingFailed(error.localizedDescription).localizedDescription)
            updateConnectionState(.idle, connected: true)
        }
    }

    private func finishTurn(frameJPEG: Data?) async {
        stopRecording()
        guard let url = currentRecordingURL else {
            publishError(AppError.voiceInputFailed("Audio file is missing").localizedDescription)
            updateConnectionState(.idle, connected: true)
            return
        }
        do {
            let audioData = try Data(contentsOf: url)
            guard !audioData.isEmpty else { throw AppError.voiceInputFailed("Audio file is empty") }

            let response = try await withTimeout(seconds: RequestTimeout.assistTurn) {
                try await self.sendAssistRequest(audioData: audioData, frameJPEG: frameJPEG)
            }
            publishTranscription(response.transcript.trimmingCharacters(in: .whitespacesAndNewlines))
            publishResponseText(response.responseText.trimmingCharacters(in: .whitespacesAndNewlines))
            try await outputSpeech(
                text: response.responseText.trimmingCharacters(in: .whitespacesAndNewlines),
                audioBase64: response.audioBase64,
                affectsState: true
            )
        } catch {
            publishError(error.localizedDescription)
            updateConnectionState(.idle, connected: true)
        }
    }

    // MARK: - Request routing

    private func sendAssistRequest(audioData: Data, frameJPEG: Data?) async throws -> AssistResponse {
        guard useProxy else { throw AppError.missingAPIKey }
        return try await sendViaProxy(audioData: audioData, frameJPEG: frameJPEG)
    }

    // MARK: - Proxy mode

    // Text-only proxy call (STT transcript → GPT, no audio upload)
    private func sendViaProxy(audioData: Data, frameJPEG: Data?, textOverride: String) async throws -> AssistResponse {
        guard let url = URL(string: AppConfig.openAIProxyURL) else {
            throw AppError.networkError("Invalid OpenAI proxy URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = RequestTimeout.proxy
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let extraContext = extraContextProvider?() ?? ""
        let promptText = extraContext.isEmpty ? currentPrompt : "\(currentPrompt)\n\n\(extraContext)"

        var payload: [String: Any] = [
            "text": textOverride,
            "prompt": promptText,
            "language": currentLanguage.openAITranscriptionLanguageCode,
            "output_language": currentLanguage.assistantLanguageName,
            "response_model": AppConfig.openAIVisionModel,
            "voice": currentGPTVoice,
            "tts_model": AppConfig.openAITTSModel,
            "speed": OnboardingStore.shared.profile.speechRate.avRate,
            "include_audio": !prefersLocalAssistantSpeech
        ]
        if let jpg = frameJPEG, !jpg.isEmpty {
            payload["image_base64"] = jpg.base64EncodedString()
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        try await ProxyAuth.authorize(&request)

        let (data, response) = try await networkSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.networkError("No HTTP response from proxy")
        }
        guard (200...299).contains(http.statusCode) else {
            throw AppError.networkError(extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)")
        }
        let dto = try JSONDecoder().decode(AssistResponseDTO.self, from: data)
        guard !dto.responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.assistantResponseFailed(localizedEmptyProxyResponseMessage())
        }
        return AssistResponse(
            transcript: textOverride,
            responseText: dto.responseText,
            audioBase64: dto.audioBase64
        )
    }

    private func sendViaProxy(audioData: Data, frameJPEG: Data?) async throws -> AssistResponse {
        guard let url = URL(string: AppConfig.openAIProxyURL) else {
            throw AppError.networkError("Invalid OpenAI proxy URL")
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = RequestTimeout.proxy
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipartBody(boundary: boundary, audioData: audioData, frameJPEG: frameJPEG)
        try await ProxyAuth.authorize(&request)

        let (data, response) = try await networkSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.networkError("No HTTP response from proxy")
        }
        guard (200...299).contains(http.statusCode) else {
            throw AppError.networkError(extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)")
        }
        let dto = try JSONDecoder().decode(AssistResponseDTO.self, from: data)
        guard !dto.responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.assistantResponseFailed(localizedEmptyProxyResponseMessage())
        }
        return AssistResponse(transcript: dto.transcript, responseText: dto.responseText, audioBase64: dto.audioBase64)
    }

    private func describeCameraViaProxy(promptText: String, frameJPEG: Data?) async throws -> AssistResponse {
        guard let url = URL(string: AppConfig.openAIProxyURL) else {
            throw AppError.networkError("Invalid OpenAI proxy URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = RequestTimeout.cameraDescription
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": promptText,
            "prompt": currentPrompt,
            "language": currentLanguage.openAITranscriptionLanguageCode,
            "output_language": currentLanguage.assistantLanguageName,
            "response_model": AppConfig.openAIVisionModel,
            "image_base64": frameJPEG?.base64EncodedString() ?? "",
            "voice": currentGPTVoice,
            "tts_model": AppConfig.openAITTSModel,
            "speed": OnboardingStore.shared.profile.speechRate.avRate,
            "include_audio": !prefersLocalAssistantSpeech
        ])
        try await ProxyAuth.authorize(&request)

        let (data, response) = try await networkSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.networkError("No HTTP response from proxy")
        }
        guard (200...299).contains(http.statusCode) else {
            throw AppError.networkError(extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)")
        }
        let dto = try JSONDecoder().decode(AssistResponseDTO.self, from: data)
        guard !dto.responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.assistantResponseFailed(localizedEmptyProxyResponseMessage())
        }
        return AssistResponse(
            transcript: dto.transcript.isEmpty ? promptText : dto.transcript,
            responseText: dto.responseText,
            audioBase64: dto.audioBase64
        )
    }

    private func synthesiseSpeechViaProxy(text: String) async throws -> String {
        guard let url = URL(string: AppConfig.openAIProxyURL) else {
            throw AppError.networkError("Invalid OpenAI proxy URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = RequestTimeout.tts
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "prompt": currentPrompt,
            "language": currentLanguage.openAITranscriptionLanguageCode,
            "output_language": currentLanguage.assistantLanguageName,
            "voice": currentGPTVoice,
            "tts_model": AppConfig.openAITTSModel,
            "speed": OnboardingStore.shared.profile.speechRate.avRate,
            "include_audio": true,
            "task": "tts"
        ])
        try await ProxyAuth.authorize(&request)

        let (data, response) = try await networkSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.networkError("No HTTP response from proxy")
        }
        guard (200...299).contains(http.statusCode) else {
            throw AppError.networkError(extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)")
        }

        let dto = try JSONDecoder().decode(AssistResponseDTO.self, from: data)
        guard let audioBase64 = dto.audioBase64, !audioBase64.isEmpty else {
            throw AppError.ttsFailed("Proxy returned empty audio")
        }
        return audioBase64
    }

    // MARK: - Multipart body (proxy mode)

    private func buildMultipartBody(boundary: String, audioData: Data, frameJPEG: Data?) -> Data {
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        func file(_ name: String, _ filename: String, _ mime: String, _ data: Data) {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n")
            body.append(data)
            append("\r\n")
        }
        field("language",            currentLanguage.openAITranscriptionLanguageCode)
        field("voice",               currentGPTVoice)
        field("prompt",              currentPrompt)
        field("response_model",      AppConfig.openAIVisionModel)
        field("transcription_model", AppConfig.openAITranscriptionModel)
        field("tts_model",           AppConfig.openAITTSModel)
        field("mode",                activeMode.modeKey)
        field("speech_rate",         "\(OnboardingStore.shared.profile.speechRate.avRate)")
        field("include_audio",       prefersLocalAssistantSpeech ? "0" : "1")
        file("audio", "speech.m4a", "audio/mp4", audioData)
        if let jpg = frameJPEG, !jpg.isEmpty { file("image", "frame.jpg", "image/jpeg", jpg) }
        append("--\(boundary)--\r\n")
        return body
    }

    // MARK: - Playback

    @MainActor
    private func outputSpeech(text: String, audioBase64: String?, affectsState: Bool) async throws {
        guard !text.isEmpty else {
            updateConnectionState(.idle, connected: true)
            return
        }

        if prefersLocalAssistantSpeech || audioBase64?.isEmpty != false {
            speakLocally(text: text, affectsState: affectsState)
            return
        }

        do {
            try await playReturnedAudio(base64: audioBase64!, affectsState: affectsState)
        } catch {
            stopPlayback()
            speakLocally(text: text, affectsState: affectsState)
        }
    }

    @MainActor
    private func playReturnedAudio(base64: String, affectsState: Bool) async throws {
        guard let audioData = Data(base64Encoded: base64) else {
            throw AppError.ttsFailed("Unable to decode returned audio")
        }
        prepareForSpeechOutput(mode: .playback)
        let player = try AVAudioPlayer(data: audioData)
        player.delegate = self
        player.prepareToPlay()
        self.player = player
        beginSpeechOutput(affectsState: affectsState)
        scheduleSpeechWatchdog(forTextLength: audioData.count / 24)
        guard player.play() else {
            self.player = nil
            stopPlayback()
            throw AppError.ttsFailed("Unable to start playback")
        }
    }

    @MainActor
    private func speakLocally(text: String, affectsState: Bool) {
        prepareForSpeechOutput(mode: .playback)
        beginSpeechOutput(affectsState: affectsState)
        scheduleSpeechWatchdog(forTextLength: text.count)
        guard let speech = speechService else {
            // No injected TTS → stay speaking briefly then return to idle
            finishSpeechOutput()
            return
        }
        // Detect the actual language of the response text so that, e.g.,
        // a Russian GPT reply is read with a Russian voice even when the
        // user profile is set to Kazakh.
        let resolvedLanguage = LanguageResolver.resolve(text: text)
        speech.speak(text, language: resolvedLanguage)
    }

    // MARK: - Audio session helpers

    private func stopRecording() { recorder?.stop(); recorder = nil }
    private func stopSpeechOutputEngines() {
        speechWatchdogTask?.cancel()
        speechWatchdogTask = nil
        speechService?.stop()
        player?.stop()
        player = nil
    }
    private func stopPlayback()  {
        stopSpeechOutputEngines()
        isSpeechOutputActive = false
        activeSpeechAffectsState = true
    }

    func stopAllInput() {
        stopSTTRecording()
        stopRecording()
    }

    @MainActor
    private func prepareForSpeechOutput(mode: AudioSessionManager.Mode) {
        onWillSpeak?()
        stopSTTRecording()
        stopRecording()
        AudioSessionManager.activate(mode, force: true)
    }

    private func scheduleSpeechWatchdog(forTextLength length: Int) {
        speechWatchdogTask?.cancel()
        let seconds = max(6.0, min(18.0, Double(max(length, 1)) / 12.0))
        speechWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.runOnMain {
                guard self.isSpeechOutputActive else { return }
                self.stopSpeechOutputEngines()
                self.finishSpeechOutput()
            }
        }
    }

    private func beginSpeechOutput(affectsState: Bool) {
        isSpeechOutputActive = true
        activeSpeechAffectsState = affectsState
        if affectsState {
            updateConnectionState(.speaking, connected: true)
        }
    }

    private func finishSpeechOutput() {
        speechWatchdogTask?.cancel()
        speechWatchdogTask = nil

        let hadActiveSpeech = isSpeechOutputActive
        let affectedState = activeSpeechAffectsState
        isSpeechOutputActive = false
        activeSpeechAffectsState = true

        if affectedState && (state == .speaking || state == .processing) {
            updateConnectionState(.idle, connected: true)
        }
        guard hadActiveSpeech else { return }
        onDidFinishSpeaking?(affectedState)
    }

    @MainActor
    private func configureRecordingSession() throws {
        AudioSessionManager.activate(.recording)
    }

    @MainActor
    private func configurePlaybackSession() throws {
        AudioSessionManager.activate(.playback)
    }

    private func makeRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("janarym-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
    }

    // MARK: - Helpers

    private func extractErrorMessage(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = json["error"] as? [String: Any], let msg = err["message"] as? String, !msg.isEmpty { return msg }
            if let msg = json["message"] as? String, !msg.isEmpty { return msg }
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AppError.networkError("Request timed out")
            }

            guard let result = try await group.next() else {
                throw AppError.networkError("Unexpected empty response from task group")
            }
            group.cancelAll()
            return result
        }
    }

    private func publishError(_ message: String) {
        runOnMain { self.errorMessage = message; self.onFailure?(message) }
    }
    private func clearError() {
        runOnMain { self.errorMessage = nil }
    }
    private func publishTranscription(_ text: String) {
        runOnMain { self.onTranscription?(text) }
    }
    private func publishResponseText(_ text: String) {
        runOnMain { self.onResponseText?(text) }
    }
    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }
    private func updateConnectionState(_ newState: OpenAIRealtimeState, connected: Bool) {
        if Thread.isMainThread {
            state = newState
            isConnected = connected
        } else {
            DispatchQueue.main.async { self.state = newState; self.isConnected = connected }
        }
    }
}

// MARK: - AVAudio delegates

extension OpenAIRealtimeService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag && state == .recording {
            publishError(AppError.recordingFailed("Recording stopped unexpectedly").localizedDescription)
            updateConnectionState(.idle, connected: true)
        }
    }
}

extension OpenAIRealtimeService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        DispatchQueue.main.async {
            guard self.player === player else { return }
            self.player = nil
            self.finishSpeechOutput()
        }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard self.player === player else { return }
        self.player = nil
        publishError(AppError.ttsFailed(error?.localizedDescription ?? "Audio decode failed").localizedDescription)
        DispatchQueue.main.async {
            self.finishSpeechOutput()
        }
    }
}

// MARK: - Private models

private struct AssistResponseDTO: Decodable {
    let transcript:   String
    let responseText: String
    let audioBase64:  String?

    enum CodingKeys: String, CodingKey {
        case transcript
        case responseText = "response_text"
        case audioBase64  = "audio_base64"
        case response
        case text
        case message
        case outputText = "output_text"
        case audio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript) ?? ""
        responseText =
            try container.decodeIfPresent(String.self, forKey: .responseText)
            ?? container.decodeIfPresent(String.self, forKey: .response)
            ?? container.decodeIfPresent(String.self, forKey: .outputText)
            ?? container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .text)
            ?? ""
        audioBase64 =
            try container.decodeIfPresent(String.self, forKey: .audioBase64)
            ?? container.decodeIfPresent(String.self, forKey: .audio)
    }
}

private struct AssistResponse {
    let transcript:   String
    let responseText: String
    let audioBase64:  String?
}

private extension UserProfile.Language {
    var openAITranscriptionLanguageCode: String {
        switch self {
        case .kazakh:  return "kk"
        case .russian: return "ru"
        case .english: return "en"
        }
    }
}

private func localizedEmptyProxyResponseMessage() -> String {
    AppText.pick(
        "Ассистенттен жауап келмеді. Қайта айтып көріңіз.",
        "Ассистент не вернул ответ. Попробуйте повторить запрос.",
        en: "The assistant did not return an answer. Please try again."
    )
}
