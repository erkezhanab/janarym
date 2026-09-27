import AVFoundation
import SwiftUI

// MARK: - Speech preview helper

@MainActor
private final class SpeechPreview: NSObject, ObservableObject {
    private var player: AVAudioPlayer?
    private var speakTask: Task<Void, Never>?
    private let localSpeech = SpeechSynthesizerService()

    private static func log(_ message: String) {
        print("SettingsPreview:", message)
    }

    func speak(_ text: String, profile: UserProfile) {
        speakTask?.cancel()
        speakTask = Task { [weak self] in
            await self?.playPreview(text, profile: profile)
        }
    }

    private func playPreview(_ text: String, profile: UserProfile) async {
        stopPlayback()

        let remoteAudio: String
        do {
            remoteAudio = try await fetchRemotePreviewAudio(text: text, profile: profile)
        } catch {
            Self.log("preview fetch failed — falling back to local: \(error.localizedDescription)")
            AudioSessionManager.activate(.playback)
            localSpeech.speak(text, language: profile.language.detectedLanguage)
            return
        }
        do {
            try playAudio(base64: remoteAudio)
            Self.log("preview playback started")
        } catch {
            Self.log("preview playback failed: \(error.localizedDescription)")
        }
    }

    private func fetchRemotePreviewAudio(text: String, profile: UserProfile) async throws -> String {
        if !AppConfig.openAIProxyURL.isEmpty {
            do {
                let audio = try await fetchPreviewViaProxy(text: text, profile: profile)
                Self.log("preview fetched via proxy")
                return audio
            } catch {
                Self.log("proxy preview failed, falling back to direct TTS: \(error.localizedDescription)")
            }
        }
        throw AppError.missingAPIKey
    }

    private func fetchPreviewViaProxy(text: String, profile: UserProfile) async throws -> String {
        guard let url = URL(string: AppConfig.openAIProxyURL) else {
            throw AppError.networkError("Invalid OpenAI proxy URL")
        }
        let payload: [String: Any] = [
            "text": text,
            "voice": profile.gptVoice.openAIVoiceID,
            "tts_model": AppConfig.openAITTSModel,
            "speed": profile.speechRate.avRate,
            "include_audio": true,
            "task": "tts"
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        try await ProxyAuth.authorize(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AppError.networkError(extractErrorMessage(from: data) ?? "Preview TTS failed")
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let audioBase64 = json["audio_base64"] as? String,
            !audioBase64.isEmpty
        else {
            throw AppError.ttsFailed("Preview audio is missing")
        }
        return audioBase64
    }

    private func playAudio(base64: String) throws {
        guard let audioData = Data(base64Encoded: base64) else {
            throw AppError.ttsFailed("Unable to decode preview audio")
        }
        try configurePlaybackSession()
        let player = try AVAudioPlayer(data: audioData)
        player.delegate = self
        player.prepareToPlay()
        self.player = player
        guard player.play() else {
            throw AppError.ttsFailed("Unable to start preview playback")
        }
    }

    func stop() {
        speakTask?.cancel()
        stopPlayback()
    }

    private func stopPlayback() {
        speakTask = nil
        localSpeech.stop()
        player?.stop()
        player = nil
    }

    private func configurePlaybackSession() throws {
        AudioSessionManager.activate(.playback)
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }
        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }
        return nil
    }
}

