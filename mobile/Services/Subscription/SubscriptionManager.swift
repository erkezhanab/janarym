import StoreKit
import Foundation

// MARK: - Subscription Tier
// Free: минимум токен, тек базалық функциялар
// Premium (5000₸): орташа мүмкіндіктер, экономды
// VIP (15000₸): толық мүмкіндіктер, барлығы ашық

enum SubscriptionTier: String, Comparable {
    case free
    case premium
    case vip

    static func < (lhs: SubscriptionTier, rhs: SubscriptionTier) -> Bool {
        let order: [SubscriptionTier] = [.free, .premium, .vip]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }

    // MARK: - Tier-based limits

    /// Күнделікті сұрақ лимиті
    var dailyRequestLimit: Int {
        switch self {
        case .free: return 5
        case .premium: return 50
        case .vip: return .max  // шексіз
        }
    }

    /// Камера суретін жіберу мүмкіндігі — тегін нұсқа да камера қолдана алады
    var canSendImage: Bool { true }

    /// Сурет өлшемі (maxEdge)
    var imageMaxEdge: Int {
        switch self {
        case .free: return 384     // тегін де камера — бірақ орта сапа
        case .premium: return 384  // бірдей
        case .vip: return 512      // жоғары сапа
        }
    }

    /// Барлық тариф барлық режимді қолдана алады
    var allowedModes: [String] {
        return ["general", "reading", "shopping", "navigation", "antiscam"]
    }

    func canUseMode(_ mode: String) -> Bool { true }

    /// Кастомизация (дауыс, жылдамдық, т.б.) — тек Premium+
    var canCustomize: Bool { self >= .premium }
}

// MARK: - SubscriptionManager

@MainActor
final class SubscriptionManager: ObservableObject {

    static let shared = SubscriptionManager()

    @Published private(set) var tier: SubscriptionTier = .free
    @Published private(set) var premiumProduct: Product?
    @Published private(set) var vipProduct: Product?
    @Published private(set) var isLoading: Bool = false

    // Кері үйлесімділік — ескі код үшін
    var isPremium: Bool { tier >= .premium }
    var isVIP: Bool { tier == .vip }

    // DEBUG: нақты телефонда тестілеу үшін (App Store-ға шығарда өшіру)
    #if DEBUG
    func debugSetTier(_ newTier: SubscriptionTier) {
        tier = newTier
        print("🧪 DEBUG: tier → \(newTier)")
    }
    #endif

    // Тегін пайдаланушы үшін күнделікті есептегіш
    private let usageKey = "janarym.daily.usage"
    private let usageDateKey = "janarym.daily.usage.date"

    private var updateListenerTask: Task<Void, Never>?

    private func print(_ items: Any...) {}

    private init() {
        updateListenerTask = listenForTransactions()
        Task { await loadAndCheck() }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Public

    /// Сұрақ жіберуге болады ма?
    var canMakeRequest: Bool {
        tier == .vip || todayUsageCount < tier.dailyRequestLimit
    }

    /// Бүгінгі тегін сұрақ қалдығы
    var requestsRemaining: Int {
        if tier == .vip { return .max }
        return max(0, tier.dailyRequestLimit - todayUsageCount)
    }

    /// Сұрақ жасалды деп белгіле
    func recordRequest() {
        guard tier != .vip else { return }
        var count = todayUsageCount
        count += 1
        UserDefaults.standard.set(count, forKey: usageKey)
        UserDefaults.standard.set(todayString, forKey: usageDateKey)
    }

    // MARK: - Purchase

    func purchasePremium() async {
        guard let premiumProduct else {
            print("❌ premiumProduct nil — StoreKit конфигурациясы жүктелмеді")
            return
        }
        await purchase(product: premiumProduct)
    }

    func purchaseVIP() async {
        guard let vipProduct else {
            print("❌ vipProduct nil — StoreKit конфигурациясы жүктелмеді")
            return
        }
        await purchase(product: vipProduct)
    }

    private func purchase(product: Product) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateTier()
                await transaction.finish()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            print("Purchase error: \(error)")
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await updateTier()
        } catch {
            print("Restore error: \(error)")
        }
    }

    // MARK: - Private

    private func loadAndCheck() async {
        let productIDs = [AppConfig.premiumProductID, AppConfig.vipProductID]
        print("🛒 StoreKit: өнімдер жүктелуде... IDs: \(productIDs)")
        do {
            let products = try await Product.products(for: productIDs)
            print("🛒 StoreKit: \(products.count) өнім табылды")
            for p in products {
                print("  → \(p.id): \(p.displayName) — \(p.displayPrice)")
                if p.id == AppConfig.premiumProductID { premiumProduct = p }
                if p.id == AppConfig.vipProductID { vipProduct = p }
            }
            if products.isEmpty {
                print("⚠️ StoreKit: өнімдер жоқ! Scheme-де StoreKit config байланысты ма?")
            }
        } catch {
            print("❌ StoreKit load error: \(error)")
        }
        await updateTier()
    }

    private func updateTier() async {
        var foundTier: SubscriptionTier = .free

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.revocationDate == nil {
                if transaction.productID == AppConfig.vipProductID {
                    foundTier = .vip
                    break  // VIP — ең жоғары, тоқтаймыз
                } else if transaction.productID == AppConfig.premiumProductID {
                    foundTier = .premium
                }
            }
        }

        tier = foundTier
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await self.updateTier()
                    await transaction.finish()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreError.failedVerification
        case .verified(let value): return value
        }
    }

    // MARK: - Daily usage

    private var todayUsageCount: Int {
        let saved = UserDefaults.standard.string(forKey: usageDateKey) ?? ""
        if saved != todayString {
            UserDefaults.standard.set(0, forKey: usageKey)
            return 0
        }
        return UserDefaults.standard.integer(forKey: usageKey)
    }

    private var todayString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}

enum StoreError: Error {
    case failedVerification
}
