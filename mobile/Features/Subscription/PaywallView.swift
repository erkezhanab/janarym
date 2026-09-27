import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject private var sub = SubscriptionManager.shared
    @ObservedObject private var onboarding = OnboardingStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: SelectedPlan = .premium

    private var kk: Bool { onboarding.currentLanguage == .kazakh }
    private var language: UserProfile.Language { onboarding.currentLanguage }

    enum SelectedPlan {
        case premium, vip
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // MARK: Header
                    VStack(spacing: 12) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(
                                LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .padding(.top, 48)

                        Text(AppText.pick("Жанарым жазылымдар", "Подписки Жанарым", language: language))
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)

                        Text(AppText.pick("Өзіңізге сай тарифті таңдаңыз", "Выберите подходящий тариф", language: language))
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.bottom, 24)

                    // MARK: Current Tier Badge
                    if sub.tier != .free {
                        HStack(spacing: 6) {
                            Image(systemName: sub.isVIP ? "crown.fill" : "star.fill")
                                .font(.system(size: 12))
                            Text(sub.isVIP
                                 ? AppText.pick("VIP белсенді", "VIP активен", language: language)
                                 : AppText.pick("Premium белсенді", "Premium активен", language: language))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(sub.isVIP ? Color.yellow : Color.green)
                        .clipShape(Capsule())
                        .padding(.bottom, 20)
                    }

                    // MARK: Plan Cards
                    VStack(spacing: 12) {
                        // Premium Card
                        PlanCard(
                            isSelected: selectedPlan == .premium,
                            title: "Premium",
                            price: "5 000 ₸",
                            period: AppText.pick("/ ай", "/ месяц", language: language),
                            color: .green,
                            icon: "star.fill",
                            features: kk ? [
                                "Күніне 50 сұрақ",
                                "Дауыс және жылдамдық баптаулары",
                                "GPT дауысы (OpenAI TTS)",
                                "Барлық режимдер қол жетімді"
                            ] : [
                                "50 запросов в день",
                                "Настройка голоса и скорости",
                                "GPT голос (OpenAI TTS)",
                                "Все режимы доступны"
                            ]
                        ) {
                            selectedPlan = .premium
                        }

                        // VIP Card
                        PlanCard(
                            isSelected: selectedPlan == .vip,
                            title: "VIP",
                            price: "15 000 ₸",
                            period: AppText.pick("/ ай", "/ месяц", language: language),
                            color: .yellow,
                            icon: "crown.fill",
                            badge: AppText.pick("Толық мүмкіндік", "Полный доступ", language: language),
                            features: kk ? [
                                "Шексіз сұрақтар",
                                "Жоғары сапалы AI камера (512px)",
                                "Барлық баптаулар + кастомизация",
                                "GPT дауысы + жылдамдық + стиль",
                                "Барлық режимдер шексіз"
                            ] : [
                                "Безлимитные запросы",
                                "Высококачественная AI-камера (512px)",
                                "Все настройки + кастомизация",
                                "GPT голос + скорость + стиль",
                                "Все режимы без ограничений"
                            ]
                        ) {
                            selectedPlan = .vip
                        }
                    }
                    .padding(.horizontal, 20)

                    // MARK: Free tier info
                    VStack(spacing: 4) {
                        Text(AppText.pick("Тегін тарифте:", "В бесплатном тарифе:", language: language))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                        Text(AppText.pick(
                            "Күніне 5 сұрақ · Барлық режимдер · Камера · Дауыс баптаусыз",
                            "5 запросов в день · Все режимы · Камера · Без настройки голоса",
                            language: language))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.3))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 16)

                    // MARK: CTA Button
                    VStack(spacing: 12) {
                        // Product жүктелмесе — ескерту
                        let productAvailable = selectedPlan == .vip ? sub.vipProduct != nil : sub.premiumProduct != nil
                        if !productAvailable && !sub.isLoading {
                            HStack(spacing: 6) {
                                ProgressView().tint(.orange).scaleEffect(0.8)
                                Text(AppText.pick("Жүктелуде...", "Загрузка...", language: language))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.orange)
                            }
                            .padding(.bottom, 4)
                        }

                        if sub.isLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                        } else {
                            Button {
                                Task {
                                    if selectedPlan == .vip {
                                        await sub.purchaseVIP()
                                    } else {
                                        await sub.purchasePremium()
                                    }
                                }
                            } label: {
                                VStack(spacing: 2) {
                                    Text(selectedPlan == .vip
                                         ? AppText.pick("VIP алу", "Получить VIP", language: language)
                                         : AppText.pick("Premium алу", "Получить Premium", language: language))
                                        .font(.system(size: 17, weight: .bold))
                                    Text(selectedPlan == .vip ? "15 000 ₸" : "5 000 ₸")
                                        .font(.system(size: 13))
                                        + Text(AppText.pick(" / ай", " / месяц", language: language))
                                        .font(.system(size: 13))
                                }
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    LinearGradient(
                                        colors: selectedPlan == .vip
                                            ? [.yellow, .orange]
                                            : [.green, .teal],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }

                            Button {
                                Task { await sub.restorePurchases() }
                            } label: {
                                Text(AppText.pick("Сатып алуды қалпына келтіру", "Восстановить покупку", language: language))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }

                        Text(AppText.pick("Жазылымды кез келген уақытта App Store-да болдырмауға болады.", "Отменить подписку можно в любое время через App Store.", language: language))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 40)

                    // DEBUG батырмалар — тек нақты телефонда тест үшін
                    #if DEBUG
                    if sub.premiumProduct == nil {
                        VStack(spacing: 8) {
                            Text("🧪 DEBUG — StoreKit жоқ (нақты телефон)")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.3))

                            HStack(spacing: 8) {
                                Button("Free") {
                                    sub.debugSetTier(.free)
                                    dismiss()
                                }
                                .buttonStyle(DebugTierStyle(color: .gray))

                                Button("Premium") {
                                    sub.debugSetTier(.premium)
                                    dismiss()
                                }
                                .buttonStyle(DebugTierStyle(color: .green))

                                Button("VIP") {
                                    sub.debugSetTier(.vip)
                                    dismiss()
                                }
                                .buttonStyle(DebugTierStyle(color: .yellow))
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    #endif
                }
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(.top, 16)
                    .padding(.trailing, 16)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Plan Card

private struct PlanCard: View {
    let isSelected: Bool
    let title: String
    let price: String
    let period: String
    let color: Color
    let icon: String
    var badge: String? = nil
    let features: [String]
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color)

                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(color)
                        .clipShape(Capsule())
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(price)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                Text(period)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(color)
                        Text(feature)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(isSelected ? 0.1 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? color : Color.clear, lineWidth: 2)
        )
        .onTapGesture { onTap() }
    }
}


// MARK: - Debug Tier Button Style
#if DEBUG
private struct DebugTierStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(Capsule())
    }
}
#endif
