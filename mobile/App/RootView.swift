import AVFoundation
import Combine
import SwiftUI

// MARK: - AppMode (UI only, separate from AssistantMode)
enum AppMode: String, CaseIterable, Identifiable {
    case general    = "Жалпы"
    case navigation = "Навигация"
    case security   = "Қауіпсіздік"
    case shopping   = "Сауда"
    case reading    = "Мәтін оқу"
    case arGlasses  = "AR Көзілдірік"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:    return "mic.fill"
        case .navigation: return "map.fill"
        case .security:   return "shield.fill"
        case .shopping:   return "cart.fill"
        case .reading:    return "doc.text.fill"
        case .arGlasses:  return "eyeglasses"
        }
    }

    /// Барлық режимдер барлық тарифта қол жетімді
    @MainActor
    var isAvailable: Bool { true }

    /// Tier тексеру кілті
    var modeKey: String {
        switch self {
        case .general:    return "general"
        case .navigation: return "navigation"
        case .security:   return "antiscam"
        case .shopping:   return "shopping"
        case .reading:    return "reading"
        case .arGlasses:  return "arglasses"
        }
    }

    var localizedName: String {
        let kk = OnboardingStore.shared.profile.language == .kazakh
        switch self {
        case .general:    return kk ? "Жалпы"         : "Общий"
        case .navigation: return "Навигация"
        case .security:   return kk ? "Қауіпсіздік"   : "Безопасность"
        case .shopping:   return kk ? "Сауда"          : "Покупки"
        case .reading:    return kk ? "Мәтін оқу"     : "Чтение"
        case .arGlasses:  return kk ? "AR Көзілдірік" : "AR Очки"
        }
    }

    var pillWidth: CGFloat {
        switch self {
        case .general:    return 172
        case .navigation: return 165
        case .security:   return 190
        case .shopping:   return 155
        case .reading:    return 170
        case .arGlasses:  return 190
        }
    }
}

// MARK: - Root

struct RootView: View {

    @StateObject private var coordinator = AssistantCoordinator()
    @ObservedObject private var onboarding = OnboardingStore.shared
    @EnvironmentObject private var authService: AuthService
    private let arFrameStaleThreshold: TimeInterval = 2.5
    @Environment(\.scenePhase) private var scenePhase
    @State private var permissionsReady = false

    private func print(_ items: Any...) {}
    private var currentRole: UserRole? { authService.currentUser?.role }
    private var isMemberFlow: Bool { currentRole?.isStandardUser ?? true }

