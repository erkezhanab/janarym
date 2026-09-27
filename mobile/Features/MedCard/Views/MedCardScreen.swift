import SwiftUI

// MARK: - MedCardScreen

struct MedCardScreen: View {

    @StateObject private var vm = MedCardViewModel.shared
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing        = false
    @State private var showEmergency    = false
    @State private var showScan         = false
    @State private var showAddMed       = false
    @State private var editingMed: Medication? = nil
    @State private var allergyInput     = ""
    @State private var conditionInput   = ""

    private var kk: Bool { OnboardingStore.shared.profile.language == .kazakh }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        // ── 1. Emergency banner ──────────────────────
                        EmergencyBanner(card: vm.card, kk: kk) {
                            showEmergency = true
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        // ── 2. Personal info ─────────────────────────
                        MCSection(
                            title: kk ? "Жеке ақпарат"   : "Личные данные",
                            icon: "person.fill"
                        ) {
                            if isEditing {
                                MCEditRow(label: kk ? "Аты-жөні" : "ФИО",
                                          icon: "person",
                                          text: $vm.card.fullName)
                                MCEditRow(label: kk ? "Туған күні (КК.АА.ЖЖЖЖ)" : "Дата рождения (ДД.ММ.ГГГГ)",
                                          icon: "calendar",
                                          text: $vm.card.birthDate,
                                          keyboard: .numbersAndPunctuation)
                                MCBloodTypePicker(label: kk ? "Қан тобы" : "Группа крови",
                                                  selection: $vm.card.bloodType)
                            } else {
                                MCViewRow(label: kk ? "Аты-жөні"    : "ФИО",
                                          value: vm.card.fullName,
                                          icon: "person.fill")
                                MCViewRow(label: kk ? "Туған күні"  : "Дата рождения",
                                          value: vm.card.birthDate,
                                          icon: "calendar")
                                MCViewRow(label: kk ? "Қан тобы"    : "Группа крови",
                                          value: vm.card.bloodType?.display ?? "—",
                                          icon: "drop.fill",
                                          valueColor: .yellow)
                            }
                        }

                        // ── 3. Allergies ─────────────────────────────
                        MCSection(
                            title: kk ? "Аллергия"        : "Аллергии",
                            icon: "exclamationmark.triangle.fill",
                            accent: .orange
                        ) {
                            if vm.card.allergies.isEmpty {
                                MCEmpty(kk ? "Аллергия жоқ" : "Аллергий нет")
                            }
                            ForEach(vm.card.allergies, id: \.self) { item in
                                MCTag(text: item, color: .orange, editable: isEditing) {
                                    vm.card.allergies.removeAll { $0 == item }
                                    vm.saveCard()
                                }
                            }
                            if isEditing {
                                MCTagInput(
                                    placeholder: kk ? "Аллергия қосу…" : "Добавить аллергию…",
                                    text: $allergyInput
                                ) {
                                    vm.addAllergy(allergyInput)
                                    allergyInput = ""
                                }
                            }
                        }

                        // ── 4. Chronic conditions ────────────────────
                        MCSection(
                            title: kk ? "Созылмалы аурулар" : "Хронические заболевания",
                            icon: "heart.text.square.fill",
                            accent: .purple
                        ) {
                            if vm.card.chronicConditions.isEmpty {
                                MCEmpty(kk ? "Тіркелмеген" : "Не указаны")
                            }
                            ForEach(vm.card.chronicConditions, id: \.self) { item in
                                MCTag(text: item, color: .purple, editable: isEditing) {
                                    vm.card.chronicConditions.removeAll { $0 == item }
                                    vm.saveCard()
                                }
                            }
                            if isEditing {
                                MCTagInput(
                                    placeholder: kk ? "Ауру қосу…" : "Добавить заболевание…",
                                    text: $conditionInput
                                ) {
                                    vm.addCondition(conditionInput)
                                    conditionInput = ""
                                }
                            }
                        }

                        // ── 5. Medications ───────────────────────────
                        MCSection(
                            title: kk ? "Дәрілер"  : "Препараты",
                            icon: "pills.fill",
                            accent: .blue,
                            trailingButtons: {
                                AnyView(HStack(spacing: 8) {
                                    MCIconButton(icon: "camera.fill", color: .blue) {
                                        showScan = true
                                    }
                                    .accessibilityLabel(kk ? "Дәрі сканерлеу" : "Сканировать препарат")

                                    MCIconButton(icon: "plus", color: .green) {
                                        showAddMed = true
                                    }
                                    .accessibilityLabel(kk ? "Дәрі қосу" : "Добавить препарат")
                                })
                            }
                        ) {
                            if vm.card.medications.isEmpty {
                                MCEmpty(kk ? "Дәрі тіркелмеген" : "Препараты не добавлены")
                            }
                            ForEach(vm.card.medications) { med in
                                MedRow(med: med, kk: kk) {
                                    editingMed = med
                                } onDelete: {
                                    vm.removeMedication(withID: med.id)
                                }
                            }
                        }

                        // ── 6. Emergency contact ─────────────────────
                        MCSection(
                            title: kk ? "Жедел байланыс" : "Экстренный контакт",
                            icon: "phone.fill",
                            accent: .red
                        ) {
                            if isEditing {
                                MCEditRow(label: kk ? "Аты-жөні" : "ФИО",
                                          icon: "person",
                                          text: $vm.card.emergencyContact)
                                MCEditRow(label: kk ? "Телефон" : "Телефон",
                                          icon: "phone",
                                          text: $vm.card.emergencyPhone,
                                          keyboard: .phonePad)
                                MCEditRow(label: kk ? "Ескертпе" : "Примечание",
                                          icon: "note.text",
                                          text: $vm.card.emergencyNotes,
                                          multiline: true)
                            } else {
                                MCViewRow(label: kk ? "Аты-жөні" : "ФИО",
                                          value: vm.card.emergencyContact, icon: "person.fill")
                                MCViewRow(label: kk ? "Телефон" : "Телефон",
                                          value: vm.card.emergencyPhone,
                                          icon: "phone.fill",
                                          valueColor: Color(red: 0.5, green: 1.0, blue: 0.5))
                                if !vm.card.emergencyNotes.isEmpty {
                                    MCViewRow(label: kk ? "Ескертпе" : "Примечание",
                                              value: vm.card.emergencyNotes, icon: "note.text")
                                }
                            }
                        }

                        // ── 7. Doctor ────────────────────────────────
                        MCSection(
                            title: kk ? "Дәрігер" : "Врач",
                            icon: "stethoscope"
                        ) {
                            if isEditing {
                                MCEditRow(label: kk ? "Аты-жөні" : "ФИО",
                                          icon: "person.badge.plus",
                                          text: $vm.card.doctorName)
                                MCEditRow(label: kk ? "Телефон" : "Телефон",
                                          icon: "phone",
                                          text: $vm.card.doctorPhone,
                                          keyboard: .phonePad)
                            } else {
                                MCViewRow(label: kk ? "Аты-жөні" : "ФИО",
                                          value: vm.card.doctorName, icon: "person.badge.plus.fill")
                                MCViewRow(label: kk ? "Телефон" : "Телефон",
                                          value: vm.card.doctorPhone, icon: "phone.fill")
                            }
                        }

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle(kk ? "Медициналық карта" : "Медкарта")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .accessibilityLabel(kk ? "Жабу" : "Закрыть")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if isEditing { vm.saveCard() }
                        withAnimation(.easeInOut(duration: 0.2)) { isEditing.toggle() }
                    } label: {
                        Text(isEditing
                             ? (kk ? "Сақтау" : "Сохранить")
                             : (kk ? "Өңдеу"  : "Изменить"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isEditing ? Color.green : .white.opacity(0.8))
                    }
                    .accessibilityLabel(isEditing
                                        ? (kk ? "Сақтау" : "Сохранить")
                                        : (kk ? "Өңдеу"  : "Изменить"))
                }
            }
            .toolbarBackground(Color(red: 0.04, green: 0.04, blue: 0.08), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        // ── Emergency fullscreen cover ───────────────────────────
        .fullScreenCover(isPresented: $showEmergency) {
            EmergencyOverlayView(card: vm.card) { showEmergency = false }
        }
        // ── Medication scan ──────────────────────────────────────
        .sheet(isPresented: $showScan) {
            MedicationScanView { scanned in vm.addMedication(scanned) }
        }
        // ── Add medication ───────────────────────────────────────
        .sheet(isPresented: $showAddMed) {
            MedFormView(
                initial: Medication(),
                kk: kk,
                title: kk ? "Дәрі қосу" : "Добавить препарат"
            ) { vm.addMedication($0) }
        }
        // ── Edit medication ──────────────────────────────────────
        .sheet(item: $editingMed) { med in
            MedFormView(
                initial: med,
                kk: kk,
                title: kk ? "Дәріні өңдеу" : "Редактировать препарат"
            ) { vm.updateMedication($0) }
        }
    }
}