extension SpeechPreview: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.player = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.player = nil
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {

    @ObservedObject private var store = OnboardingStore.shared
    @ObservedObject private var sub = SubscriptionManager.shared
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preview = SpeechPreview()
    @State private var showParentLinkSheet = false
    @State private var showPaywall = false
    @State private var arGlassesHostDraft = ESP32CameraService.storedHost()

    private var kk: Bool { store.profile.language == .kazakh }
    private var canCustomize: Bool { sub.tier.canCustomize }
    private var canUseParentLink: Bool {
        guard let user = authService.currentUser else { return false }
        return user.role == .child || user.parentUid != nil || user.isLinked
    }

    private func applyProfileChange(
        _ update: (inout UserProfile) -> Void,
        shouldPreviewSpeech: Bool = false,
        previewText: String? = nil
    ) {
        var updated = store.profile
        let previous = updated
        update(&updated)
        if updated != previous {
            HapticService.shared.single()
            store.updateProfile(updated)
        } else if shouldPreviewSpeech {
            HapticService.shared.single()
        } else {
            return
        }

        guard shouldPreviewSpeech, let previewText else { return }
        preview.speak(previewText, profile: updated)
    }

    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    if canUseParentLink {
                        parentLinkSection
                    }
                    arGlassesSection
                    focusModeSection
                    gptVoiceSection
                    if canCustomize {
                        speechRateSection
                        responseLengthSection
                        formalitySection
                    } else {
                        premiumCustomizationBanner
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea())
            .navigationTitle(kk ? "Баптаулар" : "Настройки")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(kk ? "Жабу" : "Закрыть") { dismiss() }
                        .foregroundStyle(.white)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .colorScheme(.dark)
        }
        .sheet(isPresented: $showParentLinkSheet) {
            if let childUID = authService.currentUser?.id {
                ChildParentLinkSheet(childUID: childUID, kk: kk)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Premium customization banner

    private var premiumCustomizationBanner: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "star.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.green)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(kk ? "Дауыс кастомизациясы" : "Настройка голоса")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text(kk
                         ? "Дауыс, жылдамдық, стиль — Premium немесе VIP-та"
                         : "Голос, скорость, стиль — доступны в Premium и VIP")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                Text(kk ? "Ашу" : "Открыть")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.green.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Parent link

    private var parentLinkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(kk ? "Ата-ана бақылауы" : "Родительский контроль")
            Button {
                HapticService.shared.single()
                showParentLinkSheet = true
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "figure.and.child.holdinghands")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.green)
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(kk ? "Ата-анаға қосылу" : "Подключиться к родителю")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                        Text(kk ? "Жақын маңнан ата-ананы тауып, сұрау жіберу" : "Найти родителя рядом и отправить запрос")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, minHeight: 80)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - AR glasses

    private var arGlassesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(kk ? "AR көзілдірік" : "AR очки")

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.cyan)
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(kk ? "ESP32 камера адресі" : "Адрес ESP32 камеры")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                        Text(kk
                             ? "IP немесе толық URL жазыңыз. Қосымша автоматты түрде `/snapshot` endpoint-ын қолданады."
                             : "Укажите IP или полный URL. Приложение автоматически использует endpoint `/snapshot`.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                TextField(
                    kk ? "Мысалы, 192.168.43.230" : "Например, 192.168.43.230",
                    text: $arGlassesHostDraft
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.28))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
                .foregroundStyle(.white)
                .onSubmit(commitARGlassesHost)

                HStack(spacing: 10) {
                    Button(kk ? "Сақтау" : "Сохранить", action: commitARGlassesHost)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.cyan)
                        .clipShape(Capsule())

                    Button(kk ? "Әдепкі IP" : "IP по умолчанию") {
                        arGlassesHostDraft = ESP32CameraService.defaultHost
                        commitARGlassesHost()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }

                Text(kk
                     ? "Қазір сақталған адрес: \(ESP32CameraService.storedHost()). Камера мен iPhone бір Wi‑Fi желісінде болуы керек."
                     : "Сейчас сохранён адрес: \(ESP32CameraService.storedHost()). Камера и iPhone должны быть в одной Wi‑Fi сети.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    private func commitARGlassesHost() {
        arGlassesHostDraft = ESP32CameraService.saveHost(arGlassesHostDraft)
        HapticService.shared.single()
    }

    // MARK: - Focus mode

    private var focusModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(kk ? "Камера фокусы" : "Фокус камеры")
            ForEach(UserProfile.FocusMode.allCases, id: \.self) { mode in
                focusModeCard(mode)
            }
        }
    }

    private func focusModeCard(_ mode: UserProfile.FocusMode) -> some View {
        let isSelected = store.profile.focusMode == mode
        return Button {
            applyProfileChange(
                { $0.focusMode = mode },
                shouldPreviewSpeech: true,
                previewText: mode.announcementText(kk: kk)
            )
        } label: {
            HStack(spacing: 16) {
                Image(systemName: mode.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isSelected ? .black : Color.green)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName(kk: kk))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(isSelected ? .black : .white)
                    Text(mode.descriptionText(kk: kk))
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? .black.opacity(0.65) : .white.opacity(0.5))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.black)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.green : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.displayName(kk: kk))
        .accessibilityHint(mode.descriptionText(kk: kk))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Speech rate

    private var speechRateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(kk ? "Сөйлеу жылдамдығы" : "Скорость речи")
            HStack(spacing: 10) {
                ForEach(UserProfile.SpeechRate.allCases, id: \.self) { rate in
                    speechRateButton(rate)
                }
            }
        }
    }

    private func speechRateButton(_ rate: UserProfile.SpeechRate) -> some View {
        let isSelected = store.profile.speechRate == rate
        return Button {
            let sample = kk
                ? "Бұл Жанарым қолданбасы."
                : "Это приложение Жанарым."
            applyProfileChange(
                { $0.speechRate = rate },
                shouldPreviewSpeech: true,
                previewText: sample
            )
        } label: {
            VStack(spacing: 8) {
                Image(systemName: rate.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? .black : Color.green)
                Text(rate.display(store.profile.language))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isSelected ? .black : .white)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.green : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rate.display(store.profile.language))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Response length

    private var responseLengthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(kk ? "Жауап ұзындығы" : "Длина ответа")
            HStack(spacing: 10) {
                ForEach(UserProfile.ResponseLength.allCases, id: \.self) { len in
                    responseLengthButton(len)
                }
            }
        }
    }

    private func responseLengthButton(_ len: UserProfile.ResponseLength) -> some View {
        let isSelected = store.profile.responseLength == len
        return Button {
            let text = kk ? "\(len.display(.kazakh)) таңдалды" : "\(len.display(.russian)) выбрано"
            applyProfileChange(
                { $0.responseLength = len },
                shouldPreviewSpeech: true,
                previewText: text
            )
        } label: {
            VStack(spacing: 8) {
                Image(systemName: len.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? .black : Color.green)
                Text(len.display(store.profile.language))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isSelected ? .black : .white)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.green : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(len.display(store.profile.language))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Formality

    private var formalitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(kk ? "Жүгіну" : "Обращение")
            HStack(spacing: 10) {
                ForEach(UserProfile.Formality.allCases, id: \.self) { formality in
                    formalityButton(formality)
                }
            }
        }
    }

    private func formalityButton(_ formality: UserProfile.Formality) -> some View {
        let isSelected = store.profile.formality == formality
        return Button {
            let text = kk
                ? "'\(formality.display(.kazakh))' деп жүгіну таңдалды"
                : "Обращение на '\(formality.display(.russian))' выбрано"
            applyProfileChange(
                { $0.formality = formality },
                shouldPreviewSpeech: true,
                previewText: text
            )
        } label: {
            VStack(spacing: 6) {
                Text(formality.display(store.profile.language))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isSelected ? .black : .white)
                Text(formality.formalityLabel(kk: kk))
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .black.opacity(0.65) : .white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.green : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(formality.display(store.profile.language)) — \(formality.formalityLabel(kk: kk))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - GPT voice

    private var gptVoiceSectionTitle: String {
        kk ? "GPT дауысы" : "Голос GPT"
    }

    private var gptVoiceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(gptVoiceSectionTitle)
            ForEach(UserProfile.GPTVoice.allCases, id: \.self) { voice in
                gptVoiceRow(voice)
            }
        }
    }

    private func gptVoiceRow(_ voice: UserProfile.GPTVoice) -> some View {
        let isSelected = store.profile.gptVoice == voice
        return Button {
            applyProfileChange(
                {
                    $0.gptVoice = voice
                    $0.selectedVoiceIdentifier = nil
                },
                shouldPreviewSpeech: true,
                previewText: voice.announcement(store.profile.language)
            )
        } label: {
            HStack(spacing: 14) {
                Image(systemName: voice == .ember ? "person.fill.checkmark" : "person.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .black : Color.green)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(voice.title(store.profile.language))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? .black : .white)
                    Text(voice.subtitle(store.profile.language))
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? .black.opacity(0.6) : .white.opacity(0.45))
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.black)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? Color.green : Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(voice.title(store.profile.language)) \(voice.subtitle(store.profile.language))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
            .textCase(.uppercase)
            .tracking(0.9)
            .padding(.leading, 4)
    }
}