    var body: some View {
        ZStack {
            // Барлық экрандардың артындағы қара фон
            Color(red: 0.04, green: 0.04, blue: 0.08)
                .ignoresSafeArea(.all)

            if authService.isRestoringSession {
                AppStartupView()
                    .ignoresSafeArea(.all)
                    .transition(.opacity)
            } else if !authService.isAuthenticated {
                // 1. Аутентификация
                LoginView()
                    .ignoresSafeArea(.all)
                    .transition(.opacity)
            } else if !authService.isApproved {
                // 1.5. Өтініш әлі мақұлданбаса
                PendingApprovalView(status: authService.applicationStatus,
                                    rejectionReason: authService.rejectionReason)
                    .environmentObject(authService)
                    .ignoresSafeArea(.all)
                    .transition(.opacity)
            } else if currentRole == .parent, let user = authService.currentUser {
                MentorDashboardView(user: user)
                    .environmentObject(authService)
                    .ignoresSafeArea(.all)
                    .transition(.opacity)
            } else if !onboarding.isCompleted, isMemberFlow {
                // 3. Onboarding — тек member/child үшін (admin/mentor өткізіп кетеді)
                OnboardingView(store: OnboardingStore.shared)
                    .ignoresSafeArea(.all)
                    .transition(.opacity)
            } else if !permissionsReady, isMemberFlow {
                // 4. Permissions — тек member/child үшін (admin/mentor өткізіп кетеді)
                PermissionsView(
                    manager: coordinator.permissionManager,
                    onContinue: goToMainScreen
                )
                    .ignoresSafeArea(.all)
                    .onAppear {
                        coordinator.permissionManager.checkAll()
                        if coordinator.permissionManager.allGranted {
                            goToMainScreen()
                        }
                    }
                    .transition(.opacity)
            } else {
                // 5. Негізгі экран (барлық рөл)
                JanarymMainView(coordinator: coordinator)
                    .transition(.opacity)
                    .onAppear {
                        if !permissionsReady { permissionsReady = true }
                        coordinator.onMainViewAppear()
                    }
                    .onDisappear { coordinator.onMainViewDisappear() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.4), value: authService.isAuthenticated)
        .animation(.easeInOut(duration: 0.5), value: onboarding.isCompleted)
        .animation(.easeInOut(duration: 0.4), value: permissionsReady)
        .animation(.easeInOut(duration: 0.25), value: authService.isRestoringSession)
        .withLifecycle(coordinator: coordinator)
        .onAppear {
            refreshPermissionsState()
        }
        .onChange(of: onboarding.isCompleted) { completed in
            if completed {
                refreshPermissionsState()
            }
        }
        .onChange(of: authService.isAuthenticated) { authenticated in
            if authenticated {
                refreshPermissionsState()
            } else {
                permissionsReady = false
            }
        }
        // Permissions granted → navigate (3 independent listeners for bulletproof detection)
        .onReceive(coordinator.permissionManager.$allGranted.removeDuplicates()) { granted in
            if granted { goToMainScreen() }
        }
        .onReceive(coordinator.permissionManager.$cameraGranted) { _ in
            recheckAndNavigate()
        }
        .onReceive(coordinator.permissionManager.$microphoneGranted) { _ in
            recheckAndNavigate()
        }
        // Settings-тен қайтқанда рұқсаттарды қайта тексеру
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active, !permissionsReady {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    coordinator.permissionManager.checkAll()
                    recheckAndNavigate()
                }
            }
        }
        // Notification fallback — UIApplication.didBecomeActiveNotification
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            guard !permissionsReady else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                coordinator.permissionManager.checkAll()
                recheckAndNavigate()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func goToMainScreen() {
        let role = authService.currentUser?.role
        let isAdminOrMentor = role == .admin || role == .mentor || role == .developer
        guard !permissionsReady,
              authService.isAuthenticated,
              onboarding.isCompleted || isAdminOrMentor else { return }
        print("🟢 goToMainScreen() called — navigating to camera")
        // Pre-warm audio session on a background thread so the main thread is never
        // blocked by setCategory/setActive during the permission-granted transition.
        Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.mixWithOthers, .allowBluetoothHFP, .defaultToSpeaker]
            )
            try? session.setActive(true)
            try? session.overrideOutputAudioPort(.speaker)
        }
        permissionsReady = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            coordinator.onPermissionsGranted()
        }
    }

    /// Жеке рұқсат @Published өзгергенде — бәрі берілсе navigate ету
    private func recheckAndNavigate() {
        let pm = coordinator.permissionManager
        if pm.cameraGranted, pm.microphoneGranted {
            goToMainScreen()
        }
    }

    private func refreshPermissionsState() {
        coordinator.permissionManager.checkAll()
        recheckAndNavigate()
    }
}

struct AppStartupView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.08),
                         Color(red: 0.07, green: 0.10, blue: 0.16)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(.all)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 88, height: 88)
                    Image(systemName: "eye.fill")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(Color.green)
                }

                Text("Жанарым")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)

                ProgressView()
                    .tint(.white)

                Text(AppText.pick("Қосымша жүктеліп жатыр...", "Загрузка приложения..."))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

