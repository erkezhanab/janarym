import AVFoundation
import SwiftUI

// MARK: - HoldZone (UIKit touch begin/end)

private struct HoldZone: UIViewRepresentable {
    let onBegan: () -> Void
    let onEnded: () -> Void

    func makeUIView(context: Context) -> _HoldView {
        let v = _HoldView()
        v.onBegan = onBegan
        v.onEnded = onEnded
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ v: _HoldView, context: Context) {
        v.onBegan = onBegan
        v.onEnded = onEnded
    }

    final class _HoldView: UIView {
        var onBegan: (() -> Void)?
        var onEnded:  (() -> Void)?
        override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?)    { onBegan?() }
        override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent?)    { onEnded?() }
        override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent?) { onEnded?() }
    }
}

// MARK: - SOS Corner Overlay (4-corner simultaneous touch)

private struct SOSCornerOverlay: UIViewRepresentable {
    let onSOS: () -> Void
    func makeUIView(context: Context) -> _SOSView {
        let v = _SOSView()
        v.onSOS = onSOS
        v.backgroundColor = .clear
        v.isMultipleTouchEnabled = true
        return v
    }
    func updateUIView(_ v: _SOSView, context: Context) { v.onSOS = onSOS }

    final class _SOSView: UIView {
        var onSOS: (() -> Void)?
        private var activeCorners: [UITouch: CornerID] = [:]
        private var sosWork: DispatchWorkItem?

        enum CornerID: Hashable { case tl, tr, bl, br }

        private func corner(for touch: UITouch) -> CornerID? {
            let p = touch.location(in: self)
            let z = min(bounds.width, bounds.height) * 0.22
            if p.x < z && p.y < z                          { return .tl }
            if p.x > bounds.width - z && p.y < z           { return .tr }
            if p.x < z && p.y > bounds.height - z          { return .bl }
            if p.x > bounds.width - z && p.y > bounds.height - z { return .br }
            return nil
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches { if let c = corner(for: t) { activeCorners[t] = c } }
            check()
        }
        override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent?) {
            t.forEach { activeCorners.removeValue(forKey: $0) }
            sosWork?.cancel()
        }
        override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent?) {
            touchesEnded(t, with: e)
        }

        private func check() {
            let active = Set(activeCorners.values)
            guard active == [.tl, .tr, .bl, .br] else { return }
            sosWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.onSOS?() }
            sosWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }
}

// MARK: - Camera description model (@MainActor ObservableObject)

@MainActor
private final class CameraModel: ObservableObject {
    @Published var isDescribing = false

    private var task: Task<Void, Never>?
    private weak var realtimeService: OpenAIRealtimeService?
    private weak var cameraService: CameraService?

    func configure(realtime: OpenAIRealtimeService, camera: CameraService) {
        self.realtimeService = realtime
        self.cameraService   = camera
    }

    func start() {
        guard !isDescribing,
              let rs = realtimeService,
              let cs = cameraService else { return }
        isDescribing = true
        task = Task { @MainActor in
            while self.isDescribing && !Task.isCancelled {
                let frame = cs.captureCurrentFrameJPEG(maxEdge: 512)
                await rs.describeCamera(frameJPEG: frame)
                if self.isDescribing {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
            }
        }
    }

    func stop() {
        isDescribing = false
        task?.cancel(); task = nil
        realtimeService?.stopDescribing()
    }
}

// MARK: - ChildMainView

struct ChildMainView: View {

    @ObservedObject var coordinator: AssistantCoordinator
    @ObservedObject private var realtimeService: OpenAIRealtimeService
    @ObservedObject private var cameraService: CameraService
    @ObservedObject private var esp32Camera: ESP32CameraService
    @ObservedObject private var onboarding = OnboardingStore.shared

    @StateObject private var voiceCommands  = VoiceCommandService()
    @StateObject private var cameraModel    = CameraModel()

    @State private var showSettings = false
    @State private var showMedCard  = false

    private var kk: Bool { onboarding.profile.language == .kazakh }

