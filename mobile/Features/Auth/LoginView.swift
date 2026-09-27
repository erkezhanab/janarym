import SwiftUI

// MARK: - Login View

struct LoginView: View {

    @EnvironmentObject private var authService: AuthService
    @ObservedObject private var onboarding = OnboardingStore.shared

    @State private var email    = ""
    @State private var password = ""
    @State private var showApplication = false

    private var language: UserProfile.Language { onboarding.currentLanguage }
    private var kk: Bool { language == .kazakh }

    var body: some View {
        ZStack {
            // Background gradient
            Color(red: 0.04, green: 0.04, blue: 0.08)
                .ignoresSafeArea(.all)

            LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.08),
                         Color(red: 0.07, green: 0.10, blue: 0.16)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(.all)

            // Subtle glow
            Circle()
                .fill(Color.green.opacity(0.08))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(y: -120)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    LanguageSwitcher(compact: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                Spacer()

                // Logo
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 80, height: 80)
                        Image(systemName: "eye.fill")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(Color.green)
                    }

                    Text("Жанарым")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)

                    Text(AppText.pick("Дауыстық AI-ассистент", "Голосовой AI-ассистент", language: language))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.bottom, 48)

                // Card
                VStack(spacing: 16) {

                    // Email field
                    JAuthField(
                        icon: "envelope.fill",
                        placeholder: "Email",
                        text: $email,
                        isSecure: false,
                        keyboardType: .emailAddress
                    )

                    // Password field
                    JAuthField(
                        icon: "lock.fill",
                        placeholder: AppText.pick("Құпия сөз", "Пароль", language: language),
                        text: $password,
                        isSecure: true
                    )

                    // Error
                    if let err = authService.errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 12))
                            Text(err)
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(.red.opacity(0.9))
                        .padding(.horizontal, 4)
                    }

                    // Login button
                    Button {
                        Task { await authService.signIn(email: email.trimmingCharacters(in: .whitespaces),
                                                        password: password) }
                    } label: {
                        ZStack {
                            if authService.isLoading {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Text(AppText.pick("Кіру", "Войти", language: language))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.black)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(authService.isLoading || email.isEmpty || password.isEmpty)
                    .opacity(email.isEmpty || password.isEmpty ? 0.5 : 1)

                }
                .padding(24)
                .background {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay {
                            RoundedRectangle(cornerRadius: 24)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                        }
                }
                .padding(.horizontal, 24)

                // Register link
                Button {
                    showApplication = true
                } label: {
                    HStack(spacing: 6) {
                        Text(AppText.pick("Аккаунтым жоқ —", "Нет аккаунта —", language: language))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(AppText.pick("Өтініш беру", "Подать заявку", language: language))
                            .foregroundStyle(Color.green)
                    }
                    .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.top, 20)

                Spacer()
            }
        }
        .sheet(isPresented: $showApplication) {
            ApplicationView()
                .environmentObject(authService)
        }
        .preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

// MARK: - Auth Field

struct JAuthField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 20)

            Group {
                if isSecure && !isVisible {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(.white)

            if isSecure {
                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }
}
