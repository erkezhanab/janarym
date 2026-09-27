import SwiftUI

struct PermissionsView: View {

    @ObservedObject var manager: PermissionManager
    @ObservedObject private var onboarding = OnboardingStore.shared
    var onContinue: () -> Void = {}

    @State private var showShield = false
    @State private var showTitle = false
    @State private var showRow1 = false
    @State private var showRow2 = false
    @State private var showButton = false
    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 0.4
    @State private var buttonPressed = false

    // Floating particles
    @State private var particleOffsets: [CGSize] = (0..<6).map { _ in
        CGSize(width: CGFloat.random(in: -150...150), height: CGFloat.random(in: -300...300))
    }

    private let greenAccent = Color(red: 0.12, green: 0.79, blue: 0.32)
    private var language: UserProfile.Language { onboarding.currentLanguage }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(hex: "060d1a"), Color(hex: "0a1628")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(.all)

            // Floating particles
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(Double.random(in: 0.03...0.06)))
                    .frame(width: CGFloat.random(in: 20...60), height: CGFloat.random(in: 20...60))
                    .offset(particleOffsets[i])
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: Double.random(in: 4...8))
                            .repeatForever(autoreverses: true)
                        ) {
                            particleOffsets[i] = CGSize(
                                width: CGFloat.random(in: -150...150),
                                height: CGFloat.random(in: -300...300)
                            )
                        }
                    }
            }

            VStack(spacing: 0) {
                Spacer()

                // Shield icon with animated glow ring
                ZStack {
                    // Glow ring — pulse outward
                    Circle()
                        .stroke(greenAccent.opacity(0.4), lineWidth: 2)
                        .frame(width: 100, height: 100)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)

                    // Shield background
                    Circle()
                        .fill(greenAccent.opacity(0.15))
                        .frame(width: 80, height: 80)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(greenAccent)
                }
                .opacity(showShield ? 1 : 0)
                .offset(y: showShield ? 0 : -30)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.6)) { showShield = true }
                    withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) {
                        ringScale = 1.3
                        ringOpacity = 0
                    }
                }

                Spacer().frame(height: 28)

                // Title
                Text(AppText.pick("Janarym жұмыс істеу үшін\nрұқсаттар қажет", "Для работы Janarym\nнужны разрешения", language: language))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .opacity(showTitle ? 1 : 0)
                    .offset(y: showTitle ? 0 : 15)
                    .onAppear {
                        withAnimation(.easeOut(duration: 0.5).delay(0.2)) { showTitle = true }
                    }

                Spacer().frame(height: 40)

                // Permission rows with stagger animation
                VStack(spacing: 14) {
                    AnimatedPermissionRow(
                        icon: "camera.fill",
                        title: AppText.pick("Камера", "Камера", language: language),
                        subtitle: AppText.pick("Айналаны көру үшін", "Чтобы видеть вокруг", language: language),
                        granted: manager.cameraGranted,
                        show: showRow1
                    )

                    AnimatedPermissionRow(
                        icon: "mic.fill",
                        title: AppText.pick("Микрофон", "Микрофон", language: language),
                        subtitle: AppText.pick("Дауысты тыңдау үшін", "Чтобы слушать голос", language: language),
                        granted: manager.microphoneGranted,
                        show: showRow2
                    )
                }
                .padding(.horizontal, 28)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.5).delay(0.3)) { showRow1 = true }
                    withAnimation(.easeOut(duration: 0.5).delay(0.45)) { showRow2 = true }
                }

                Spacer().frame(height: 36)

                // Request button (рұқсат бергенде "Жалғастыру"-ға ауысады)
                if manager.allGranted {
                    // All granted — navigate to main screen
                    // RootView-дағы .onChange(of: allGranted) автоматты navigate етеді
                    // Бұл button — fallback (onChange race condition болғанда)
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        manager.checkAll()
                        onContinue()
                    } label: {
                        Text(AppText.pick("Жалғастыру", "Продолжить", language: language))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(LinearGradient(
                                        colors: [Color(hex: "1ec952"), Color(hex: "17a644")],
                                        startPoint: .leading, endPoint: .trailing
                                    ))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 28)
                    .transition(.asymmetric(
                        insertion: .offset(y: 40).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .animation(.spring(duration: 0.5, bounce: 0.4), value: manager.allGranted)
                } else {
                    VStack(spacing: 14) {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            buttonPressed = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                buttonPressed = false
                            }
                            manager.requestAll()
                        } label: {
                            Text(AppText.pick("Рұқсат беру", "Разрешить доступ", language: language))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 58)
                                .background(
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(LinearGradient(
                                            colors: [Color(hex: "1ec952"), Color(hex: "17a644")],
                                            startPoint: .leading, endPoint: .trailing
                                        ))
                                )
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(buttonPressed ? 0.95 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: buttonPressed)

                        Button {
                            manager.openSettings()
                        } label: {
                            Text(AppText.pick("Баптауларды ашу", "Открыть настройки", language: language))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 28)
                    .opacity(showButton ? 1 : 0)
                    .offset(y: showButton ? 0 : 20)
                    .onAppear {
                        withAnimation(.easeOut(duration: 0.5).delay(0.7)) { showButton = true }
                    }
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.all)
        .onChange(of: manager.allGranted) { granted in
            guard granted else { return }
            // Small delay: let the permission dialog fully dismiss + release its
            // audio session before we activate ours. Without this, setActive(true)
            // on the main thread can race with the system's speech-rec cleanup.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                onContinue()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Animated Permission Row

struct AnimatedPermissionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let granted: Bool
    let show: Bool

    private let greenAccent = Color(red: 0.12, green: 0.79, blue: 0.32)

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            // Checkmark
            ZStack {
                Circle()
                    .fill(granted ? greenAccent : Color.white.opacity(0.08))
                    .frame(width: 30, height: 30)

                if granted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 30, height: 30)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: granted)
            .onChange(of: granted) { newValue in
                if newValue {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            granted ? greenAccent.opacity(0.4) : Color.white.opacity(0.1),
                            lineWidth: 1
                        )
                }
        )
        .opacity(show ? 1 : 0)
        .offset(x: show ? 0 : -50)
    }
}

// MARK: - Color hex extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}