    init(coordinator: AssistantCoordinator) {
        self.coordinator  = coordinator
        _realtimeService  = ObservedObject(wrappedValue: coordinator.realtimeService)
        _cameraService    = ObservedObject(wrappedValue: coordinator.cameraService)
        _esp32Camera      = ObservedObject(wrappedValue: coordinator.esp32Camera)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // ── Full-screen camera ──
                Group {
                    if isARMode {
                        SnapshotPreviewView(
                            imageData: esp32Camera.latestSnapshot,
                            isConnected: esp32Camera.isConnected,
                            title: kk ? "AR көзілдірікке қосылуда" : "Подключение к AR-очкам",
                            subtitle: kk
                                ? "Wi‑Fi бірдей желіде болсын. Қажет болса IP-ді баптаулардан өзгертіңіз."
                                : "Убедитесь, что устройства в одной Wi‑Fi сети. При необходимости измените IP в настройках."
                        )
                    } else {
                        CameraPreviewView(session: cameraService.session, isActive: true)
                    }
                }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // Gradient scrim for readability
                LinearGradient(
                    colors: [Color.black.opacity(0.12), Color.black.opacity(0.50)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // ── Touch zones ──
                VStack(spacing: 0) {
                    // TOP 60% — Camera zone
                    cameraZone
                        .frame(height: geo.size.height * 0.60)

                    // MIDDLE 25% — Med card zone
                    medCardZone
                        .frame(height: geo.size.height * 0.25)

                    // BOTTOM 15% — Settings zone
                    settingsZone
                        .frame(height: geo.size.height * 0.15)
                }
                .ignoresSafeArea()

                // ── SOS: invisible corner overlay above everything ──
                SOSCornerOverlay(onSOS: coordinator.triggerSOS)
                    .ignoresSafeArea()

                // ── Status label (non-interactive) ──
                statusLabel
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
        // Pause voice commands during recording
        .onReceive(realtimeService.$state) { state in
            switch state {
            case .recording, .processing, .speaking: voiceCommands.pause()
            case .idle: voiceCommands.resume()
            default: break
            }
        }
        // Handle voice commands
        .onReceive(voiceCommands.$lastCommand.compactMap { $0 }) { cmd in
            handleVoice(cmd)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showMedCard)  { MedCardScreen() }
    }

    // MARK: - Camera zone (top 60%)

    private var isARMode: Bool { coordinator.activeMode == .arGlasses }

    private var cameraZone: some View {
        ZStack {
            if !isARMode {
                HoldZone(
                    onBegan: { cameraModel.start(); voiceCommands.pause() },
                    onEnded:  { cameraModel.stop();  voiceCommands.resume() }
                )
            }

            // Hint label
            VStack {
                Spacer()
                Group {
                    if isARMode {
                        HStack(spacing: 8) {
                            Image(systemName: "eyeglasses")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.cyan)
                            Text(kk ? "AR режимі — дауыспен басқарыңыз" : "Режим AR — управляй голосом")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.cyan)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Color.black.opacity(0.70))
                        .clipShape(Capsule())
                    } else if cameraModel.isDescribing {
                        HStack(spacing: 8) {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text(kk ? "AI сипаттап жатыр..." : "AI описывает...")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Color.black.opacity(0.70))
                        .clipShape(Capsule())
                    } else {
                        Text(kk ? "Ұстап тұр → AI сипаттайды" : "Держи → AI описывает")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.50))
                    }
                }
                .padding(.bottom, 18)
            }
            .allowsHitTesting(false)
        }
        .accessibilityLabel(kk
            ? "Камера аймағы. Ұстап тұрыңыз — AI камерадан не көрінетінін сипаттайды"
            : "Зона камеры. Удерживайте — AI описывает изображение с камеры")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Med card zone (middle 25%)

    private var medCardZone: some View {
        ZStack {
            Color.white.opacity(0.04)
                .overlay(Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1), alignment: .top)

            VStack(spacing: 6) {
                Image(systemName: "cross.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.red.opacity(0.90))
                Text(kk ? "Медкарта" : "Медкарта")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Text(kk ? "2 сек ұстап тұр" : "Удержи 2 сек")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 2.0, perform: openMedCard)
        .accessibilityLabel(kk ? "Медициналық карта" : "Медкарта")
        .accessibilityHint(kk ? "2 секунд ұстап тұрыңыз" : "Удерживайте 2 секунды")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Settings zone (bottom 15%)

    private var settingsZone: some View {
        ZStack {
            Color.white.opacity(0.04)
                .overlay(Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1), alignment: .top)

            VStack(spacing: 4) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Text(kk ? "Баптаулар — 3 сек" : "Настройки — 3 сек")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.30))
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 3.0, perform: openSettings)
        .accessibilityLabel(kk ? "Баптаулар" : "Настройки")
        .accessibilityHint(kk ? "3 секунд ұстап тұрыңыз" : "Удерживайте 3 секунды")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Status label (top bar)