struct LanguageSwitcher: View {
    @ObservedObject private var onboarding = OnboardingStore.shared
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            ForEach(UserProfile.Language.allCases, id: \.self) { language in
                Button {
                    onboarding.updateLanguage(language)
                } label: {
                    Text(language.shortLabel)
                        .font(.system(size: compact ? 12 : 13, weight: .bold))
                        .foregroundStyle(onboarding.currentLanguage == language ? .black : .white.opacity(0.75))
                        .padding(.horizontal, compact ? 10 : 12)
                        .padding(.vertical, compact ? 7 : 8)
                        .background(
                            Capsule()
                                .fill(onboarding.currentLanguage == language ? Color.green : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(compact ? 4 : 6)
        .background(Capsule().fill(Color.black.opacity(0.28)))
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - Main View

struct JanarymMainView: View {
    @ObservedObject var coordinator: AssistantCoordinator
    @ObservedObject private var cameraService: CameraService
    @ObservedObject private var esp32Camera: ESP32CameraService
    private let arFrameStaleThreshold: TimeInterval = 2.5

    @State private var isModesOpen = false
    @State private var showPaywall = false
    @ObservedObject private var realtimeService: OpenAIRealtimeService
    @State private var showDashboard = false
    @State private var showLogoutConfirm = false
    @State private var showTierInfo = false
    @State private var showCameraOverlay = true
    @State private var showMedCard = false
    @State private var showSettings = false
    @ObservedObject private var sub = SubscriptionManager.shared
    @ObservedObject private var onboarding = OnboardingStore.shared
    @EnvironmentObject private var authService: AuthService
    
    private var kk: Bool { onboarding.profile.language == .kazakh }
    private var pttTapCountRequired: Int { coordinator.activeMode == .arGlasses ? 2 : 1 }
    private var arPreviewTitle: String {
        switch esp32Camera.connectionIssue {
        case .localNetworkDenied:
            return kk ? "Жергілікті желіге рұқсат керек" : "Нужен доступ к локальной сети"
        case .appTransportBlocked:
            return kk ? "AR камераға кіру бұғатталды" : "Доступ к AR-камере заблокирован"
        default:
            return kk ? "AR көзілдірікке қосылуда" : "Подключение к AR-очкам"
        }
    }
    private var arPreviewSubtitle: String {
        if esp32Camera.isDiscoveringViaBluetooth {
            return kk
                ? "Bluetooth арқылы камераны іздеп, адресін автоматты алып жатырмын."
                : "Ищу камеру по Bluetooth и автоматически забираю её адрес."
        }
        switch esp32Camera.connectionIssue {
        case .localNetworkDenied:
            return kk
                ? "iPhone баптауларынан Janarym үшін Local Network рұқсатын қосыңыз."
                : "В настройках iPhone включите для Janarym доступ к Local Network."
        case .appTransportBlocked:
            return kk
                ? "Жергілікті IP-ге HTTP сұрауы бұғатталды. Қолданбаның жаңа build-н орнатыңыз."
                : "HTTP-запрос к локальному IP заблокирован. Установите новую сборку приложения."
        case .timedOut, .unreachable:
            return kk
                ? "ESP32 адресі ашылмады. iPhone мен камера бір Wi‑Fi-де екенін тексеріңіз."
                : "ESP32 не отвечает по адресу. Проверьте, что iPhone и камера в одной Wi‑Fi сети."
        case .invalidResponse:
            return kk
                ? "Камера жауап берді, бірақ snapshot қате келді. ESP-ні қайта қосып көріңіз."
                : "Камера отвечает, но snapshot пришёл некорректно. Попробуйте переподключить ESP."
        case .unknown:
            return kk
                ? "Камерамен байланыс орнамады. IP-ді тексеріп, қайта ашып көріңіз."
                : "Не удалось установить связь с камерой. Проверьте IP и откройте режим снова."
        case .none:
            return kk
                ? "Камера мен iPhone бір Wi‑Fi-де болсын. Қажет болса IP-ді баптаулардан өзгертіңіз."
                : "Камера и iPhone должны быть в одной Wi‑Fi сети. При необходимости измените IP в настройках."
        }
    }
    private var pttAccessibilityHint: String {
        if coordinator.activeMode == .arGlasses {
            return kk
                ? "Сөйлесу үшін экранның бос жерін 2 рет басыңыз"
                : "Дважды коснитесь пустой области экрана, чтобы говорить"
        }
        return kk
            ? "Сөйлесу үшін экранның кез келген жерін басыңыз"
            : "Коснитесь любого места экрана, чтобы говорить"
    }
    private func isARPreviewStale(at date: Date) -> Bool {
        guard coordinator.activeMode == .arGlasses else { return false }
        guard esp32Camera.latestSnapshot != nil else { return !esp32Camera.isConnected }
        guard let lastSnapshotAt = esp32Camera.lastSnapshotAt else { return true }
        return date.timeIntervalSince(lastSnapshotAt) > arFrameStaleThreshold
    }
    private func arFrameStatusText(at date: Date) -> String {
        guard let lastSnapshotAt = esp32Camera.lastSnapshotAt else {
            return kk ? "Кадр күтілуде" : "Ожидаем кадр"
        }
        let age = max(0, Int(date.timeIntervalSince(lastSnapshotAt)))
        if isARPreviewStale(at: date) {
            return kk ? "Кадр тоқтап қалды: \(age) с" : "Кадр завис: \(age) с"
        }
        return kk ? (age <= 1 ? "Тікелей кадр" : "Соңғы кадр \(age) с бұрын")
                  : (age <= 1 ? "Живой кадр" : "Последний кадр \(age) с назад")
    }
    private var arActionHint: String {
        if esp32Camera.isDiscoveringViaBluetooth {
            return kk
                ? "Bluetooth іздеу жүріп жатыр. Камера қосулы және жақын жерде болсын."
                : "Идёт поиск по Bluetooth. Камера должна быть включена и рядом."
        }
        return kk
            ? "Экранды 2 рет басып сұрақ қойыңыз. Егер кадр тоқтаса, қайта қосылуды басыңыз."
            : "Дважды коснитесь экрана, чтобы задать вопрос. Если кадр завис, нажмите переподключение."
    }

    init(coordinator: AssistantCoordinator) {
        self.coordinator = coordinator
        _cameraService = ObservedObject(wrappedValue: coordinator.cameraService)
        _esp32Camera = ObservedObject(wrappedValue: coordinator.esp32Camera)
        _realtimeService = ObservedObject(wrappedValue: coordinator.realtimeService)
    }

    var body: some View {
        GeometryReader { geo in
        ZStack {
            Group {
                if coordinator.activeMode == .arGlasses {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        SnapshotPreviewView(
                            imageData: esp32Camera.latestSnapshot,
                            isConnected: esp32Camera.isConnected,
                            title: arPreviewTitle,
                            subtitle: arPreviewSubtitle,
                            statusText: arFrameStatusText(at: context.date),
                            showStaleOverlay: isARPreviewStale(at: context.date)
                        )
                    }
                } else {
                    // Камера preview — толық экран, safe area-ны елемейді
                    CameraPreviewView(
                        session: cameraService.session,
                        isActive: true
                    )
                }
            }
            .ignoresSafeArea(.all)
            .allowsHitTesting(false)

            if coordinator.activeMode != .arGlasses && showCameraOverlay && (!cameraService.isRunning || cameraService.error != nil) {
                CameraStartupOverlay(
                    error: cameraService.error,
                    isStarting: cameraService.isStarting
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            }

            // Dim overlay
            Color.black
                .opacity(isModesOpen ? 0.15 : 0)
                .ignoresSafeArea(.all)
                .allowsHitTesting(isModesOpen)
                .onTapGesture { closeMenu() }
                .animation(.easeInOut(duration: 0.2), value: isModesOpen)

            // ── Transparent PTT tap zone (accessibility: any tap starts/stops recording) ──
            // Placed BELOW UI overlay so buttons (settings, medcard, modes) still get taps.
            // Placed ABOVE Dim overlay so when menu closed, full screen triggers PTT.
            Color.clear
                .contentShape(Rectangle())
                .padding(.top, coordinator.activeMode == .arGlasses ? 150 : 110)
                .padding(.bottom, 120)
                .onTapGesture(count: pttTapCountRequired) { toggleVoiceCapture() }
                .allowsHitTesting(!isModesOpen)
                .accessibilityLabel(kk ? "Дауысты басу аймағы" : "Зона голоса")
                .accessibilityHint(pttAccessibilityHint)
                .accessibilityAddTraits(.isButton)

            // UI overlay — safe area-ны сақтайды (Dynamic Island-ды жаппайды)
            VStack(spacing: 0) {
                // Top bar — status pill + badges
                HStack {
                    JStatusPill(assistantMode: coordinator.mode, appMode: coordinator.activeMode)

                    // Offline mode indicator
                    if coordinator.isOfflineMode {
                        HStack(spacing: 4) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 10, weight: .bold))
                            Text(kk ? "Офлайн" : "Офлайн")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
                        .transition(.opacity.combined(with: .scale))
                        .animation(.easeInOut(duration: 0.3), value: coordinator.isOfflineMode)
                    }

                    Spacer()

                    // Dashboard button (developer / admin / mentor / parent)
                    if let role = authService.currentUser?.role, !role.isStandardUser {
                        let dashInfo: (icon: String, color: Color) = {
                            switch role {
                            case .developer: return ("terminal.fill", Color(red: 0.6, green: 0.2, blue: 1.0))
                            case .admin:     return ("crown.fill", .yellow)
                            case .parent:    return ("figure.and.child.holdinghands", Color(red: 1.0, green: 0.6, blue: 0.2))
                            default:         return ("person.2.fill", Color(red: 0.4, green: 0.6, blue: 1.0))
                            }
                        }()
                        Button { showDashboard = true } label: {
                            Image(systemName: dashInfo.icon)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(dashInfo.color)
                                .padding(8)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Circle())
                                .overlay { Circle().strokeBorder(dashInfo.color.opacity(0.4), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }

                    if sub.isVIP {
                        Button { showTierInfo = true } label: { TierBadge(tier: .vip) }
                            .buttonStyle(.plain)
                    } else if sub.isPremium {
                        Button { showTierInfo = true } label: { TierBadge(tier: .premium) }
                            .buttonStyle(.plain)
                    } else {
                        FreeUsageBadge(remaining: sub.requestsRemaining) {
                            showPaywall = true
                        }
                    }

                    // Logout menu
                    Menu {
                        if let user = authService.currentUser {
                            Section {
                                Label(user.name, systemImage: "person.fill")
                                Label(user.role.label, systemImage: "shield.fill")
                            }
                        }
                        Section(header: Text(AppText.pick("Тіл", "Язык", language: onboarding.currentLanguage))) {
                            ForEach(UserProfile.Language.allCases, id: \.self) { language in
                                Button {
                                    onboarding.updateLanguage(language)
                                } label: {
                                    Label(
                                        language.displayName,
                                        systemImage: onboarding.currentLanguage == language ? "checkmark.circle.fill" : "circle"
                                    )
                                }
                            }
                        }
                        Button(role: .destructive) {
                            showLogoutConfirm = true
                        } label: {
                            Label(AppText.pick("Шығу", "Выйти", language: onboarding.currentLanguage), systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 16)
                // VStack safe area сақтайды — Dynamic Island-тан автоматты кейін тұрады

                if coordinator.activeMode == .arGlasses {
                    HStack {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            ARGlassesConnectionBadge(
                                host: esp32Camera.host,
                                isConnected: esp32Camera.isConnected,
                                isFrameStale: isARPreviewStale(at: context.date),
                                statusText: arFrameStatusText(at: context.date),
                                hintText: arActionHint,
                                kk: kk,
                                onRetry: restartARConnection,
                                onOpenSettings: { showSettings = true },
                                onExit: { coordinator.activeMode = .general }
                            )
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                    .zIndex(3)
                }

                // Transcription + Response overlay
                if !coordinator.liveTranscript.isEmpty || !coordinator.liveResponseText.isEmpty {
                    ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !coordinator.liveTranscript.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text(coordinator.liveTranscript)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(8)
                            }
                        }
                        if !coordinator.liveResponseText.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.green.opacity(0.8))
                                Text(coordinator.liveResponseText)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(8)
                            }
                        }
                    }
                    }
                    .frame(maxHeight: 180)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeInOut(duration: 0.3), value: coordinator.liveTranscript)
                }

                Spacer()

                // Bottom — PTT button + MedCard + modes menu + button
                // GeometryReader geo пайдаланамыз — landscape-да overflow болмасын
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        // Settings button
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(kk ? "Баптаулар" : "Настройки")

                        // MedCard button
                        Button { showMedCard = true } label: {
                            Image(systemName: "cross.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.red)
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Color.red.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(kk ? "Медициналық карта" : "Медкарта")
                    }
                    .padding(.leading, 24)
                    .padding(.bottom, 16)

                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        if isModesOpen {
                            // ScrollView — landscape-да height аз болса scroll жасайды
                            ScrollView(.vertical, showsIndicators: false) {
                                JModesMenu(
                                    activeMode: coordinator.activeMode,
                                    onModeTap: { mode in
                                        if !mode.isAvailable {
                                            showPaywall = true
                                            closeMenu()
                                            return
                                        }
                                        coordinator.activeMode = mode
                                        closeMenu()
                                    }
                                )
                                .padding(.vertical, 4)
                            }
                            // Landscape үшін: экран биіктігінен 100px (topBar+button) алып тастаймыз
                            .frame(maxHeight: max(160, geo.size.height - 100))
                            .transition(
                                .move(edge: .trailing)
                                    .combined(with: .opacity)
                            )
                        }

                        // Modes button (always visible)
                        JModesButton(isOpen: isModesOpen) { toggleMenu() }
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 16)
                    .animation(.easeInOut(duration: 0.18), value: isModesOpen)
                }
            }
        }
        } // GeometryReader
        .onAppear {
            showCameraOverlay = true
        }
        .onDisappear {
            showCameraOverlay = false
        }
        // Voice command — UI actions
        .onReceive(coordinator.$uiCommand.compactMap { $0 }) { cmd in
            coordinator.uiCommand = nil
            switch cmd {
            case .settings:      showSettings = true
            case .medCard:       showMedCard  = true
            case .back:          break   // no nav stack — ignore or dismiss
            case .whereIsParent:
                // Speak parent location from presence
                let lang: DetectedLanguage = OnboardingStore.shared.profile.language.detectedLanguage
                let phrase = AppText.pick(
                    "Ата-ана орналасуын тексеріп жатырмын",
                    "Проверяю местоположение родителя",
                    en: "Checking parent location"
                )
                coordinator.ttsService.speak(phrase, language: lang)
            default: break
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showMedCard) {
            MedCardScreen()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showTierInfo) {
            TierInfoSheet(tier: sub.tier)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPaywall)) { _ in
            showPaywall = true
        }
        .sheet(isPresented: $showDashboard) {
            if let user = authService.currentUser {
                if user.role == .developer {
                    DeveloperDashboardView().environmentObject(authService)
                } else if user.role == .admin {
                    AdminDashboardView().environmentObject(authService)
                } else {
                    MentorDashboardView(user: user).environmentObject(authService)
                }
            }
        }
        .alert(AppText.pick("Шығу", "Выйти", language: onboarding.currentLanguage), isPresented: $showLogoutConfirm) {
            Button(AppText.pick("Жоқ", "Нет", language: onboarding.currentLanguage), role: .cancel) { }
            Button(AppText.pick("Иә, шығу", "Да, выйти", language: onboarding.currentLanguage), role: .destructive) {
                authService.signOut()
            }
        } message: {
            Text(AppText.pick("Аккаунттан шығасыз ба?", "Выйти из аккаунта?", language: onboarding.currentLanguage))
        }
    }