// MARK: - EmergencyBanner

private struct EmergencyBanner: View {
    let card: MedCard
    let kk: Bool
    let onActivate: () -> Void

    @State private var pressing = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.65, green: 0.05, blue: 0.05),
                         Color(red: 0.50, green: 0.03, blue: 0.03)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: "cross.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(kk ? "ЖЕДЕЛ КАРТАСЫ" : "МЕДКАРТА — ЭКСТРЕННО")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white.opacity(0.70))
                        .kerning(1.2)
                    if let bt = card.bloodType {
                        Text(bt.display)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(.yellow)
                    } else {
                        Text("—")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    if !card.allergies.isEmpty {
                        Text(card.allergies.prefix(2).joined(separator: " • "))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(kk ? "Ұзақ басу" : "Удержать")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .scaleEffect(pressing ? 0.97 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: pressing)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onChanged { _ in pressing = true }
                .onEnded   { _ in pressing = false; onActivate() }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            var parts = [kk ? "Жедел медициналық карта" : "Экстренная медкарта"]
            if let bt = card.bloodType { parts.append(kk ? "Қан тобы: \(bt.display)" : "Группа крови: \(bt.display)") }
            if !card.allergies.isEmpty { parts.append(kk ? "Аллергия: \(card.allergies.joined(separator: ", "))" : "Аллергия: \(card.allergies.joined(separator: ", "))") }
            return parts.joined(separator: ". ")
        }())
        .accessibilityHint(kk ? "Жедел ақпарат экранын ашу үшін ұзақ басыңыз" : "Удержите для отображения экстренных данных")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - MCSection

