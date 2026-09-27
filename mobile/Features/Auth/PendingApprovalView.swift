import SwiftUI

// MARK: - Pending Approval View
// Өтініш жіберілді, бірақ әлі мақұлданбаса көрсетіледі

struct PendingApprovalView: View {

    let status: ApplicationStatus?
    var rejectionReason: String? = nil
    @EnvironmentObject private var authService: AuthService
    @ObservedObject private var onboarding = OnboardingStore.shared
    @State private var isChecking = false

    private var kk: Bool { onboarding.currentLanguage == .kazakh }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.08)
                .ignoresSafeArea(.all)

            // Subtle glow
            Circle()
                .fill(statusColor.opacity(0.08))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(y: -80)

            VStack(spacing: 24) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 100, height: 100)
                    Image(systemName: statusIcon)
                        .font(.system(size: 44))
                        .foregroundStyle(statusColor)
                }

                // Title
                Text(statusTitle)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                // Description
                Text(statusDescription)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Rejection reason card
                if status == .rejected, let reason = rejectionReason ?? authService.rejectionReason, !reason.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "text.bubble.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.red.opacity(0.8))
                            Text(AppText.pick("Себеп:", "Причина:", language: onboarding.currentLanguage))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        Text(reason)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.08))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(.red.opacity(0.25), lineWidth: 1)
                            }
                    }
                    .padding(.horizontal, 32)
                }

                // Status badge
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background {
                    Capsule()
                        .fill(statusColor.opacity(0.12))
                        .overlay {
                            Capsule().strokeBorder(statusColor.opacity(0.3), lineWidth: 1)
                        }
                }

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    // Refresh
                    Button {
                        checkAgain()
                    } label: {
                        HStack(spacing: 8) {
                            if isChecking {
                                ProgressView().tint(.black)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                Text(AppText.pick("Қайта тексеру", "Проверить снова", language: onboarding.currentLanguage))
                            }
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(isChecking)

                    // Logout
                    Button {
                        authService.signOut()
                    } label: {
                        Text(AppText.pick("Шығу", "Выйти", language: onboarding.currentLanguage))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Check again

    private func checkAgain() {
        isChecking = true
        Task {
            guard let uid = authService.currentUser?.id else {
                isChecking = false
                return
            }
            let (newStatus, reason) = await FirestoreService.shared.applicationStatus(userId: uid)
            await MainActor.run {
                authService.applicationStatus = newStatus
                authService.rejectionReason = reason
                isChecking = false
            }
        }
    }

    // MARK: - Status-based UI

    private var statusColor: Color {
        switch status {
        case .pending, .none: return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }

    private var statusIcon: String {
        switch status {
        case .pending, .none: return "clock.fill"
        case .approved: return "checkmark.circle.fill"
        case .rejected: return "xmark.circle.fill"
        }
    }

    private var statusTitle: String {
        switch status {
        case .pending, .none: return AppText.pick("Өтінішіңіз қаралуда", "Заявка на рассмотрении", language: onboarding.currentLanguage)
        case .approved:       return AppText.pick("Мақұлданды!", "Одобрено!", language: onboarding.currentLanguage)
        case .rejected:       return AppText.pick("Өтініш қабылданбады", "Заявка отклонена", language: onboarding.currentLanguage)
        }
    }

    private var statusDescription: String {
        switch status {
        case .pending, .none:
            return kk
                ? "Ментор немесе әкімші өтінішіңізді тексеруде.\nБұл біраз уақыт алуы мүмкін."
                : "Ментор или администратор проверяет вашу заявку.\nЭто может занять некоторое время."
        case .approved:
            return kk
                ? "Қосымшаға кіруге рұқсат берілді!\nҚайта тексеру батырмасын басыңыз."
                : "Доступ к приложению разрешён!\nНажмите кнопку проверки."
        case .rejected:
            return kk
                ? "Кешіріңіз, өтінішіңіз қабылданбады.\nӘкімшіге хабарласыңыз."
                : "Извините, ваша заявка отклонена.\nСвяжитесь с администратором."
        }
    }

    private var statusLabel: String {
        switch status {
        case .pending, .none: return kk ? "Күтуде"       : "Ожидание"
        case .approved:       return kk ? "Мақұлданды"   : "Одобрено"
        case .rejected:       return kk ? "Қабылданбады" : "Отклонено"
        }
    }
}