    // MARK: - Menu toggle (single state, no asyncAfter race)

    private func toggleMenu() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isModesOpen.toggle()
        }
    }

    private func closeMenu() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isModesOpen = false
        }
    }

    private func restartARConnection() {
        coordinator.esp32Camera.stopPolling(preserveLatestFrame: true)
        coordinator.esp32Camera.discoverHostViaBluetooth()
        coordinator.esp32Camera.startPolling()
    }

    private func toggleVoiceCapture() {
        // Gate on coordinator.mode (not realtimeService.state): the realtime state
        // transiently reports .idle during startPTT while we're still playing the
        // "listening" prompt, which would otherwise let a double-tap fire startPTT
        // twice. mode is authoritative — it flips to .recording synchronously.
        switch coordinator.mode {
        case .recording:
            coordinator.stopPTT()
        case .idle, .error, .speaking:
            coordinator.startPTT()
        case .processing:
            break
        }
    }
}

struct CameraStartupOverlay: View {
    let error: AppError?
    var isStarting: Bool = false
    @ObservedObject private var onboarding = OnboardingStore.shared

    private var label: String {
        let kk = onboarding.currentLanguage == .kazakh
        if let _ = error {
            return kk ? "Камера қайта іске қосылып жатыр..." : "Перезапуск камеры..."
        }
        return kk ? "Камера іске қосылып жатыр..." : "Запуск камеры..."
    }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.15)

            Text(label)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
    }
}

