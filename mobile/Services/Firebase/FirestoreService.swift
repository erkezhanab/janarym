import Foundation
import CoreLocation
import FirebaseFirestore

// MARK: - Member Presence Model
struct MemberPresence: Identifiable {
    var id: String { userId }
    let userId: String
    let lat: Double
    let lng: Double
    let battery: Double   // 0.0 – 1.0
    let lastSeen: Date
    let lastPhotoURL: String?
    let lastPhotoBase64: String?
    let sosActive: Bool
    let sosAt: Date?
    let accuracy: Double?
    let speed: Double?
    let heading: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var isLive: Bool {
        Date().timeIntervalSince(lastSeen) < 90
    }
}

struct ParentLinkRequest: Identifiable, Equatable {
    let id: String
    let childUID: String
    let parentUID: String
    let childName: String
    let childEmail: String
    let createdAt: Date
}

// MARK: - Application Model
struct Application: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var phone: String
    var purpose: String
    var documentURL: String?
    var status: ApplicationStatus
    var rejectionReason: String?   // Қабылдамаған себеп — пайдаланушыға көрсетіледі
    var createdAt: Date
    var userId: String
}

enum ApplicationStatus: String, Codable {
    case pending  = "pending"
    case approved = "approved"
    case rejected = "rejected"
}

// MARK: - Firestore Service
final class FirestoreService {

    static let shared = FirestoreService()
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Users Collection

    func createUserProfile(_ user: AppUser) async throws {
        try await db.collection("users").document(user.id).setData(userData(for: user))
    }

