import SwiftUI

// MARK: - EmergencyOverlayView

struct EmergencyOverlayView: View {

    let card: MedCard
    let onDismiss: () -> Void

    private var kk: Bool { OnboardingStore.shared.profile.language == .kazakh }

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── Background gradient ──────────────────────────────────
            LinearGradient(
                colors: [Color(hex: "8B0000"), Color(hex: "1a0000")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // ── Scrollable content ───────────────────────────────────
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {

                    // ── 1. Header ────────────────────────────────────
                    VStack(spacing: 10) {
                        Image(systemName: "cross.fill")
                            .font(.system(size: 60, weight: .bold))
                            .foregroundStyle(.white)
                            .accessibilityHidden(true)

                        Text(kk ? "ЖЕДЕЛ МЕДИЦИНАЛЫҚ АҚПАРАТ" : "ЭКСТРЕННЫЕ МЕДДАННЫЕ")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .kerning(2.0)
                            .multilineTextAlignment(.center)

                        if !card.fullName.isEmpty {
                            Text(card.fullName)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 56)
                    .padding(.bottom, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(kk ? "Жедел медициналық ақпарат" : "Экстренные медданные"). \(card.fullName)"
                    )

                    // ── 2. Blood type ────────────────────────────────
                    ECard {
                        ELabel(
                            icon: "drop.fill",
                            text: kk ? "Қан тобы" : "Группа крови"
                        )
                        Text(card.bloodType?.display ?? "—")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.yellow)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(kk ? "Қан тобы" : "Группа крови"): \(card.bloodType?.display ?? "—")"
                    )

                    // ── 3. Allergies ─────────────────────────────────
                    ECard {
                        ELabel(
                            icon: "exclamationmark.triangle.fill",
                            text: kk ? "Аллергия" : "Аллергия",
                            iconColor: Color(hex: "FF6B6B")
                        )
                        if card.allergies.isEmpty {
                            EBodyText(kk ? "Жоқ" : "Нет")
                        } else {
                            ForEach(card.allergies, id: \.self) { item in
                                EBodyText("• \(item)")
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel({
                        let val = card.allergies.isEmpty
                            ? (kk ? "Жоқ" : "Нет")
                            : card.allergies.joined(separator: ", ")
                        return "\(kk ? "Аллергия" : "Аллергия"): \(val)"
                    }())

                    // ── 4. Chronic conditions ────────────────────────
                    ECard {
                        ELabel(icon: "heart.text.square.fill",
                               text: kk ? "Созылмалы аурулар" : "Хронические заболевания")
                        if card.chronicConditions.isEmpty {
                            EBodyText(kk ? "Жоқ" : "Нет")
                        } else {
                            ForEach(card.chronicConditions, id: \.self) { item in
                                EBodyText("• \(item)")
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel({
                        let val = card.chronicConditions.isEmpty
                            ? (kk ? "Жоқ" : "Нет")
                            : card.chronicConditions.joined(separator: ", ")
                        return "\(kk ? "Созылмалы аурулар" : "Хронические заболевания"): \(val)"
                    }())

                    // ── 5. Emergency contact ─────────────────────────
                    ECard {
                        ELabel(icon: "phone.fill",
                               text: kk ? "Жедел байланыс" : "Экстренный контакт",
                               iconColor: Color(hex: "4CAF50"))
                        if !card.emergencyContact.isEmpty {
                            EBodyText(card.emergencyContact)
                        }
                        if !card.emergencyPhone.isEmpty {
                            EPhoneButton(number: card.emergencyPhone)
                        }
                        if card.emergencyContact.isEmpty && card.emergencyPhone.isEmpty {
                            EBodyText(kk ? "Белгіленбеген" : "Не указан")
                        }
                        if !card.emergencyNotes.isEmpty {
                            Text(card.emergencyNotes)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.60))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(kk ? "Жедел байланыс" : "Экстренный контакт")

                    // ── 6. Doctor ────────────────────────────────────
                    ECard {
                        ELabel(icon: "stethoscope",
                               text: kk ? "Дәрігер" : "Врач")
                        if !card.doctorName.isEmpty {
                            EBodyText(card.doctorName)
                        }
                        if !card.doctorPhone.isEmpty {
                            EPhoneButton(number: card.doctorPhone)
                        }
                        if card.doctorName.isEmpty && card.doctorPhone.isEmpty {
                            EBodyText(kk ? "Белгіленбеген" : "Не указан")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(kk ? "Дәрігер" : "Врач")

                    // ── 7. Medications ───────────────────────────────
                    ECard {
                        ELabel(icon: "pills.fill",
                               text: kk ? "Дәрілер" : "Препараты")
                        if card.medications.isEmpty {
                            EBodyText(kk ? "Жоқ" : "Нет")
                        } else {
                            ForEach(card.medications) { med in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("•")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.5))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(med.name)
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(.white)
                                        if !med.dosage.isEmpty {
                                            Text(med.dosage)
                                                .font(.system(size: 13))
                                                .foregroundStyle(.white.opacity(0.65))
                                        }
                                    }
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(med.name)\(med.dosage.isEmpty ? "" : ", \(med.dosage)")")
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(kk ? "Дәрілер" : "Препараты")

                    // bottom padding clears the pinned call + dismiss bar
                    Spacer(minLength: 168)
                }
                .padding(.horizontal, 16)
            }

            // ── Pinned bottom bar: call buttons + dismiss ────────────
            VStack(spacing: 0) {
                // Fade mask so scrolled content blends in
                LinearGradient(
                    colors: [Color.clear, Color(hex: "1a0000")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 32)
                .allowsHitTesting(false)

                // Emergency call buttons — always visible
                HStack(spacing: 12) {
                    ECallButton(
                        label: "🚑  103",
                        hint: kk ? "Жедел жәрдем шақыру" : "Вызов скорой помощи",
                        number: "103",
                        background: Color(hex: "C0392B")
                    )
                    ECallButton(
                        label: "🚔  112",
                        hint: kk ? "Жедел қызмет шақыру" : "Вызов экстренных служб",
                        number: "112",
                        background: Color(hex: "003580")
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(Color(hex: "1a0000"))

                Button(action: onDismiss) {
                    Text(kk ? "Жабу" : "Закрыть")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                }
                .buttonStyle(.plain)
                .background(Color(hex: "1a0000"))
                .accessibilityLabel(kk ? "Жабу" : "Закрыть")
                .accessibilityHint(kk ? "Жедел ақпарат экранын жабады" : "Закрывает экстренный экран")
                .padding(.bottom, 8)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - ECard

private struct ECard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - ELabel

private struct ELabel: View {
    let icon: String
    let text: String
    var iconColor: Color = .white

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(iconColor.opacity(0.85))
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.60))
                .kerning(1.2)
                .textCase(.uppercase)
        }
    }
}

// MARK: - EBodyText

private struct EBodyText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - EPhoneButton (tappable, calls tel://)

private struct EPhoneButton: View {
    let number: String

    var body: some View {
        Button {
            let cleaned = number.filter { $0.isNumber || $0 == "+" }
            guard let url = URL(string: "tel://\(cleaned)") else { return }
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(number)
                    .font(.system(size: 20, weight: .bold))
            }
            .foregroundStyle(Color(hex: "4CAF50"))
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(number)
        .accessibilityHint("Қоңырау шалу")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - ECallButton

private struct ECallButton: View {
    let label: String
    let hint: String
    let number: String
    let background: Color

    var body: some View {
        Button {
            guard let url = URL(string: "tel://\(number)") else { return }
            UIApplication.shared.open(url)
        } label: {
            Text(label)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
    }
}