// MARK: - Status Pill

struct JStatusPill: View {
    let assistantMode: AssistantMode
    let appMode: AppMode
    @ObservedObject private var onboarding = OnboardingStore.shared

    private var kk: Bool { onboarding.profile.language == .kazakh }

    private var modeLabel: String {
        if appMode == .general {
            return AppText.pick("Жалпы режим", "Общий режим", language: onboarding.currentLanguage)
        }
        return appMode.localizedName
    }

    private var subLabel: String { assistantMode.localizedTitle }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: appMode.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))

            Text(modeLabel)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            JPulsingDot(assistantMode: assistantMode)

            Text(subLabel)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .background {
            Capsule()
                .fill(Color.black.opacity(0.55))
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .animation(.easeInOut(duration: 0.25), value: assistantMode)
    }
}

struct ARGlassesConnectionBadge: View {
    let host: String
    let isConnected: Bool
    let isFrameStale: Bool
    let statusText: String
    let hintText: String
    let kk: Bool
    var onRetry: (() -> Void)? = nil
    var onOpenSettings: (() -> Void)? = nil
    var onExit: (() -> Void)? = nil

    @State private var dotOpacity: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if isConnected && !isFrameStale {
                    Image(systemName: "wifi")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.cyan)
                } else {
                    HStack(spacing: 3) {
                        ForEach(0..<3) { i in
                            Circle()
                                .fill(Color.white.opacity(0.6))
                                .frame(width: 4, height: 4)
                                .opacity(dotOpacity)
                                .animation(
                                    .easeInOut(duration: 0.6)
                                        .repeatForever()
                                        .delay(Double(i) * 0.2),
                                    value: dotOpacity
                                )
                        }
                    }
                    .onAppear { dotOpacity = 0.2 }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(kk ? "AR көзілдірік" : "AR очки")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(host)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer(minLength: 6)

                Text(statusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isFrameStale ? Color.orange : .white.opacity(0.82))
            }

            Text(hintText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))

            HStack(spacing: 8) {
                if (!isConnected || isFrameStale), let onRetry {
                    Button(action: onRetry) {
                        Label(kk ? "Қайта қосу" : "Повтор", systemImage: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if let onOpenSettings {
                    Button(action: onOpenSettings) {
                        Label(kk ? "IP баптау" : "IP", systemImage: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if let onExit {
                    Button(action: onExit) {
                        Label(kk ? "Шығу" : "Выйти", systemImage: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.black.opacity(0.52))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    (isConnected && !isFrameStale ? Color.cyan : Color.orange).opacity(isConnected && !isFrameStale ? 0.22 : 0.45),
                    lineWidth: 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Pulsing Dot

struct JPulsingDot: View {
    let assistantMode: AssistantMode

    @State private var scale: CGFloat = 1
    @State private var opacity: CGFloat = 0.5

    private var dotColor: Color {
        switch assistantMode {
        case .idle:       return Color(red: 0.2, green: 0.78, blue: 0.35)
        case .recording:  return Color(red: 0.98, green: 0.45, blue: 0.1)
        case .processing: return Color(red: 0.55, green: 0.36, blue: 0.97)
        case .speaking:   return Color(red: 0.2, green: 0.78, blue: 0.55)
        case .error:      return Color(red: 0.95, green: 0.3, blue: 0.3)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(dotColor.opacity(0.3))
                .frame(width: 18, height: 18)
                .scaleEffect(scale)
                .opacity(opacity)
            Circle()
                .fill(dotColor)
                .frame(width: 9, height: 9)
        }
        .onAppear { pulse() }
        .onChange(of: assistantMode) { _ in pulse() }
    }

    private func pulse() {
        scale = 1; opacity = 0.5
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            scale = 1.6
            opacity = 0
        }
    }
}

// MARK: - Mode Pill (simplified — no isVisible/index state)

struct JModesMenu: View {
    let activeMode: AppMode
    let onModeTap: (AppMode) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(AppMode.allCases) { mode in
                JModePill(
                    mode: mode,
                    isActive: activeMode == mode,
                    onTap: { onModeTap(mode) }
                )
            }
        }
    }
}

struct JModePill: View {
    let mode: AppMode
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: mode.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.8))
                    .frame(width: 20)

                Text(mode.localizedName)
                    .font(.system(size: 16, weight: isActive ? .bold : .semibold))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize()

                Spacer(minLength: 0)

                if isActive {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.78, blue: 0.35))
                        .frame(width: 8, height: 8)
                        .shadow(color: .green.opacity(0.8), radius: 3)
                } else if !mode.isAvailable {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 15)
            .frame(width: mode.pillWidth, alignment: .leading)
            .background {
                Capsule()
                    .fill(isActive ? Color.green.opacity(0.25) : Color.black.opacity(0.65))
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                isActive ? Color.green.opacity(0.6) : Color.white.opacity(0.16),
                                lineWidth: 1
                            )
                    }
            }
            .shadow(
                color: isActive ? .green.opacity(0.14) : .black.opacity(0.18),
                radius: 8,
                y: 3
            )
            .opacity(isActive ? 1 : (mode.isAvailable ? 1 : 0.45))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.localizedName)
    }
}