    func fetchUser(uid: String) async throws -> AppUser {
        let snapshot = try await db.collection("users").document(uid).getDocument()
        guard let data = snapshot.data() else {
            throw NSError(domain: "FirestoreService", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        return appUser(id: uid, data: data)
    }

    func deleteUserProfile(uid: String) async throws {
        try await db.collection("users").document(uid).delete()
        // presence де өшіру
        try? await db.collection("presence").document(uid).delete()
    }

    func updateUserRole(uid: String, role: UserRole) async throws {
        try await db.collection("users").document(uid).updateData(["role": role.rawValue])
    }

    func fetchAllUsers() async throws -> [AppUser] {
        let snapshot = try await db.collection("users").getDocuments()
        return snapshot.documents.map { appUser(id: $0.documentID, data: $0.data()) }
    }

    func findUser(byEmail email: String) async throws -> AppUser? {
        let normalizedEmail = normalizeEmail(email)
        guard !normalizedEmail.isEmpty else { return nil }

        let indexedSnapshot = try await db.collection("users")
            .whereField("normalizedEmail", isEqualTo: normalizedEmail)
            .limit(to: 1)
            .getDocuments()

        if let doc = indexedSnapshot.documents.first {
            return appUser(id: doc.documentID, data: doc.data())
        }

        let exactSnapshot = try await db.collection("users")
            .whereField("email", isEqualTo: email.trimmingCharacters(in: .whitespacesAndNewlines))
            .limit(to: 1)
            .getDocuments()

        if let doc = exactSnapshot.documents.first {
            return appUser(id: doc.documentID, data: doc.data())
        }

        // Backward-compatible fallback for legacy user docs created before email normalization.
        let snapshot = try await db.collection("users").getDocuments()
        return snapshot.documents
            .map { appUser(id: $0.documentID, data: $0.data()) }
            .first { normalizeEmail($0.email) == normalizedEmail }
    }

    // MARK: - Applications Collection

    func submitApplication(_ app: Application) async throws {
        let data: [String: Any] = [
            "name":        app.name,
            "phone":       app.phone,
            "purpose":     app.purpose,
            "documentURL": app.documentURL as Any,
            "status":      app.status.rawValue,
            "createdAt":   Timestamp(date: app.createdAt),
            "userId":      app.userId
        ]
        try await db.collection("applications").addDocument(data: data)
    }

    func fetchApplications(forUserId userId: String? = nil) async throws -> [Application] {
        var query: Query = db.collection("applications")
            .order(by: "createdAt", descending: true)

        if let uid = userId {
            query = query.whereField("userId", isEqualTo: uid)
        }

        let snapshot = try await query.getDocuments()
        return try snapshot.documents.compactMap { doc in
            try doc.data(as: Application.self)
        }
    }

    func updateApplicationStatus(appId: String, status: ApplicationStatus, reason: String? = nil) async throws {
        var data: [String: Any] = ["status": status.rawValue]
        if let reason, !reason.isEmpty { data["rejectionReason"] = reason }
        try await db.collection("applications").document(appId).updateData(data)
    }

    /// Пайдаланушының өтініші бекітілді ме?
    func isApplicationApproved(userId: String) async -> Bool {
        do {
            let snapshot = try await db.collection("applications")
                .whereField("userId", isEqualTo: userId)
                .whereField("status", isEqualTo: "approved")
                .limit(to: 1)
                .getDocuments()
            return !snapshot.documents.isEmpty
        } catch {
            return false
        }
    }

    /// Пайдаланушының өтініші статусы + себебі (rejected болса)
    func applicationStatus(userId: String) async -> (ApplicationStatus?, String?) {
        do {
            let snapshot = try await db.collection("applications")
                .whereField("userId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: 1)
                .getDocuments()
            guard let doc = snapshot.documents.first,
                  let raw = doc.data()["status"] as? String else { return (nil, nil) }
            let reason = doc.data()["rejectionReason"] as? String
            return (ApplicationStatus(rawValue: raw), reason)
        } catch {
            return (nil, nil)
        }
    }

    // MARK: - Presence & SOS (ата-ана бақылауы)

    /// Member presence-ін жаңарту: локация + батарея + соңғы фото
    func updatePresence(
        userId: String,
        lat: Double,
        lng: Double,
        battery: Double,
        photoURL: String?,
        photoBase64: String? = nil,
        accuracy: Double? = nil,
        speed: Double? = nil,
        heading: Double? = nil
    ) async {
        var data: [String: Any] = [
            "lat": lat, "lng": lng,
            "battery": battery,
            "lastSeen": Timestamp(date: Date())
        ]
        if let url = photoURL { data["lastPhotoURL"] = url }
        if let photoBase64 { data["lastPhotoBase64"] = photoBase64 }
        if let accuracy { data["accuracy"] = accuracy }
        if let speed, speed >= 0 { data["speed"] = speed }
        if let heading, heading >= 0 { data["heading"] = heading }
        try? await db.collection("presence").document(userId).setData(data, merge: true)
    }

    /// Сохраняет последнее фото. В presence пишет только при наличии валидной геопозиции.
    func updateLastPhoto(
        userId: String,
        photoURL: String?,
        photoBase64: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        battery: Double? = nil
    ) async {
        var presenceData: [String: Any] = [:]
        var userData: [String: Any] = [:]
        if let photoURL {
            presenceData["lastPhotoURL"] = photoURL
            userData["lastPhotoURL"] = photoURL
        }
        if let photoBase64 {
            presenceData["lastPhotoBase64"] = photoBase64
            userData["lastPhotoBase64"] = photoBase64
        }
        if let lat, let lng, let battery {
            let timestamp = Timestamp(date: Date())
            presenceData["lat"] = lat
            presenceData["lng"] = lng
            presenceData["battery"] = battery
            presenceData["lastSeen"] = timestamp
            try? await db.collection("presence").document(userId).setData(presenceData, merge: true)
        }
        if !userData.isEmpty {
            try? await db.collection("users").document(userId).setData(userData, merge: true)
        }
    }

    /// Member-лердің presence деректерін бірден алу
    func fetchPresence(userId: String) async -> MemberPresence? {
        guard let doc = try? await db.collection("presence").document(userId).getDocument(),
              let d = doc.data() else { return nil }
        return MemberPresence(
            userId: userId,
            lat: d["lat"] as? Double ?? 0,
            lng: d["lng"] as? Double ?? 0,
            battery: d["battery"] as? Double ?? 0,
            lastSeen: (d["lastSeen"] as? Timestamp)?.dateValue() ?? Date(),
            lastPhotoURL: d["lastPhotoURL"] as? String,
            lastPhotoBase64: d["lastPhotoBase64"] as? String,
            sosActive: d["sosActive"] as? Bool ?? false,
            sosAt: (d["sosAt"] as? Timestamp)?.dateValue(),
            accuracy: d["accuracy"] as? Double,
            speed: d["speed"] as? Double,
            heading: d["heading"] as? Double
        )
    }

    /// Менторға тіркелген member-лерді алу
    func fetchMembers(mentorId: String) async throws -> [AppUser] {
        let snapshot = try await db.collection("users")
            .whereField("mentorId", isEqualTo: mentorId)
            .getDocuments()
        return snapshot.documents.map { appUser(id: $0.documentID, data: $0.data()) }
    }

    func fetchChildren(parentUID: String) async throws -> [AppUser] {
        let snapshot = try await db.collection("users")
            .whereField("parentUid", isEqualTo: parentUID)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            let user = appUser(id: doc.documentID, data: doc.data())
            let role = user.role
            guard role == .child || role == .member else { return nil }
            return user
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// SOS іске қосу — ата-анаға хабар
    func triggerSOS(userId: String, lat: Double, lng: Double) async {
        let data: [String: Any] = [
            "sosActive": true,
            "sosAt": Timestamp(date: Date()),
            "lat": lat, "lng": lng,
            "lastSeen": Timestamp(date: Date())
        ]
        try? await db.collection("presence").document(userId).setData(data, merge: true)
    }

    /// SOS өшіру
    func clearSOS(userId: String) async {
        try? await db.collection("presence").document(userId).updateData(["sosActive": false])
    }

    /// Real-time presence listener — presence жаңарғанда UI автоматты жаңарады
    func listenPresence(userId: String, onChange: @escaping (MemberPresence?) -> Void) -> ListenerRegistration {
        db.collection("presence").document(userId).addSnapshotListener { snap, _ in
            guard let d = snap?.data() else { onChange(nil); return }
            onChange(MemberPresence(
                userId: userId,
                lat: d["lat"] as? Double ?? 0,
                lng: d["lng"] as? Double ?? 0,
                battery: d["battery"] as? Double ?? 0,
                lastSeen: (d["lastSeen"] as? Timestamp)?.dateValue() ?? Date(),
                lastPhotoURL: d["lastPhotoURL"] as? String,
                lastPhotoBase64: d["lastPhotoBase64"] as? String,
                sosActive: d["sosActive"] as? Bool ?? false,
                sosAt: (d["sosAt"] as? Timestamp)?.dateValue(),
                accuracy: d["accuracy"] as? Double,
                speed: d["speed"] as? Double,
                heading: d["heading"] as? Double
            ))
        }
    }

    /// Real-time SOS listener — ата-ана жағы
    func listenSOS(mentorId: String, onChange: @escaping ([String]) -> Void) -> ListenerRegistration {
        db.collection("presence")
            .whereField("sosActive", isEqualTo: true)
            .addSnapshotListener { snapshot, _ in
                let ids = snapshot?.documents.map(\.documentID) ?? []
                onChange(ids)
            }
    }

    // MARK: - Admin: тікелей пайдаланушы жасау (Firestore-ға ғана)
    func createDirectUser(_ user: AppUser) async throws {
        // isDirectApproved = true — pending экран шықпасын
        let approved = AppUser(
            id: user.id,
            email: user.email,
            name: user.name,
            role: user.role,
            mentorId: user.mentorId,
            isDirectApproved: true,
            parentUid: user.parentUid,
            children: user.children,
            isLinked: user.isLinked,
            lastPhotoURL: user.lastPhotoURL,
            lastPhotoBase64: user.lastPhotoBase64
        )
        try await createUserProfile(approved)
    }

    func createDirectChild(_ user: AppUser, parentUID: String) async throws {
        let child = AppUser(
            id: user.id,
            email: user.email,
            name: user.name,
            role: .child,
            mentorId: nil,
            isDirectApproved: true,
            parentUid: parentUID,
            children: user.children,
            isLinked: true,
            lastPhotoURL: user.lastPhotoURL,
            lastPhotoBase64: user.lastPhotoBase64
        )

        let batch = db.batch()
        let childRef = db.collection("users").document(child.id)
        let parentRef = db.collection("users").document(parentUID)
        batch.setData(userData(for: child), forDocument: childRef)
        batch.updateData(["children": FieldValue.arrayUnion([child.id])], forDocument: parentRef)
        try await batch.commit()
    }

    // MARK: - BLE Linking

    /// Publish short discovery token so child can look up parent UID via BLE local name
    func publishDiscoveryToken(uid: String) async throws {
        let shortCode = String(uid.prefix(8)).uppercased()
        try await db.collection("discoveryTokens").document(shortCode).setData([
            "uid":       uid,
            "createdAt": Timestamp(date: Date())
        ])
    }

    /// Child sends link request after tapping discovered parent device
    func sendBLELinkRequest(childUID: String, parentShortCode: String) async throws {
        let snap = try await db.collection("discoveryTokens")
            .document(parentShortCode)
            .getDocument()

        guard let data = snap.data(),
              let parentUID = data["uid"] as? String else {
            throw NSError(
                domain: "FirestoreService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Parent discovery token not found"]
            )
        }

        let requestID = "\(childUID)_\(parentUID)"
        try await db.collection("linkRequests").document(requestID).setData([
            "childUid":  childUID,
            "parentUid": parentUID,
            "status":    "pending",
            "createdAt": Timestamp(date: Date())
        ])
    }

    /// Parent accepts link request — updates both user docs
    func acceptLinkRequest(requestID: String, parentUID: String, childUID: String) async throws {
        try await db.collection("linkRequests")
            .document(requestID)
            .updateData(["status": "accepted"])
        try await db.collection("users").document(parentUID)
            .updateData(["children": FieldValue.arrayUnion([childUID])])
        try await db.collection("users").document(childUID)
            .setData(["parentUid": parentUID, "isLinked": true], merge: true)
    }

    func listenParentLinkRequests(
        parentUID: String,
        onChange: @escaping ([ParentLinkRequest]) -> Void,
        onError: ((Error) -> Void)? = nil
    ) -> ListenerRegistration {
        db.collection("linkRequests")
            .whereField("parentUid", isEqualTo: parentUID)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snap, error in
                if let error {
                    onError?(error)
                    return
                }
                guard let self else {
                    onChange([])
                    return
                }
                let documents = snap?.documents ?? []
                let db = self.db
                Task {
                    let requests: [ParentLinkRequest] = await withTaskGroup(of: ParentLinkRequest?.self) { group in
                        for doc in documents {
                            group.addTask {
                                let data = doc.data()
                                let childUID = data["childUid"] as? String ?? ""
                                let parentUID = data["parentUid"] as? String ?? ""
                                guard !childUID.isEmpty, !parentUID.isEmpty else { return nil }
                                let childDoc = try? await db.collection("users").document(childUID).getDocument()
                                let childData = childDoc?.data()
                                return ParentLinkRequest(
                                    id: doc.documentID,
                                    childUID: childUID,
                                    parentUID: parentUID,
                                    childName: childData?["name"] as? String ?? childUID,
                                    childEmail: childData?["email"] as? String ?? "",
                                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                                )
                            }
                        }

                        var resolved: [ParentLinkRequest] = []
                        for await result in group {
                            if let result { resolved.append(result) }
                        }
                        return resolved
                    }

                    await MainActor.run {
                        onChange(requests.sorted { $0.createdAt > $1.createdAt })
                    }
                }
            }
    }

    /// Listen for incoming link requests targeting parentUID
    func listenLinkRequests(parentUID: String,
                            onChange: @escaping ([String: Any]) -> Void) -> ListenerRegistration {
        db.collection("linkRequests")
            .whereField("parentUid", isEqualTo: parentUID)
            .whereField("status",    isEqualTo: "pending")
            .addSnapshotListener { snap, _ in
                snap?.documents.forEach { onChange($0.data()) }
            }
    }

    // MARK: - Child location & battery (parent dashboard)

    func updateChildLocation(uid: String, lat: Double, lng: Double) async {
        try? await db.collection("users").document(uid)
            .setData(["location": ["lat": lat, "lng": lng,
                                   "updatedAt": Timestamp(date: Date())]], merge: true)
    }

    func updateBatteryLog(uid: String, pct: Int) async {
        let entry: [String: Any] = ["pct": pct, "timestamp": Timestamp(date: Date())]
        // arrayUnion adds entry; pruning to last 5 handled client-side after read
        try? await db.collection("users").document(uid)
            .setData(["batteryLog": FieldValue.arrayUnion([entry])], merge: true)
    }

    func saveMedCard(childUID: String, data: [String: Any]) async {
        try? await db.collection("users").document(childUID)
            .setData(["medCard": data], merge: true)
    }

    func fetchMedCard(childUID: String) async -> [String: Any]? {
        guard let doc = try? await db.collection("users").document(childUID).getDocument(),
              let d = doc.data() else { return nil }
        return d["medCard"] as? [String: Any]
    }

    func saveSymptom(childUID: String, text: String, audioURL: String?, recordedBy: String) async {
        let entry: [String: Any] = [
            "text":       text,
            "audioUrl":   audioURL as Any,
            "timestamp":  Timestamp(date: Date()),
            "recordedBy": recordedBy
        ]
        try? await db.collection("users").document(childUID)
            .setData(["symptoms": FieldValue.arrayUnion([entry])], merge: true)
    }

    func saveAIPhotoRecord(childUID: String, timestamp: String, url: String, description: String) async {
        let data: [String: Any] = [
            "url":         url,
            "description": description,
            "createdAt":   Timestamp(date: Date())
        ]
        try? await db.collection("ai_photos").document(childUID)
            .setData([timestamp: data], merge: true)
    }

    private func userData(for user: AppUser) -> [String: Any] {
        var data: [String: Any] = [
            "uid": user.id,
            "email": user.email,
            "normalizedEmail": normalizeEmail(user.email),
            "name": user.name,
            "role": user.role.rawValue,
            "mentorId": user.mentorId as Any,
            "children": user.children,
            "isLinked": user.isLinked
        ]
        if let approved = user.isDirectApproved { data["isDirectApproved"] = approved }
        if let parentUid = user.parentUid { data["parentUid"] = parentUid }
        if let lastPhotoURL = user.lastPhotoURL { data["lastPhotoURL"] = lastPhotoURL }
        if let lastPhotoBase64 = user.lastPhotoBase64 { data["lastPhotoBase64"] = lastPhotoBase64 }
        return data
    }

    private func appUser(id: String, data: [String: Any]) -> AppUser {
        AppUser(
            id: id,
            email: data["email"] as? String ?? "",
            name: data["name"] as? String ?? "",
            role: UserRole(rawValue: data["role"] as? String ?? "member") ?? .member,
            mentorId: data["mentorId"] as? String,
            isDirectApproved: data["isDirectApproved"] as? Bool,
            parentUid: data["parentUid"] as? String,
            children: data["children"] as? [String] ?? [],
            isLinked: data["isLinked"] as? Bool ?? false,
            lastPhotoURL: data["lastPhotoURL"] as? String,
            lastPhotoBase64: data["lastPhotoBase64"] as? String
        )
    }

    private func normalizeEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
