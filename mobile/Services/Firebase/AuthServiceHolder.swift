import Foundation
import FirebaseAuth
import FirebaseCore

/// AssistantCoordinator сияқты MainActor емес жерлерден
/// қазіргі Firebase UID-ді оқу үшін жеңіл жол.
final class AuthServiceHolder {
    static let shared = AuthServiceHolder()
    private init() {}

    var currentUID: String? {
        guard FirebaseApp.app() != nil else { return nil }
        return Auth.auth().currentUser?.uid
    }
    var currentRole: UserRole?
}