// MARK: - Modes Button (circle with 2x2 grid)

struct JModesButton: View {
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.65))
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(isOpen ? 0.5 : 0.22), lineWidth: 1.5)
                    }
                    .shadow(color: .black.opacity(0.24), radius: 12, y: 6)

                // 2x2 grid icon
                VStack(spacing: 5) {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.9)).frame(width: 9, height: 9)
                        RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.9)).frame(width: 9, height: 9)
                    }
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.9)).frame(width: 9, height: 9)
                        RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.9)).frame(width: 9, height: 9)
                    }
                }
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .animation(.easeInOut(duration: 0.18), value: isOpen)
            }
            .frame(width: 64, height: 64)
        }
        .buttonStyle(.plain)
        .scaleEffect(isOpen ? 1.05 : 1)
        .animation(.easeInOut(duration: 0.18), value: isOpen)
    }
}

// MARK: - Tier Badge (Premium / VIP)

struct TierBadge: View {
    let tier: SubscriptionTier

    private var icon: String {
        tier == .vip ? "crown.fill" : "star.fill"
    }
    private var label: String {
        tier == .vip ? "VIP" : "Premium"
    }
    private var color: Color {
        tier == .vip ? .yellow : .green
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(Color.black.opacity(0.55))
                .overlay { Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1) }
        }
    }
}

