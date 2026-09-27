import SwiftUI

// MARK: - Onboarding Container

struct OnboardingView: View {
    @ObservedObject var store: OnboardingStore
    @State private var step  = 0
    @State private var draft = UserProfile()

    private var kk: Bool { draft.language == .kazakh }
    private let totalSteps = 10

    var body: some View {
        ZStack {
            // Dark gradient — барлық экрандарда
            LinearGradient(
                colors: [Color(hex: "060d1a"), Color(hex: "0a1628")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(.all)

            if step == 0 {
                // SCREEN 1 — Welcome + Language Selection (арнайы дизайн)
                LanguageWelcomeScreen(draft: $draft) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 1 }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                // Steps 1-9 — Standard onboarding flow
                standardOnboardingFlow
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.all)
        .preferredColorScheme(.dark)
    }

    // MARK: - Standard Steps (1-9)

    private var standardOnboardingFlow: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 60)

            progressCard
                .padding(.horizontal, 20)

            Spacer()

            Group {
                switch step {
                case 1: nameStep
                case 2: formalityStep
                case 3: ageStep
                case 4: occupationStep
                case 5: cityStep
                case 6: purposeStep
                case 7: hobbiesStep
                case 8: lengthStep
                case 9: rateStep
                default: EmptyView()
                }
            }
            .id(step)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal:   .move(edge: .leading).combined(with: .opacity)
            ))
            .padding(.horizontal, 20)

            Spacer()

            navRow
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
        }
    }

    // MARK: - Progress card

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(kk ? "Жеке баптау: \(step)/\(totalSteps - 1)"
                         : "Персонализация: \(step)/\(totalSteps - 1)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "1ec952"))
                        .frame(width: geo.size.width * CGFloat(step) / CGFloat(totalSteps - 1), height: 6)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
                }
            }
            .frame(height: 6)

            Text(kk ? "Жауап беріңіз немесе келесіге өтіңіз."
                    : "Ответьте или перейдите к следующему.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "1ec952").opacity(0.4), lineWidth: 1)
                )
        )
    }

    // MARK: - Steps

    private var nameStep: some View {
        OnboardingTextStep(
            question: kk ? "Есіміңіз кім?" : "Как вас зовут?",
            placeholder: kk ? "Есімді жазыңыз (міндетті емес)" : "Введите имя (необязательно)",
            text: $draft.name
        )
    }

    private var formalityStep: some View {
        OnboardingChoiceStep(
            question: kk ? "Сізге қалай жүгінейін?" : "Как к вам обращаться?",
            options: UserProfile.Formality.allCases.map { $0.display(draft.language) },
            selected: UserProfile.Formality.allCases.firstIndex(of: draft.formality) ?? 0
        ) { draft.formality = UserProfile.Formality.allCases[$0] }
    }

    private var ageStep: some View {
        OnboardingChoiceStep(
            question: kk ? "Жас аралығыңыз?" : "Ваш возраст?",
            options: UserProfile.AgeRange.allCases.map { $0.display(draft.language) },
            selected: UserProfile.AgeRange.allCases.firstIndex(of: draft.ageRange) ?? 0
        ) { draft.ageRange = UserProfile.AgeRange.allCases[$0] }
    }

    private var occupationStep: some View {
        OnboardingChoiceStep(
            question: kk ? "Негізгі саланыз?" : "Ваша основная сфера?",
            options: UserProfile.Occupation.allCases.map { $0.display(draft.language) },
            selected: UserProfile.Occupation.allCases.firstIndex(of: draft.occupation) ?? 0
        ) { draft.occupation = UserProfile.Occupation.allCases[$0] }
    }

    private var cityStep: some View {
        OnboardingTextStep(
            question: kk ? "Қай қалада тұрасыз?" : "В каком городе живёте?",
            placeholder: kk ? "Алматы, Астана... (міндетті емес)" : "Алматы, Астана... (необязательно)",
            text: $draft.city
        )
    }

    private var purposeStep: some View {
        OnboardingChoiceStep(
            question: kk ? "Жанарымды не үшін?" : "Для чего Жанарым?",
            options: UserProfile.Purpose.allCases.map { $0.display(draft.language) },
            selected: UserProfile.Purpose.allCases.firstIndex(of: draft.purpose) ?? 0
        ) { draft.purpose = UserProfile.Purpose.allCases[$0] }
    }

    private var hobbiesStep: some View {
        OnboardingTextStep(
            question: kk ? "Хоббиіңіз бар ма?" : "Ваши хобби?",
            placeholder: kk ? "Кітап, музыка, спорт... (міндетті емес)" : "Книги, музыка, спорт... (необязательно)",
            text: $draft.hobbies
        )
    }

    private var lengthStep: some View {
        OnboardingChoiceStep(
            question: kk ? "Жауап ұзындығы?" : "Длина ответов?",
            options: UserProfile.ResponseLength.allCases.map { $0.display(draft.language) },
            selected: UserProfile.ResponseLength.allCases.firstIndex(of: draft.responseLength) ?? 0
        ) { draft.responseLength = UserProfile.ResponseLength.allCases[$0] }
    }

    private var rateStep: some View {
        OnboardingChoiceStep(
            question: kk ? "Дауыс жылдамдығы?" : "Скорость речи?",
            options: UserProfile.SpeechRate.allCases.map { $0.display(draft.language) },
            selected: UserProfile.SpeechRate.allCases.firstIndex(of: draft.speechRate) ?? 0
        ) { draft.speechRate = UserProfile.SpeechRate.allCases[$0] }
    }

    // MARK: - Navigation

    private var navRow: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    step = max(0, step - 1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            // Skip for optional text steps
            if step == 1 || step == 5 || step == 7 {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { step += 1 }
                } label: {
                    Text(kk ? "Өткізу" : "Пропустить")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            // Next / Finish
            Button {
                if step < totalSteps - 1 {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { step += 1 }
                } else {
                    store.complete(with: draft)
                }
            } label: {
                Text(step < totalSteps - 1
                     ? (kk ? "Жалғастыру" : "Продолжить")
                     : (kk ? "Бастау!" : "Начать!"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(minWidth: 130)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 24)
                    .background(
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color(hex: "1ec952"), Color(hex: "17a644")],
                                startPoint: .leading, endPoint: .trailing
                            ))
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - SCREEN 1: Language Welcome Screen (animated)

struct LanguageWelcomeScreen: View {
    @Binding var draft: UserProfile
    let onContinue: () -> Void

    @State private var logoScale: CGFloat = 1.0
    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var showCards = false
    @State private var showButton = false
    @State private var buttonPressed = false

    private let greenAccent = Color(red: 0.12, green: 0.79, blue: 0.32)

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Eye Logo with glow pulse
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(greenAccent.opacity(0.15))
                    .frame(width: 130, height: 130)
                    .scaleEffect(logoScale)

                // Inner circle
                Circle()
                    .fill(greenAccent.opacity(0.2))
                    .frame(width: 100, height: 100)

                // Eye icon
                Image(systemName: "eye.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(greenAccent)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    logoScale = 1.08
                }
            }

            Spacer().frame(height: 24)

            // Title
            Text("Жанарым")
                .font(.system(size: 42, weight: .black))
                .foregroundStyle(.white)
                .opacity(showTitle ? 1 : 0)
                .offset(y: showTitle ? 0 : 20)

            Spacer().frame(height: 8)

            // Subtitle
            Text(draft.language == .kazakh ? "Дауыстық AI-ассистент" : "Голосовой AI-ассистент")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))
                .opacity(showSubtitle ? 1 : 0)
                .offset(y: showSubtitle ? 0 : 12)

            Spacer().frame(height: 44)

            // Language cards
            VStack(spacing: 12) {
                ForEach(Array(UserProfile.Language.allCases.enumerated()), id: \.element) { idx, lang in
                    LanguageCard(
                        title: lang.displayName,
                        subtitle: lang.languageSubtitle,
                        flag: lang.flagEmoji,
                        isSelected: draft.language == lang
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            draft.language = lang
                        }
                    }
                    .opacity(showCards ? 1 : 0)
                    .offset(y: showCards ? 0 : 30)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.8)
                        .delay(0.4 + Double(idx) * 0.1),
                        value: showCards
                    )
                }
            }
            .padding(.horizontal, 28)

            Spacer().frame(height: 36)

            // Continue button
            Button {
                buttonPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    buttonPressed = false
                    onContinue()
                }
            } label: {
                Text(draft.language == .kazakh ? "Жалғастыру" : "Продолжить")
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
            .padding(.horizontal, 28)
            .opacity(showButton ? 1 : 0)
            .offset(y: showButton ? 0 : 25)

            Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) { showTitle = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.35)) { showSubtitle = true }
            showCards = true // animation handled per-card
            withAnimation(.easeOut(duration: 0.5).delay(0.6)) { showButton = true }
        }
    }
}

