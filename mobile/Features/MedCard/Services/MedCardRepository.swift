import Foundation

// MARK: - MedCardRepository
// Mirrors the UserDefaults + JSONCoder singleton pattern used by OnboardingStore.

final class MedCardRepository {

    static let shared = MedCardRepository()

    private let cardKey = "med_card_v1"

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private init() {}

    // MARK: - Load

    func load() -> MedCard {
        guard
            let data = UserDefaults.standard.data(forKey: cardKey),
            let card = try? decoder.decode(MedCard.self, from: data)
        else { return MedCard() }
        return card
    }

    // MARK: - Save

    func save(_ card: MedCard) {
        guard let data = try? encoder.encode(card) else { return }
        UserDefaults.standard.set(data, forKey: cardKey)
    }

    // MARK: - Delete

    func delete() {
        UserDefaults.standard.removeObject(forKey: cardKey)
    }
}