private struct MCSection<Content: View>: View {
    let title: String
    let icon: String
    var accent: Color = .green
    var trailingButtons: (() -> AnyView)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .textCase(.uppercase)
                    .kerning(0.8)
                Spacer()
                trailingButtons?()
            }
            .padding(.horizontal, 2)

            VStack(spacing: 8) {
                content()
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

// MARK: - MCViewRow

private struct MCViewRow: View {
    let label: String
    let value: String
    let icon: String
    var valueColor: Color = .white

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.40))
                Text(value.isEmpty ? "—" : value)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(value.isEmpty ? Color.white.opacity(0.20) : valueColor)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value.isEmpty ? "—" : value)")
    }
}

// MARK: - MCEditRow

private struct MCEditRow: View {
    let label: String
    let icon: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var multiline: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 18)
                .padding(.top, multiline ? 2 : 0)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.40))
                if multiline {
                    TextField(label, text: $text, axis: .vertical)
                        .font(.system(size: 15)).foregroundStyle(.white)
                        .lineLimit(2...5)
                } else {
                    TextField(label, text: $text)
                        .font(.system(size: 15)).foregroundStyle(.white)
                        .keyboardType(keyboard)
                        .autocorrectionDisabled()
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - MCBloodTypePicker

private struct MCBloodTypePicker: View {
    let label: String
    @Binding var selection: BloodType?

    private let none = "—"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "drop")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.40))
                Picker(label, selection: Binding(
                    get: { selection?.rawValue ?? none },
                    set: { selection = BloodType(rawValue: $0) }
                )) {
                    Text(none).tag(none)
                    ForEach(BloodType.allCases, id: \.rawValue) { bt in
                        Text(bt.display).tag(bt.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(.green)
                .padding(.leading, -8)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - MCTag

private struct MCTag: View {
    let text: String
    var color: Color
    let editable: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color.opacity(0.55)).frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white)
            Spacer()
            if editable {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.red.opacity(0.65))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Жою")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityAction(named: "Жою", onDelete)
    }
}