// MARK: - Language Card (glassmorphism)

struct LanguageCard: View {
    let title: String
    let subtitle: String
    let flag: String
    let isSelected: Bool
    let onTap: () -> Void

    private let greenAccent = Color(red: 0.12, green: 0.79, blue: 0.32)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Text(flag)
                    .font(.system(size: 28))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(greenAccent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.08))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(
                                isSelected ? greenAccent : .white.opacity(0.15),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
                    .shadow(color: isSelected ? greenAccent.opacity(0.3) : .clear, radius: 12)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Choice step

struct OnboardingChoiceStep: View {
    let question: String
    let options: [String]
    let selected: Int
    let onSelect: (Int) -> Void

    private let greenAccent = Color(red: 0.12, green: 0.79, blue: 0.32)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(question)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, title in
                    Button { onSelect(idx) } label: {
                        HStack {
                            Text(title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(idx == selected ? .white : .white.opacity(0.65))
                            Spacer()
                            if idx == selected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(greenAccent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    idx == selected
                                    ? Color.white.opacity(0.1)
                                    : Color.white.opacity(0.04)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(
                                            idx == selected
                                            ? greenAccent.opacity(0.6)
                                            : Color.white.opacity(0.08),
                                            lineWidth: 1
                                        )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: selected)
                }
            }
        }
    }
}

// MARK: - Text step

struct OnboardingTextStep: View {
    let question: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(question)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)

            TextField("", text: $text,
                      prompt: Text(placeholder).foregroundColor(.white.opacity(0.25)))
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
        }
    }
}
