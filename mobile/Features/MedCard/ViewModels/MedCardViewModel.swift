import Foundation
import Combine

// MARK: - MedCardViewModel
// @MainActor singleton — mirrors the ObservableObject pattern used throughout the app.

@MainActor
final class MedCardViewModel: ObservableObject {

    static let shared = MedCardViewModel()

    @Published var card: MedCard = MedCard()

    private let repo = MedCardRepository.shared

    private init() {
        loadCard()
    }

    // MARK: - Persistence

    func loadCard() {
        card = repo.load()
    }

    func saveCard() {
        repo.save(card)
    }

    // MARK: - Medications

    func addMedication(_ med: Medication) {
        card.medications.append(med)
        repo.save(card)
    }

    func removeMedication(withID id: UUID) {
        card.medications.removeAll { $0.id == id }
        repo.save(card)
    }

    func removeMedications(at offsets: IndexSet) {
        card.medications.remove(atOffsets: offsets)
        repo.save(card)
    }

    func updateMedication(_ med: Medication) {
        guard let idx = card.medications.firstIndex(where: { $0.id == med.id }) else { return }
        card.medications[idx] = med
        repo.save(card)
    }

    // MARK: - Allergies

    func addAllergy(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !card.allergies.contains(t) else { return }
        card.allergies.append(t)
        repo.save(card)
    }

    func removeAllergy(at offsets: IndexSet) {
        card.allergies.remove(atOffsets: offsets)
        repo.save(card)
    }

    // MARK: - Chronic conditions

    func addCondition(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !card.chronicConditions.contains(t) else { return }
        card.chronicConditions.append(t)
        repo.save(card)
    }

    func removeCondition(at offsets: IndexSet) {
        card.chronicConditions.remove(atOffsets: offsets)
        repo.save(card)
    }

    // MARK: - SOS med card text (read aloud immediately on SOS trigger)

    /// Returns plain-text summary of critical medical info for TTS during SOS.
    /// "[Name], [age] жас. Қан тобы: [type]. Аллергия: [list]. Дәрігер: [phone]"
    func sosReadoutText() -> String {
        var parts: [String] = []
        let name = card.fullName.isEmpty ? "Пайдаланушы" : card.fullName
        let age  = computeAge()
        parts.append(age > 0 ? "\(name), \(age) жас" : name)
        if let bt = card.bloodType { parts.append("Қан тобы: \(bt.display)") }
        if !card.allergies.isEmpty {
            parts.append("Аллергия: \(card.allergies.joined(separator: ", "))")
        }
        if !card.doctorPhone.isEmpty {
            parts.append("Дәрігер: \(card.doctorPhone)")
        } else if !card.emergencyPhone.isEmpty {
            parts.append("Байланыс: \(card.emergencyPhone)")
        }
        return parts.joined(separator: ". ")
    }

    func spokenSummary(kk: Bool) -> String? {
        var parts: [String] = []

        let name = card.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let age = computeAge()
        if !name.isEmpty {
            parts.append(age > 0
                         ? (kk ? "\(name), \(age) жаста" : "\(name), \(age) лет")
                         : name)
        } else if age > 0 {
            parts.append(kk ? "\(age) жаста" : "\(age) лет")
        }

        if let bt = card.bloodType {
            parts.append(kk ? "Қан тобы: \(bt.display)" : "Группа крови: \(bt.display)")
        }
        if !card.allergies.isEmpty {
            parts.append(kk
                         ? "Аллергия: \(card.allergies.joined(separator: ", "))"
                         : "Аллергия: \(card.allergies.joined(separator: ", "))")
        }
        if !card.chronicConditions.isEmpty {
            parts.append(kk
                         ? "Созылмалы аурулар: \(card.chronicConditions.joined(separator: ", "))"
                         : "Хронические заболевания: \(card.chronicConditions.joined(separator: ", "))")
        }
        if !card.medications.isEmpty {
            let meds = card.medications.prefix(3).map(\.name).joined(separator: ", ")
            parts.append(kk ? "Дәрілер: \(meds)" : "Препараты: \(meds)")
        }
        if !card.emergencyContact.isEmpty || !card.emergencyPhone.isEmpty {
            let contact = [card.emergencyContact, card.emergencyPhone]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            if !contact.isEmpty {
                parts.append(kk ? "Жедел байланыс: \(contact)" : "Экстренный контакт: \(contact)")
            }
        }
        if !card.doctorName.isEmpty || !card.doctorPhone.isEmpty {
            let doctor = [card.doctorName, card.doctorPhone]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            if !doctor.isEmpty {
                parts.append(kk ? "Дәрігер: \(doctor)" : "Врач: \(doctor)")
            }
        }
        if !card.emergencyNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(kk
                         ? "Ескертпе: \(card.emergencyNotes)"
                         : "Примечание: \(card.emergencyNotes)")
        }

        let summary = parts.joined(separator: ". ")
        return summary.isEmpty ? nil : summary
    }

    private func computeAge() -> Int {
        // birthDate stored as "DD.MM.YYYY"
        let parts = card.birthDate.split(separator: ".")
        guard parts.count == 3,
              let day  = Int(parts[0]),
              let mo   = Int(parts[1]),
              let year = Int(parts[2]) else { return 0 }
        var comps = DateComponents()
        comps.day = day; comps.month = mo; comps.year = year
        guard let birth = Calendar.current.date(from: comps) else { return 0 }
        return Calendar.current.dateComponents([.year], from: birth, to: Date()).year ?? 0
    }

    // MARK: - Firestore sync

    func syncToFirestore(childUID: String) {
        Task {
            var data: [String: Any] = [
                "name":            card.fullName,
                "birthDate":       card.birthDate,
                "bloodType":       card.bloodType?.rawValue as Any,
                "allergies":       card.allergies,
                "diagnoses":       card.chronicConditions,
                "insuranceNumber": ""
            ]
            data["emergencyContact"] = [
                "name":  card.emergencyContact,
                "phone": card.emergencyPhone
            ]
            let meds = card.medications.map { m -> [String: Any] in
                ["name":    m.name,
                 "dose":    m.dosage,
                 "schedule": m.scheduleString(kk: true)]
            }
            data["medications"] = meds
            await FirestoreService.shared.saveMedCard(childUID: childUID, data: data)
        }
    }
}