    private var statusLabel: some View {
        HStack {
            let state = realtimeService.state
            if state == .processing {
                HStack(spacing: 6) {
                    ProgressView().tint(.white).scaleEffect(0.8)
                    Text(kk ? "Өңделуде" : "Обрабатываю")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.black.opacity(0.65))
                .clipShape(Capsule())
                .padding(.top, 56)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Lifecycle

    private func onAppear() {
        cameraModel.configure(realtime: coordinator.realtimeService,
                              camera: coordinator.cameraService)
        coordinator.cameraService.start()
        coordinator.realtimeService.connect()

        // Auto-torch callback — speak personality phrase when torch switches
        coordinator.cameraService.onTorchChanged = { [weak coordinator] isOn in
            let lang = onboarding.profile.language.detectedLanguage
            let phrase = isOn ? JanarymVoice.shared.torchOn(language: lang) : JanarymVoice.shared.torchOff(language: lang)
            coordinator?.speakGPTFeedback(phrase)
        }
        coordinator.cameraService.autoTorchEnabled = false  // child uses manual torch via voice

        // Delay voice commands 2 s so AVCaptureSession.startRunning() (camera hardware
        // init) finishes before AVAudioEngine grabs the same audio hardware resources.
        let voiceCommands = self.voiceCommands
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            voiceCommands.start()
        }

        // Welcome greeting after camera + voice are ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            let lang = onboarding.profile.language.detectedLanguage
            coordinator.speakVoiceFeedback(
                JanarymVoice.shared.screenWelcome(language: lang),
                language: lang
            )
        }
    }

    private func onDisappear() {
        coordinator.cameraService.onTorchChanged = nil
        voiceCommands.stop()
        cameraModel.stop()
    }

    // MARK: - Actions

    private func openMedCard() {
        HapticService.shared.single()
        let lang = onboarding.profile.language.detectedLanguage
        coordinator.speakVoiceFeedback(
            JanarymVoice.shared.medCardOpened(language: lang),
            language: lang
        )
        showMedCard = true
    }

    private func openSettings() {
        HapticService.shared.single()
        let lang = onboarding.profile.language.detectedLanguage
        coordinator.speakVoiceFeedback(
            JanarymVoice.shared.settingsOpened(language: lang),
            language: lang
        )
        showSettings = true
    }

    private func handleVoice(_ cmd: RecognizedVoiceCommand) {
        let lang: DetectedLanguage = onboarding.profile.language.detectedLanguage
        switch cmd {
        case .wakeWord:
            HapticService.shared.single()
            coordinator.speakVoiceFeedback(JanarymVoice.shared.listening(language: lang), language: lang)

        case .settings:
            openSettings()

        case .medCard:
            openMedCard()

        case .readMedCard:
            HapticService.shared.single()
            coordinator.readMedCardAloud(language: lang)

        case .describeScene, .scanMedicine, .readText, .scanBarcode:
            HapticService.shared.single()
            if coordinator.activeMode == .arGlasses {
                let hint: String? = cmd == .describeScene ? nil
                    : cmd == .scanMedicine ? (kk ? "Дәрі туралы ақпаратты оқы: атауы, мөлшері." : "Прочитай информацию о лекарстве.")
                    : cmd == .readText    ? (kk ? "Алдымдағы мәтінді толық оқы." : "Прочитай текст полностью.")
                    : (kk ? "Өнімді тап, бағасын айт." : "Найди товар, назови цену.")
                coordinator.triggerCameraDescribe(focusHint: hint)
            } else {
                cameraModel.start()
            }

        case .startVideoRecording:
            HapticService.shared.single()
            coordinator.cameraService.startVideoRecording()

        case .stopVideoRecording:
            HapticService.shared.single()
            coordinator.cameraService.stopVideoRecording()

        case .back:
            HapticService.shared.single()
            cameraModel.stop()

        case .whereIsParent:
            HapticService.shared.double()
            coordinator.speakVoiceFeedback(kk ? "Ата-ана орнын іздеп жатырмын..." : "Ищу местоположение родителя...", language: lang)

        case .navigation:
            HapticService.shared.single()
            coordinator.activeMode = .navigation
            coordinator.speakVoiceFeedback(
                kk ? "Навигация режимі қосылды. Қайда барайын деп тұрсыз?" : "Режим навигации включён. Куда хотите пойти?",
                language: lang
            )

        case .arGlasses:
            HapticService.shared.single()
            coordinator.activeMode = .arGlasses
            coordinator.speakVoiceFeedback(
                kk ? "AR көзілдірік режимі қосылды. Дауыспен басқарыңыз." : "Режим AR очков включён. Управляйте голосом.",
                language: lang
            )

        case .whereAmI:
            HapticService.shared.single()
            coordinator.speakVoiceFeedback(kk ? "Орналасуыңызды іздеп жатырмын..." : "Ищу ваше местоположение...", language: lang)

        case .sos:
            coordinator.triggerSOS()

        case .torchOn:
            HapticService.shared.single()
            coordinator.cameraService.setTorch(on: true)

        case .torchOff:
            HapticService.shared.single()
            coordinator.cameraService.setTorch(on: false)

        case .torchToggle:
            HapticService.shared.single()
            let currentlyOn = coordinator.cameraService.currentBrightness < 0.5
            coordinator.cameraService.setTorch(on: !currentlyOn)

        case .askTime:
            HapticService.shared.double()
            let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
            coordinator.speakVoiceFeedback(kk ? "Қазір сағат \(time)" : "Сейчас \(time)", language: lang)

        // Customization — forward to coordinator helpers
        case .setFocusAll, .setFocusPeople, .setFocusText, .setFocusObjects,
             .setSpeechRateSlow, .setSpeechRateNormal, .setSpeechRateFast,
             .setResponseShort, .setResponseMedium, .setResponseLong,
             .setVoiceMale, .setVoiceFemale,
             .setFormalityFormal, .setFormalityInformal:
            coordinator.handleCustomizationCommand(cmd, language: lang)
        }
    }
}
