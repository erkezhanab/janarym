import UIKit

/// Haptic feedback patterns for Janarym.
/// All methods are safe to call from any thread.
final class HapticService {

    static let shared = HapticService()
    private init() {}

    // MARK: - Patterns

    /// Single medium impact — wake / acknowledge
    func single() {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare()
        DispatchQueue.main.async { g.impactOccurred() }
    }

    /// Two light impacts 80ms apart — voice received / processing
    func double() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        DispatchQueue.main.async {
            g.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { g.impactOccurred() }
        }
    }

    /// System success notification — response ready
    func success() {
        DispatchQueue.main.async {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// System error notification
    func error() {
        DispatchQueue.main.async {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    /// System warning notification
    func warning() {
        DispatchQueue.main.async {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    /// Single warning pulse — SOS confirmation without a jarring rumble
    func sos() {
        DispatchQueue.main.async {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }
}
