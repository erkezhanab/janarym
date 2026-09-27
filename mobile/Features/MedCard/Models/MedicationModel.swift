import Foundation

// MARK: - Medication

struct Medication: Codable, Identifiable, Equatable {
    var id:        UUID   = UUID()
    var name:      String = ""
    var dosage:    String = ""
    var morning:   Bool   = false
    var afternoon: Bool   = false
    var evening:   Bool   = false
    var night:     Bool   = false
    var notes:     String = ""

    // MARK: - Schedule helper

    func scheduleString(kk: Bool) -> String {
        var parts: [String] = []
        if morning   { parts.append(kk ? "Таңертең" : "Утро")  }
        if afternoon { parts.append(kk ? "Түскі"    : "День")  }
        if evening   { parts.append(kk ? "Кешкі"    : "Вечер") }
        if night     { parts.append(kk ? "Түнгі"    : "Ночь")  }
        guard !parts.isEmpty else {
            return kk ? "Кесте белгіленбеген" : "Расписание не задано"
        }
        return parts.joined(separator: " • ")
    }
}