// MARK: - MCTagInput

private struct MCTagInput: View {
    let placeholder: String
    @Binding var text: String
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .font(.system(size: 15)).foregroundStyle(.white)
                .submitLabel(.done)
                .onSubmit { if !text.trimmingCharacters(in: .whitespaces).isEmpty { onAdd() } }
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22)).foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Қосу")
        }
        .padding(.top, 4)
    }
}

// MARK: - MCEmpty

private struct MCEmpty: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(.white.opacity(0.28))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 2)
    }
}

// MARK: - MCIconButton

private struct MCIconButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .padding(7)
                .background(color.opacity(0.14))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MedRow

private struct MedRow: View {
    let med: Medication
    let kk: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(med.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                if !med.dosage.isEmpty {
                    Text(med.dosage)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Text(med.scheduleString(kk: kk))
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.4, green: 0.65, blue: 1.0))
                if !med.notes.isEmpty {
                    Text(med.notes)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.40))
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(spacing: 10) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kk ? "Өңдеу" : "Редактировать")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kk ? "Жою" : "Удалить")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(med.name), \(med.dosage), \(med.scheduleString(kk: kk))")
    }
}

// MARK: - MedFormView

struct MedFormView: View {
    @Environment(\.dismiss) private var dismiss
    let kk: Bool
    let title: String
    let onSave: (Medication) -> Void

    @State private var med: Medication

    init(initial: Medication, kk: Bool, title: String, onSave: @escaping (Medication) -> Void) {
        _med  = State(initialValue: initial)
        self.kk     = kk
        self.title  = title
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {

                        MFField(label: kk ? "Атауы *" : "Название *",
                                icon: "pill", text: $med.name)

                        MFField(label: kk ? "Дозасы (мыс. 500 мг)" : "Дозировка (напр. 500 мг)",
                                icon: "scalemass", text: $med.dosage)

                        // Schedule toggles
                        VStack(alignment: .leading, spacing: 10) {
                            Text(kk ? "Қабылдау уақыты" : "Время приёма")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.50))
                                .textCase(.uppercase).kerning(0.8)

                            HStack(spacing: 10) {
                                MFPill(label: kk ? "Таңертең" : "Утро",   isOn: $med.morning)
                                MFPill(label: kk ? "Түскі"    : "День",   isOn: $med.afternoon)
                                MFPill(label: kk ? "Кешкі"    : "Вечер",  isOn: $med.evening)
                                MFPill(label: kk ? "Түнгі"    : "Ночь",   isOn: $med.night)
                            }
                        }

                        MFField(label: kk ? "Ескертпе" : "Примечание",
                                icon: "note.text", text: $med.notes,
                                multiline: true)

                        Spacer(minLength: 20)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(kk ? "Бас тарту" : "Отмена") { dismiss() }
                        .foregroundStyle(.white.opacity(0.55))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(kk ? "Сақтау" : "Сохранить") {
                        onSave(med); dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(med.name.isEmpty ? Color.white.opacity(0.25) : Color.green)
                    .disabled(med.name.isEmpty)
                }
            }
            .toolbarBackground(Color(red: 0.04, green: 0.04, blue: 0.08), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

private struct MFField: View {
    let label: String
    let icon: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var multiline: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                    .accessibilityHidden(true)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Group {
                if multiline {
                    TextField(label, text: $text, axis: .vertical)
                        .lineLimit(2...5)
                } else {
                    TextField(label, text: $text)
                        .keyboardType(keyboard)
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .autocorrectionDisabled()
            .padding(12)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct MFPill: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? .black : .white.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(isOn ? Color.green : Color.white.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "қосулы" : "өшірулі")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
