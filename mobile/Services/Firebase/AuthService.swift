import Foundation
import FirebaseAuth
import FirebaseCore

// MARK: - User Role
enum UserRole: String, Codable, CaseIterable {
    case developer = "developer" // Барлық рұқсат + техникалық деректер
    case admin     = "admin"
    case mentor    = "mentor"
    case parent    = "parent"    // Ата-ана — баласын бақылайды
    case child     = "child"
    case member    = "member"

    var isStandardUser: Bool {
        self == .member || self == .child
    }
}

// MARK: - App User Model
struct AppUser: Codable, Identifiable {
    let id: String          // Firebase UID
    let email: String
    var name: String
    var role: UserRole
    var mentorId: String?   // тек member үшін
    var isDirectApproved: Bool? // Admin тікелей жасаса true — application керек емес
    var parentUid: String?
    var children: [String]
    var isLinked: Bool
    var lastPhotoURL: String?
    var lastPhotoBase64: String?

    init(
        id: String,
        email: String,
        name: String,
        role: UserRole,
        mentorId: String? = nil,
        isDirectApproved: Bool? = nil,
        parentUid: String? = nil,
        children: [String] = [],
        isLinked: Bool = false,
        lastPhotoURL: String? = nil,
        lastPhotoBase64: String? = nil
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.role = role
        self.mentorId = mentorId
        self.isDirectApproved = isDirectApproved
        self.parentUid = parentUid
        self.children = children
        self.isLinked = isLinked
        self.lastPhotoURL = lastPhotoURL
        self.lastPhotoBase64 = lastPhotoBase64
    }
}

// MARK: - Auth Service
@MainActor
final class AuthService: ObservableObject {

    private static let directUserCreationAppName = "JanarymDirectUserCreation"

    @Published var currentUser: AppUser?
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var isRestoringSession: Bool = true
    @Published var errorMessage: String?
    @Published var applicationStatus: ApplicationStatus?  // nil = жоқ, pending/approved/rejected
    @Published var rejectionReason: String?               // Қабылдамаған себеп

    private let auth: Auth?
    private var stateListener: AuthStateDidChangeListenerHandle?

    init() {
        guard FirebaseApp.app() != nil else {
            auth = nil
            isRestoringSession = false
            errorMessage = "Firebase is not configured. Add GoogleService-Info.plist to enable sign in."
            return
        }

        let auth = Auth.auth()
        self.auth = auth
        stateListener = auth.addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor in
                if let firebaseUser {
                    self?.isRestoringSession = true
                    await self?.fetchUserProfile(uid: firebaseUser.uid)
                } else {
                    self?.currentUser = nil
                    self?.isAuthenticated = false
                    self?.isRestoringSession = false
                }
            }
        }
    }

    deinit {
        if let auth, let handle = stateListener {
            auth.removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Sign Up
    func signUp(email: String, password: String, name: String, role: UserRole = .member) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let auth else { throw Self.firebaseNotConfiguredError() }
            let result = try await auth.createUser(withEmail: email, password: password)
            let user = AppUser(
                id: result.user.uid,
                email: email,
                name: name,
                role: role,
                mentorId: nil
            )
            do {
                try await FirestoreService.shared.createUserProfile(user)
            } catch {
                // Avoid leaving an Auth-only account behind when Firestore write fails.
                try? await result.user.delete()
                throw error
            }
            self.currentUser = user
            AuthServiceHolder.shared.currentRole = user.role
            self.isAuthenticated = true
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sign In
    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let auth else { throw Self.firebaseNotConfiguredError() }
            let result = try await auth.signIn(withEmail: email, password: password)
            await fetchUserProfile(uid: result.user.uid)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sign Out
    func signOut() {
        do {
            guard let auth else { throw Self.firebaseNotConfiguredError() }
            try auth.signOut()
            currentUser = nil
            AuthServiceHolder.shared.currentRole = nil
            isAuthenticated = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createUserWithoutSwitchingSession(
        email: String,
        password: String,
        afterCreate: @escaping (String) async throws -> Void
    ) async throws -> String {
        let secondaryAuth = try Self.directUserCreationAuth()
        let result = try await secondaryAuth.createUser(withEmail: email, password: password)

        do {
            try await afterCreate(result.user.uid)
            try? secondaryAuth.signOut()
            return result.user.uid
        } catch {
            try? await result.user.delete()
            try? secondaryAuth.signOut()
            throw error
        }
    }

    // MARK: - Fetch Profile
    private func fetchUserProfile(uid: String) async {
        do {
            let user = try await FirestoreService.shared.fetchUser(uid: uid)
            self.currentUser = user
            AuthServiceHolder.shared.currentRole = user.role

            // Admin/Mentor немесе admin тікелей жасаған — тексеру қажет емес
            if user.role == .developer || user.role == .admin || user.role == .mentor || user.isDirectApproved == true {
                self.applicationStatus = .approved
                self.isAuthenticated = true
            } else {
                // Member/Parent — өтініш мақұлданды ма тексеру
                let (status, reason) = await FirestoreService.shared.applicationStatus(userId: uid)
                self.applicationStatus = status
                self.rejectionReason = reason
                self.isAuthenticated = true
            }
        } catch {
            self.errorMessage = error.localizedDescription
            if let firebaseUser = auth?.currentUser {
                self.currentUser = AppUser(
                    id: firebaseUser.uid,
                    email: firebaseUser.email ?? "",
                    name: firebaseUser.displayName ?? "",
                    role: .member,
                    mentorId: nil
                )
                AuthServiceHolder.shared.currentRole = .member
                let (status, reason) = await FirestoreService.shared.applicationStatus(userId: firebaseUser.uid)
                self.applicationStatus = status
                self.rejectionReason = reason
                self.isAuthenticated = true
            } else {
                self.currentUser = nil
                AuthServiceHolder.shared.currentRole = nil
                self.isAuthenticated = false
            }
        }
        self.isRestoringSession = false
    }

    /// Өтініш мақұлданды ма? Admin/Mentor автоматты approved
    var isApproved: Bool {
        guard let user = currentUser else { return false }
        if user.role == .developer || user.role == .admin || user.role == .mentor { return true }
        if user.role == .parent { return applicationStatus == .approved }
        return applicationStatus == .approved
    }

    private static func directUserCreationAuth() throws -> Auth {
        if let app = FirebaseApp.app(name: directUserCreationAppName) {
            return Auth.auth(app: app)
        }

        guard let defaultApp = FirebaseApp.app() else {
            throw NSError(
                domain: "AuthService",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Firebase is not configured"]
            )
        }

        FirebaseApp.configure(name: directUserCreationAppName, options: defaultApp.options)

        guard let app = FirebaseApp.app(name: directUserCreationAppName) else {
            throw NSError(
                domain: "AuthService",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Secondary Firebase app is unavailable"]
            )
        }

        return Auth.auth(app: app)
    }

    private static func firebaseNotConfiguredError() -> NSError {
        NSError(
            domain: "AuthService",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: "Firebase is not configured"]
        )
    }
}
