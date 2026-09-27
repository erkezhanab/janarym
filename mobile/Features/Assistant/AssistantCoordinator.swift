import AVFoundation
import Combine
import SwiftUI
import UIKit

@MainActor
final class AssistantCoordinator: ObservableObject {

    private enum VisionFrame {
        static let maxEdge: CGFloat = 384
    }

    // MARK: - Published state

    @Published var mode: AssistantMode = .idle
    @Published var liveTranscript: String = ""
    @Published var liveResponseText: String = ""
    @Published var errorMessage: String?

    @Published var activeMode: AppMode = .general {
        didSet { handleModeChange(from: oldValue, to: activeMode) }
    }

    @Published private(set) var isOfflineMode: Bool = false

    // MARK: - Services

    let cameraService     = CameraService()
    let permissionManager = PermissionManager()
    let locationService   = LocationService()
    let realtimeService   = OpenAIRealtimeService()
    let voiceCommands     = VoiceCommandService()
    let esp32Camera       = ESP32CameraService()
    private(set) lazy var ttsService = SpeechSynthesizerService()
    private let onboarding = OnboardingStore.shared

    // UI commands forwarded to the view
    @Published var uiCommand: RecognizedVoiceCommand?

    // MARK: - Private

    private var isMainViewVisible = false
    private var callbacksReady = false
    private var voiceCommandObserversReady = false
    private var pendingVoiceCommandResumeAfterLocalSpeech = false
    private var capturedFrameAtPTTStart: Data?
    private var cancellables = Set<AnyCancellable>()
    private var pttTask: Task<Void, Never>?
    private var pttProcessingTimeout: Task<Void, Never>?
    private var videoStartAnnouncementTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        realtimeService.activeMode = activeMode
        observeLanguageChanges()
        observeNetworkStatus()
    }

    // MARK: - Lifecycle

    func onAppear() {
        permissionManager.checkAll()
        if !permissionManager.allGranted {
            permissionManager.requestAll()
        }
        activateAssistantIfPossible()
    }

    func onBecameActive() {
        permissionManager.checkAll()
        guard isMainViewVisible else { return }
        if activeMode == .arGlasses {
            esp32Camera.discoverHostViaBluetooth()
            esp32Camera.startPolling()
        }
        if activeMode != .arGlasses, !cameraService.isRunning { cameraService.start() }
    }

    func onResignActive() {
        ttsService.stop()
        esp32Camera.stopPolling(preserveLatestFrame: true)
        if isMainViewVisible { cameraService.stop() }
    }

    func onPermissionsGranted() {
        permissionManager.checkAll()
        guard isMainViewVisible, permissionManager.allGranted else { return }
    }

    func onMainViewAppear() {
        isMainViewVisible = true
        if !permissionManager.allGranted {
            permissionManager.requestAll()
        }
        // Camera starts first — it calls startRunning() which is a blocking hardware
        // init on first launch. VoiceCommandService (AVAudioEngine) must NOT start
        // simultaneously as it competes for audio hardware resources.
        activateAssistantIfPossible()
        if activeMode == .arGlasses {
            esp32Camera.discoverHostViaBluetooth()
            esp32Camera.startPolling()
            cameraService.stop()
        }
        observeVoiceCommands()

        // Delay voice commands and presence so camera session gets exclusive access
        // to system audio hardware during its blocking startRunning() call.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)   // 2 s — camera startup window
            guard let self, self.isMainViewVisible else { return }
            self.voiceCommands.start()
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)   // 3 s — after camera + voice ready
            guard let self, self.isMainViewVisible else { return }
            self.startPresenceAndSOS()
        }
    }

    func onMainViewDisappear() {
        isMainViewVisible = false
        ttsService.stop()
        cameraService.stop()
        esp32Camera.stopPolling(preserveLatestFrame: true)
        realtimeService.disconnect()
        voiceCommands.stop()
        SOSManager.shared.stopMonitoring()
        UserPresenceService.shared.stop()
    }

    // MARK: - PTT (Push-to-Talk)

    func startPTT() {
        pttTask?.cancel(); pttTask = nil
        pttProcessingTimeout?.cancel(); pttProcessingTimeout = nil

        mode = .recording
        if activeMode != .arGlasses {
            HapticService.shared.single()
        }
        ttsService.stop()
        voiceCommands.pause()

        let frameJPEG = currentVisionFrame(maxEdge: VisionFrame.maxEdge)
        capturedFrameAtPTTStart = frameJPEG

        realtimeService.connect()
        realtimeService.startPTT(frameJPEG: frameJPEG)
    }

    func stopPTT() {
        pttTask?.cancel(); pttTask = nil

        guard realtimeService.state == .recording else {
            mode = .idle
            capturedFrameAtPTTStart = nil
            voiceCommands.resume()
            return
        }

        mode = .processing

        let frameJPEG = currentVisionFrame(maxEdge: VisionFrame.maxEdge)
        if activeMode == .arGlasses, frameJPEG == nil {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let remoteFrame = await self.esp32Camera.fetchSnapshot()
                self.finishPTTResponse(with: remoteFrame ?? self.capturedFrameAtPTTStart)
            }
            return
        }
        finishPTTResponse(with: frameJPEG ?? capturedFrameAtPTTStart)
    }

    // MARK: - Presence + SOS

    private func startPresenceAndSOS() {
        guard AppConfig.presenceMonitoringEnabled else { return }
        guard AuthServiceHolder.shared.currentRole?.isStandardUser == true else { return }
        guard let uid = AuthServiceHolder.shared.currentUID else { return }
        UserPresenceService.shared.capturePhoto = { [weak self] in
            guard let self else { return nil }
            return self.currentVisionFrame(maxEdge: 512)
        }
        UserPresenceService.shared.start(userId: uid)

        SOSManager.shared.startMonitoring()
        SOSManager.shared.onSOS = { [weak self] in
            self?.triggerSOS()
        }
    }

    func triggerSOS() {
        guard AuthServiceHolder.shared.currentRole?.isStandardUser == true else { return }
        let language: DetectedLanguage = OnboardingStore.shared.profile.language.detectedLanguage

        HapticService.shared.sos()
        let sosPhrase  = JanarymVoice.shared.sosSent(language: language)
        let medReadout = MedCardViewModel.shared.sosReadoutText()
        let fullText   = medReadout.isEmpty ? sosPhrase : "\(sosPhrase) \(medReadout)"
        speakVoiceFeedback(fullText, language: language)

        guard let uid = AuthServiceHolder.shared.currentUID else { return }
        let loc = UserPresenceService.shared.lastLocation
        if loc == nil {
            print("AssistantCoordinator: SOS triggered without location — sending with (0, 0)")
        }
        Task {
            await FirestoreService.shared.triggerSOS(
                userId: uid,
                lat: loc?.coordinate.latitude ?? 0,
                lng: loc?.coordinate.longitude ?? 0
            )
        }
    }

    // MARK: - Mode change

    private func handleModeChange(from old: AppMode, to new: AppMode) {
        realtimeService.activeMode = new
        let lang: DetectedLanguage = onboarding.profile.language.detectedLanguage
        let kk = lang == .kazakh
        switch new {
        case .navigation:
            locationService.start()
            speakVoiceFeedback(kk ? "Навигация режимі қосылды." : "Режим навигации включён.", language: lang)
        case .arGlasses:
            cameraService.stop()
            esp32Camera.discoverHostViaBluetooth()
            esp32Camera.startPolling()
            speakVoiceFeedback(kk ? "AR көзілдірік режимі. Дауыспен басқарыңыз." : "Режим AR очков. Управляйте голосом.", language: lang)
        default:
            if old == .navigation { locationService.stop() }
            if old == .arGlasses {
                esp32Camera.stopPolling(preserveLatestFrame: true)
                speakVoiceFeedback(kk ? "AR режимі өшірілді." : "Режим AR очков выключен.", language: lang)
            }
            if new != .arGlasses, isMainViewVisible, !cameraService.isRunning {
                cameraService.start()
            }
        }
    }

    // MARK: - Private helpers

    private func activateAssistantIfPossible() {
        guard isMainViewVisible else { return }

        ensureCallbacks()

        // Keep the phone camera free when AR glasses mode is active; otherwise
        // start it immediately for on-device preview and capture.
        if activeMode == .arGlasses {
            cameraService.stop()
        } else if !cameraService.isRunning {
            cameraService.start()
        }
        setupCameraCallbacks()

        guard permissionManager.allGranted else { return }
        // Delay OpenAI connection so camera gets system resources first
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, self.isMainViewVisible else { return }
            self.realtimeService.connect()
            // Don't overwrite mode if PTT/processing already started within this window.
            if self.mode != .recording && self.mode != .processing && self.mode != .speaking {
                self.mode = .idle
            }
        }
    }

    private func setupCameraCallbacks() {
        cameraService.autoTorchEnabled = true
        cameraService.onTorchChanged = { [weak self] isOn in
            guard let self else { return }
            let lang = self.onboarding.profile.language.detectedLanguage
            self.speakGPTFeedback(isOn ? JanarymVoice.shared.torchOn(language: lang) : JanarymVoice.shared.torchOff(language: lang))
        }
        cameraService.onVideoRecordingChanged = { [weak self] isRecording in
            guard let self else { return }
            let lang = self.onboarding.profile.language.detectedLanguage
            if isRecording {
                self.liveResponseText = JanarymVoice.shared.videoStarted(language: lang)
                HapticService.shared.single()
                self.scheduleVideoStartAnnouncement()
            } else {
                self.videoStartAnnouncementTask?.cancel()
                self.videoStartAnnouncementTask = nil
            }
        }
        cameraService.onVideoSaved = { [weak self] _ in
            guard let self else { return }
            self.videoStartAnnouncementTask?.cancel()
            self.videoStartAnnouncementTask = nil
            let lang = self.onboarding.profile.language.detectedLanguage
            self.liveResponseText = JanarymVoice.shared.videoSaved(language: lang)
            self.speakGPTFeedback(JanarymVoice.shared.videoSaved(language: lang))
        }
        cameraService.onVideoRecordingFailed = { [weak self] message in
            guard let self else { return }
            self.videoStartAnnouncementTask?.cancel()
            self.videoStartAnnouncementTask = nil
            self.liveResponseText = message
            self.speakGPTFeedback(message)
        }
    }

    // MARK: - Voice command handler

    private func observeVoiceCommands() {
        guard !voiceCommandObserversReady else { return }
        voiceCommandObserversReady = true

        voiceCommands.$lastCommand
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cmd in self?.handleVoiceCommand(cmd) }
            .store(in: &cancellables)

        // Pause voice commands while AI is speaking or recording
        realtimeService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .recording, .processing, .speaking:
                    self.voiceCommands.pause()
                case .idle:
                    // Only resume voice commands when we're truly idle. During startPTT,
                    // state transiently hits .idle (from connect()) while mode is
                    // already .recording — resuming here would restart AVAudioEngine
                    // and kill the SFSpeechRecognizer that's about to start.
                    if self.mode != .recording && self.mode != .processing {
                        self.voiceCommands.resume()
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func handleVoiceCommand(_ cmd: RecognizedVoiceCommand) {
        let lang: DetectedLanguage = onboarding.profile.language.detectedLanguage
        let kk = lang == .kazakh

        switch cmd {
        // Torch
        case .torchOn:
            cameraService.setTorch(on: true)

        case .torchOff:
            cameraService.setTorch(on: false)

        case .torchToggle:
            let isOn = cameraService.currentBrightness < 0.5
            cameraService.setTorch(on: isOn)

        // Time
        case .askTime:
            let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
            speakVoiceFeedback(kk ? "Қазір сағат \(time)" : "Сейчас \(time)", language: lang)

        // SOS
        case .sos:
            triggerSOS()

        // Camera commands — trigger camera describe with specific focus
        case .describeScene:
            triggerCameraDescribe(focusHint: nil)

        case .scanMedicine:
            activeMode = .reading
            triggerCameraDescribe(focusHint: kk
                ? "Дәрі, препарат немесе таблетка туралы ақпаратты оқы: атауы, мөлшері, қолдану тәсілі."
                : "Прочитай информацию о лекарстве: название, дозировку, способ применения.")

        case .readText:
            activeMode = .reading
            triggerCameraDescribe(focusHint: kk
                ? "Алдымдағы мәтінді толық оқы."
                : "Прочитай текст полностью.")

        case .scanBarcode:
            activeMode = .shopping
            triggerCameraDescribe(focusHint: kk
                ? "Штрих-кодты немесе өнімнің атауын тап, бағасын немесе жарамдылық мерзімін айт."
                : "Найди штрихкод или название продукта, назови цену или срок годности.")

        case .startVideoRecording:
            cameraService.startVideoRecording()

        case .stopVideoRecording:
            cameraService.stopVideoRecording()

        // UI commands — forward to view
        case .settings:
            speakVoiceFeedback(JanarymVoice.shared.settingsOpened(language: lang), language: lang)
            uiCommand = cmd

        case .medCard:
            speakVoiceFeedback(JanarymVoice.shared.medCardOpened(language: lang), language: lang)
            uiCommand = cmd

        case .readMedCard:
            readMedCardAloud(language: lang)

        case .back, .whereIsParent:
            uiCommand = cmd

        // Navigation mode toggle
        case .navigation:
            activeMode = .navigation
            let phrase = kk
                ? "Навигация режимі қосылды. Қайда барайын деп тұрсыз?"
                : "Режим навигации включён. Куда хотите пойти?"
            speakVoiceFeedback(phrase, language: lang)

        case .arGlasses:
            activeMode = .arGlasses
            let phrase = kk
                ? "AR көзілдірік режимі қосылды. Дауыспен басқарыңыз."
                : "Режим AR очков включён. Управляйте голосом."
            speakVoiceFeedback(phrase, language: lang)

        case .whereAmI:
            announceCurrentLocation(language: lang)

        case .wakeWord:
            HapticService.shared.single()

        // MARK: Customization — Focus mode (available to everyone)
        case .setFocusAll:
            applyFocusMode(.all, language: lang)
        case .setFocusPeople:
            applyFocusMode(.people, language: lang)
        case .setFocusText:
            applyFocusMode(.text, language: lang)
        case .setFocusObjects:
            applyFocusMode(.objects, language: lang)

        // MARK: Customization — Premium features
        case .setSpeechRateSlow:
            applyCustomization({ $0.speechRate = .slow }, language: lang)
        case .setSpeechRateNormal:
            applyCustomization({ $0.speechRate = .normal }, language: lang)
        case .setSpeechRateFast:
            applyCustomization({ $0.speechRate = .fast }, language: lang)
        case .setResponseShort:
            applyCustomization({ $0.responseLength = .short }, language: lang)
        case .setResponseMedium:
            applyCustomization({ $0.responseLength = .medium }, language: lang)
        case .setResponseLong:
            applyCustomization({ $0.responseLength = .long }, language: lang)
        case .setVoiceMale:
            applyCustomization({ $0.gptVoice = .ember }, language: lang)
        case .setVoiceFemale:
            applyCustomization({ $0.gptVoice = .jupiter }, language: lang)
        case .setFormalityFormal:
            applyCustomization({ $0.formality = .formal }, language: lang)
        case .setFormalityInformal:
            applyCustomization({ $0.formality = .informal }, language: lang)
        }
    }

    /// Read out the user's current address via TTS. Falls back to coordinates if no geocode yet.
    private func announceCurrentLocation(language lang: DetectedLanguage) {
        let kk = lang == .kazakh
        if !locationService.isGranted {
            locationService.start()
            speakVoiceFeedback(kk
                ? "Орналасу рұқсатын сұрап жатырмын."
                : "Запрашиваю разрешение на геолокацию.",
                language: lang)
            return
        }
        locationService.start()

        if !locationService.address.isEmpty {
            let prefix = kk ? "Сіз қазір" : "Вы сейчас"
            speakVoiceFeedback("\(prefix) \(locationService.address).", language: lang)
        } else if let loc = locationService.location {
            let lat = String(format: "%.4f", loc.coordinate.latitude)
            let lon = String(format: "%.4f", loc.coordinate.longitude)
            speakVoiceFeedback(kk
                ? "Координаттарым: \(lat), \(lon)."
                : "Мои координаты: \(lat), \(lon).",
                language: lang)
        } else {
            speakVoiceFeedback(kk
                ? "Орналасуды іздеп жатырмын. Бірнеше секундтан кейін қайта сұраңыз."
                : "Определяю местоположение. Попробуйте через пару секунд.",
                language: lang)
        }
    }

    /// Pause VoiceCommandService (AVAudioEngine) then speak — prevents audio resource conflict.
    /// Always uses **local TTS** (`AVSpeechSynthesizer`) so that Kazakh / Russian text is
    /// pronounced with the correct voice and locale. OpenAI TTS is English-optimised and
    /// should only be used for GPT responses (via `speakGPTFeedback`).
    func speakVoiceFeedback(_ text: String, language: DetectedLanguage) {
        pendingVoiceCommandResumeAfterLocalSpeech = true
        voiceCommands.pause()
        AudioSessionManager.activate(.idle, force: true)
        ttsService.speak(text, language: language)
    }

    func speakGPTFeedback(_ text: String) {
        Task { @MainActor [weak self] in
            await self?.realtimeService.speakText(text, affectsState: false)
        }
    }

    func readMedCardAloud(language: DetectedLanguage? = nil) {
        let lang = language ?? onboarding.profile.language.detectedLanguage
        let kk = lang == .kazakh
        let text = MedCardViewModel.shared.spokenSummary(kk: kk)
            ?? JanarymVoice.shared.medCardReadoutUnavailable(language: lang)
        liveResponseText = text
        speakVoiceFeedback(text, language: lang)
    }

    // MARK: - Voice-driven customization helpers

    /// Public entry point for ChildMainView (and other views) to forward
    /// customization voice commands to the coordinator.
    func handleCustomizationCommand(_ cmd: RecognizedVoiceCommand, language: DetectedLanguage) {
        switch cmd {
        case .setFocusAll:     applyFocusMode(.all, language: language)
        case .setFocusPeople:  applyFocusMode(.people, language: language)
        case .setFocusText:    applyFocusMode(.text, language: language)
        case .setFocusObjects: applyFocusMode(.objects, language: language)
        case .setSpeechRateSlow:      applyCustomization({ $0.speechRate = .slow }, language: language)
        case .setSpeechRateNormal:    applyCustomization({ $0.speechRate = .normal }, language: language)
        case .setSpeechRateFast:      applyCustomization({ $0.speechRate = .fast }, language: language)
        case .setResponseShort:      applyCustomization({ $0.responseLength = .short }, language: language)
        case .setResponseMedium:     applyCustomization({ $0.responseLength = .medium }, language: language)
        case .setResponseLong:       applyCustomization({ $0.responseLength = .long }, language: language)
        case .setVoiceMale:          applyCustomization({ $0.gptVoice = .ember }, language: language)
        case .setVoiceFemale:        applyCustomization({ $0.gptVoice = .jupiter }, language: language)
        case .setFormalityFormal:    applyCustomization({ $0.formality = .formal }, language: language)
        case .setFormalityInformal:  applyCustomization({ $0.formality = .informal }, language: language)
        default: break
        }
    }

    /// Focus mode is available to all subscription tiers.
    private func applyFocusMode(_ mode: UserProfile.FocusMode, language: DetectedLanguage) {
        let profileLang = onboarding.profile.language
        guard onboarding.profile.focusMode != mode else {
            let alreadyText = mode.announcementText(language: profileLang)
            speakVoiceFeedback(alreadyText, language: language)
            return
        }
        var updated = onboarding.profile
        updated.focusMode = mode
        HapticService.shared.single()
        onboarding.updateProfile(updated)
        let announcement = mode.announcementText(language: profileLang)
        speakVoiceFeedback(announcement, language: language)
    }

    /// Premium-gated customization (speech rate, response length, GPT voice, formality).
    /// If the user isn't subscribed, speak a paywall prompt instead of applying the change.
    private func applyCustomization(_ update: (inout UserProfile) -> Void, language: DetectedLanguage) {
        let kk = language == .kazakh
        guard SubscriptionManager.shared.tier.canCustomize else {
            let prompt: String
            switch language {
            case .kazakh:
                prompt = "Бұл мүмкіндік Premium жазылымда қолжетімді. Баптауларды ашу үшін 'баптаулар' деңіз."
            case .russian:
                prompt = "Эта функция доступна в подписке Premium. Скажите 'настройки', чтобы открыть."
            case .english:
                prompt = "This feature is available with a Premium subscription. Say 'settings' to open."
            }
            speakVoiceFeedback(prompt, language: language)
            return
        }

        var updated = onboarding.profile
        let previous = updated
        update(&updated)
        guard updated != previous else { return }
        HapticService.shared.single()
        onboarding.updateProfile(updated)

        // Generate confirmation announcement
        let announcement = customizationAnnouncement(old: previous, new: updated, kk: kk)
        speakVoiceFeedback(announcement, language: language)
    }

    private func customizationAnnouncement(old: UserProfile, new: UserProfile, kk: Bool) -> String {
        if old.speechRate != new.speechRate {
            return kk
                ? "\(new.speechRate.display(.kazakh)) жылдамдық таңдалды"
                : "Скорость: \(new.speechRate.display(.russian))"
        }
        if old.responseLength != new.responseLength {
            return kk
                ? "\(new.responseLength.display(.kazakh)) жауап режимі таңдалды"
                : "Длина ответа: \(new.responseLength.display(.russian))"
        }
        if old.gptVoice != new.gptVoice {
            return new.gptVoice.announcement(new.language)
        }
        if old.formality != new.formality {
            return kk
                ? "'\(new.formality.display(.kazakh))' деп жүгіну таңдалды"
                : "Обращение на '\(new.formality.display(.russian))' выбрано"
        }
        return kk ? "Өзгеріс сақталды" : "Изменение сохранено"
    }

    private func scheduleVideoStartAnnouncement() {
        videoStartAnnouncementTask?.cancel()
        let lang: DetectedLanguage = onboarding.profile.language.detectedLanguage
        let phrase = JanarymVoice.shared.videoStartedAnnouncement(language: lang)

        videoStartAnnouncementTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, !Task.isCancelled, self.cameraService.isVideoRecording else { return }
            self.speakVoiceFeedback(phrase, language: lang)
        }
    }

    private func currentVisionFrame(maxEdge: CGFloat) -> Data? {
        if activeMode == .arGlasses {
            return esp32Camera.latestSnapshot
        }
        return cameraService.captureCurrentFrameJPEG(maxEdge: maxEdge)
    }

    private func finishPTTResponse(with frameJPEG: Data?) {
        let responseFrame = frameJPEG ?? capturedFrameAtPTTStart
        if activeMode == .arGlasses, responseFrame == nil {
            let lang: DetectedLanguage = onboarding.profile.language.detectedLanguage
            capturedFrameAtPTTStart = nil
            mode = .idle
            voiceCommands.resume()
            speakVoiceFeedback(
                lang == .kazakh
                    ? "AR көзілдірік қосылмаған. WiFi мен IP-ді тексеріңіз."
                    : "AR очки не подключены. Проверьте WiFi и IP.",
                language: lang
            )
            return
        }

        if let responseFrame {
            UserPresenceService.shared.uploadPhotoAndPresence(jpegData: responseFrame)
        }
        realtimeService.stopPTTAndRespond(frameJPEG: responseFrame)
        capturedFrameAtPTTStart = nil

        pttProcessingTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled, self.mode == .processing else { return }
            self.mode = .idle
        }
    }

    /// Public entry point — ChildMainView uses this for voice commands too.
    func triggerCameraDescribe(focusHint: String?) {
        guard isMainViewVisible else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let prompt = focusHint
            let frame: Data?
            if self.activeMode == .arGlasses {
                if let cachedSnapshot = self.esp32Camera.latestSnapshot {
                    frame = cachedSnapshot
                } else {
                    frame = await esp32Camera.fetchSnapshot()
                }
                if frame == nil {
                    let lang: DetectedLanguage = onboarding.profile.language.detectedLanguage
                    speakVoiceFeedback(
                        lang == .kazakh
                            ? "AR көзілдірік қосылмаған. WiFi мен IP-ді тексеріңіз."
                            : "AR очки не подключены. Проверьте WiFi и IP.",
                        language: lang
                    )
                    return
                }
            } else {
                frame = cameraService.captureCurrentFrameJPEG(maxEdge: 512)
            }

            await self.realtimeService.describeCamera(frameJPEG: frame, promptOverride: prompt)
        }
    }

    private func observeNetworkStatus() {
        NetworkMonitor.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                self?.isOfflineMode = !connected
            }
            .store(in: &cancellables)
    }

    private func observeLanguageChanges() {
        onboarding.$profile
            .map(\.language)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.ttsService.stop()
                self.liveTranscript = ""
                self.liveResponseText = ""
                self.errorMessage = nil
                self.mode = .idle
                self.realtimeService.handleLanguageChange()
                if self.isMainViewVisible, self.permissionManager.allGranted {
                    self.voiceCommands.stop()
                    self.voiceCommands.start()
                }
            }
            .store(in: &cancellables)
    }

    private func ensureCallbacks() {
        guard !callbacksReady else { return }
        callbacksReady = true

        // Inject shared TTS so realtimeService and coordinator hit the same synth
        // (dual instances caused delegate races that silenced AI speech).
        realtimeService.speechService = ttsService

        // Provide location context to the AI when navigation mode is active
        realtimeService.extraContextProvider = { [weak self] in
            guard let self else { return "" }
            guard self.activeMode == .navigation else { return "" }
            return self.locationService.locationContext
        }

        realtimeService.onResponseText = { [weak self] text in
            guard let self else { return }
            self.liveResponseText = text
        }

        realtimeService.onTranscription = { [weak self] text in
            self?.liveTranscript = text
        }

        realtimeService.onFailure = { [weak self] message in
            guard let self else { return }
            self.errorMessage = message
            self.liveResponseText = message
            self.mode = .error
        }

        // Pause VoiceCommandService (AVAudioEngine) right before TTS speaks
        realtimeService.onWillSpeak = { [weak self] in
            self?.voiceCommands.pause()
        }

        realtimeService.onDidFinishSpeaking = { [weak self] affectedState in
            guard let self else { return }
            guard !affectedState else { return }
            if self.mode != .recording && self.mode != .processing {
                self.voiceCommands.resume()
            }
        }

        ttsService.onFinished = { [weak self] in
            guard let self else { return }
            let shouldResumeVoiceCommands = self.pendingVoiceCommandResumeAfterLocalSpeech
            self.pendingVoiceCommandResumeAfterLocalSpeech = false
            if shouldResumeVoiceCommands,
               self.mode != .recording,
               self.mode != .processing {
                self.voiceCommands.resume()
            }
            // Don't reset state if PTT just took over (stop() fires onFinished async on
            // main queue, landing here AFTER startPTT set mode=.recording — without this
            // guard voiceCommands.resume() restarts AVAudioEngine and kills SFSpeech).
            if self.mode == .recording || self.mode == .processing { return }
            self.realtimeService.markSpeechFinished()
        }

        realtimeService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] realtimeState in
                guard let self else { return }
                switch realtimeState {
                case .idle:
                    // Don't auto-reset .recording — it's driven explicitly by startPTT/
                    // stopPTT. Transient state=.idle during startPTT (from connect()
                    // firing before beginSTTRecording publishes .recording) would
                    // otherwise flip us back to idle before STT actually starts.
                    if self.mode == .processing || self.mode == .speaking {
                        self.mode = .idle
                    }
                case .recording:
                    self.mode = .recording
                case .processing:
                    self.mode = .processing
                case .speaking:
                    self.mode = .speaking
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
}
