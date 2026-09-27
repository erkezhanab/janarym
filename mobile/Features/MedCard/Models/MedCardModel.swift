import Foundation

// MARK: - BloodType

enum BloodType: String, Codable, CaseIterable, Equatable {
    case aPos  = "A+"
    case aNeg  = "A−"
    case bPos  = "B+"
    case bNeg  = "B−"
    case oPos  = "O+"
    case oNeg  = "O−"
    case abPos = "AB+"
    case abNeg = "AB−"

    var display: String { rawValue }
}

// MARK: - MedCard

struct MedCard: Codable, Equatable {
    var fullName:           String    = ""
    var birthDate:          String    = ""          // "DD.MM.YYYY" free-form string
    var bloodType:          BloodType? = nil
    var allergies:          [String]  = []
    var chronicConditions:  [String]  = []
    var emergencyContact:   String    = ""
    var emergencyPhone:     String    = ""
    var emergencyNotes:     String    = ""
    var doctorName:         String    = ""
    var doctorPhone:        String    = ""
    var medications:        [Medication] = []
}