// MARK: - Free Usage Badge

struct FreeUsageBadge: View {
    let remaining: Int
    let onTap: () -> Void
    private var kk: Bool { OnboardingStore.shared.profile.language == .kazakh }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: remaining == 0 ? "xmark.circle.fill" : remaining <= 3 ? "exclamationmark.circle.fill" : "bolt.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(remaining == 0 ? .red : remaining <= 3 ? .orange : .white.opacity(0.7))
                Text(remaining == 0
                     ? (kk ? "Тегін аяқталды" : "Бесплатное исчерпано")
                     : "\(remaining) \(kk ? "тегін" : "бесплатно")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(remaining == 0 ? .red : remaining <= 3 ? .orange : .white.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(Color.black.opacity(0.55))
                    .overlay {
                        Capsule().strokeBorder(
                            remaining == 0 ? .red.opacity(0.6) : remaining <= 3 ? .orange.opacity(0.5) : .white.opacity(0.2),
                            lineWidth: 1
                        )
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tier Info Sheet

struct TierInfoSheet: View {
    let tier: SubscriptionTier
    @Environment(\.dismiss) private var dismiss
    private var kk: Bool { OnboardingStore.shared.profile.language == .kazakh }

    private var tierColor: Color  { tier == .vip ? .yellow : .green }
    private var tierIcon: String  { tier == .vip ? "crown.fill" : "star.fill" }
    private var tierName: String  { tier == .vip ? "VIP" : "Premium" }
    private var tierPrice: String { tier == .vip ? "15 000 ₸" : "5 000 ₸" }

    private var features: [(icon: String, text: String)] {
        if tier == .vip {
            return kk ? [
                ("infinity",             "Шексіз сұрақтар"),
                ("camera.fill",          "Жоғары сапалы AI көру (512px)"),
                ("square.grid.2x2.fill", "Барлық режимдер қол жетімді"),
                ("mic.fill",             "Жанды дауыстық ассистент"),
                ("map.fill",             "Навигация режимі"),
                ("shield.fill",          "Қауіпсіздік режимі"),
                ("photo.fill",           "Жоғары сапалы сурет талдауы"),
            ] : [
                ("infinity",             "Безлимитные запросы"),
                ("camera.fill",          "Высококачественное AI-зрение (512px)"),
                ("square.grid.2x2.fill", "Все режимы доступны"),
                ("mic.fill",             "Живой голосовой ассистент"),
                ("map.fill",             "Режим навигации"),
                ("shield.fill",          "Режим безопасности"),
                ("photo.fill",           "Высокое качество анализа изображений"),
            ]
        } else {
            return kk ? [
                ("50.circle.fill",       "Күніне 50 сұрақ"),
                ("camera.fill",          "Камера арқылы AI көру (384px)"),
                ("square.grid.2x2.fill", "Жалпы + Оқу + Сауда режимдері"),
                ("mic.fill",             "Жанды дауыстық батырма"),
                ("speaker.wave.2.fill",  "Дауыс синтезі"),
            ] : [
                ("50.circle.fill",       "50 запросов в день"),
                ("camera.fill",          "AI-зрение через камеру (384px)"),
                ("square.grid.2x2.fill", "Общий + Чтение + Покупки режимы"),
                ("mic.fill",             "Кнопка живого голоса"),
                ("speaker.wave.2.fill",  "Синтез речи"),
            ]
        }
    }

    private var notIncluded: [String] {
        guard tier == .premium else { return [] }
        return kk ? [
            "Навигация және Қауіпсіздік режимі",
        ] : [
            "Навигация и режим безопасности",
        ]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Circle()
                .fill(tierColor.opacity(0.1))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(y: -100)
                .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(tierColor.opacity(0.15))
                                .frame(width: 80, height: 80)
                            Image(systemName: tierIcon)
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(tierColor)
                        }
                        .padding(.top, 40)

                        Text(tierName)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(tierPrice)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(tierColor)
                            Text(kk ? "/ ай" : "/ месяц")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        Text(kk ? "Сіздің тарифіңізде:" : "В вашем тарифе:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.top, 2)
                    }
                    .padding(.bottom, 28)

                    // Included features
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(features.enumerated()), id: \.offset) { idx, item in
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(tierColor.opacity(0.15))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: item.icon)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(tierColor)
                                }
                                Text(item.text)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.white.opacity(0.9))
                                Spacer()
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(tierColor.opacity(0.8))
                            }
                            .padding(.vertical, 13)
                            .padding(.horizontal, 20)

                            if idx < features.count - 1 {
                                Divider()
                                    .background(.white.opacity(0.07))
                                    .padding(.leading, 70)
                            }
                        }
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white.opacity(0.05))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18)
                                    .strokeBorder(tierColor.opacity(0.25), lineWidth: 1)
                            }
                    }
                    .padding(.horizontal, 20)

                    // Not included — Premium only
                    if !notIncluded.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(kk ? "VIP-та қосымша:" : "Дополнительно в VIP:")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.3))
                                .padding(.horizontal, 20)
                                .padding(.top, 22)
                                .padding(.bottom, 8)

                            ForEach(notIncluded, id: \.self) { item in
                                HStack(spacing: 14) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.18))
                                        .frame(width: 36)
                                    Text(item)
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.28))
                                    Spacer()
                                }
                                .padding(.vertical, 9)
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Change plan button
                    Button {
                        dismiss()
                        // Dismiss жабылғаннан кейін PaywallView ашу үшін notification
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            NotificationCenter.default.post(name: .openPaywall, object: nil)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 14, weight: .medium))
                            Text(kk ? "Жоспарды өзгерту" : "Сменить план")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.07))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                                }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                    Spacer(minLength: 48)
                }
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .padding(.top, 16)
                    .padding(.trailing, 16)
                }
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}

extension Notification.Name {
    static let openPaywall = Notification.Name("openPaywall")
}
