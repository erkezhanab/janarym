import SwiftUI
import MapKit
import FirebaseFirestore
import UIKit

struct LiveLocationPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
}

// MARK: - ViewModel

@MainActor
final class MentorDashboardVM: ObservableObject {

    @Published var members: [AppUser] = []
    @Published var presences: [String: MemberPresence] = [:]
    @Published var tracks: [String: [LiveLocationPoint]] = [:]
    @Published var sosUserIds: Set<String> = []
    @Published var linkRequests: [ParentLinkRequest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var sosListener: ListenerRegistration?
    private var linkRequestsListener: ListenerRegistration?
    private var presenceListeners: [String: ListenerRegistration] = [:]

    func load(mentorId: String, role: UserRole) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let users: [AppUser]
                switch role {
                case .admin:
                    users = try await FirestoreService.shared.fetchAllUsers()
                case .parent:
                    users = try await FirestoreService.shared.fetchChildren(parentUID: mentorId)
                default:
                    users = try await FirestoreService.shared.fetchMembers(mentorId: mentorId)
                }

                let memberUsers = users.filter(\.role.isStandardUser)
                members = memberUsers

                let memberIds = Set(memberUsers.map(\.id))
                presences = presences.filter { memberIds.contains($0.key) }
                tracks = tracks.filter { memberIds.contains($0.key) }
                sosUserIds = sosUserIds.intersection(memberIds)
                configurePresenceListeners(for: memberUsers)
            } catch {
                members = []
                presences = [:]
                tracks = [:]
                sosUserIds = []
                presenceListeners.values.forEach { $0.remove() }
                presenceListeners = [:]
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }

        sosListener?.remove()
        sosListener = FirestoreService.shared.listenSOS(mentorId: mentorId) { [weak self] ids in
            guard let self else { return }
            let memberIds = Set(self.members.map(\.id))
            self.sosUserIds = Set(ids).intersection(memberIds)
        }

        linkRequestsListener?.remove()
        if role == .parent {
            linkRequestsListener = FirestoreService.shared.listenParentLinkRequests(
                parentUID: mentorId,
                onChange: { [weak self] requests in
                    self?.linkRequests = requests
                },
                onError: { [weak self] error in
                    Task { @MainActor in
                        self?.errorMessage = error.localizedDescription
                    }
                }
            )
        } else {
            linkRequestsListener = nil
            linkRequests = []
        }
    }

    func clearSOS(userId: String) {
        sosUserIds.remove(userId)
        Task { await FirestoreService.shared.clearSOS(userId: userId) }
    }

    func acceptLinkRequest(_ request: ParentLinkRequest) {
        Task {
            do {
                try await FirestoreService.shared.acceptLinkRequest(
                    requestID: request.id,
                    parentUID: request.parentUID,
                    childUID: request.childUID
                )
                await MainActor.run {
                    self.errorMessage = nil
                    self.linkRequests.removeAll { $0.id == request.id }
                }
                load(mentorId: request.parentUID, role: .parent)
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func configurePresenceListeners(for users: [AppUser]) {
        let memberIds = Set(users.map(\.id))

        for userId in presenceListeners.keys where !memberIds.contains(userId) {
            presenceListeners[userId]?.remove()
            presenceListeners.removeValue(forKey: userId)
            presences.removeValue(forKey: userId)
            tracks.removeValue(forKey: userId)
        }

        for user in users where presenceListeners[user.id] == nil {
            let userId = user.id
            let listener = FirestoreService.shared.listenPresence(userId: userId) { [weak self] presence in
                guard let self else { return }
                if let presence {
                    self.presences[userId] = presence
                    self.appendTrackPoint(presence, for: userId)
                } else {
                    self.presences.removeValue(forKey: userId)
                    self.tracks.removeValue(forKey: userId)
                }
            }
            presenceListeners[userId] = listener
        }
    }

    private func appendTrackPoint(_ presence: MemberPresence, for userId: String) {
        guard abs(presence.lat) > 0.000001 || abs(presence.lng) > 0.000001 else { return }

        var points = tracks[userId] ?? []
        let coordinate = presence.coordinate
        let next = LiveLocationPoint(coordinate: coordinate, timestamp: presence.lastSeen)

        if let last = points.last {
            let previous = CLLocation(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
            let current = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let movedEnough = current.distance(from: previous) >= 3
            let isNewer = presence.lastSeen.timeIntervalSince(last.timestamp) >= 2
            guard movedEnough || isNewer else { return }
        }

        points.append(next)
        if points.count > 80 {
            points.removeFirst(points.count - 80)
        }
        tracks[userId] = points
    }

    deinit {
        sosListener?.remove()
        linkRequestsListener?.remove()
        presenceListeners.values.forEach { $0.remove() }
    }
}

// MARK: - Dashboard

struct MentorDashboardView: View {

    let user: AppUser
    @StateObject private var vm: MentorDashboardVM
    @EnvironmentObject private var authService: AuthService
    @ObservedObject private var onboarding = OnboardingStore.shared
    @State private var showLinkingSheet = false

    private var kk: Bool { onboarding.currentLanguage == .kazakh }
    private var isParent: Bool { user.role == .parent }

    init(user: AppUser) {
        self.user = user
        _vm = StateObject(wrappedValue: MentorDashboardVM())
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                if vm.isLoading && vm.members.isEmpty && (!isParent || vm.linkRequests.isEmpty) {
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                } else {
                    dashboardContent
                }
            }
        }
        .onAppear {
            vm.load(mentorId: user.id, role: user.role)
        }
        .sheet(isPresented: $showLinkingSheet) {
            ParentLinkingSheet(parentUID: user.id, kk: kk)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(isParent ? (kk ? "Ата-ана бақылауы" : "Родительский контроль") : (kk ? "Панель" : "Панель"))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                Text(user.role.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Text(user.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()

            if !vm.sosUserIds.isEmpty {
                SOSBadge(count: vm.sosUserIds.count)
            }
            if isParent {
                Button {
                    showLinkingSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(10)
                        .background(Circle().fill(Color.green.opacity(0.22)))
                }
                .padding(.leading, 6)
            }
            Button {
                vm.load(mentorId: user.id, role: user.role)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .padding(.leading, 6)
            Button {
                authService.signOut()
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .padding(.leading, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 16)
    }

    // MARK: - Content

    private var dashboardContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 14) {
                if let errorMessage = vm.errorMessage {
                    errorCard(message: errorMessage)
                }

                if isParent {
                    parentLinkPanel
                }

                if vm.members.isEmpty {
                    emptyState
                } else {
                    ForEach(vm.members) { member in
                        MemberCard(
                            member: member,
                            presence: vm.presences[member.id],
                            routePoints: vm.tracks[member.id] ?? [],
                            sosActive: vm.sosUserIds.contains(member.id),
                            kk: kk,
                            onClearSOS: { vm.clearSOS(userId: member.id) }
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Parent linking

    private var parentLinkPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(kk ? "Баланы қосу" : "Подключить ребёнка")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    Text(
                        kk
                        ? "BLE арқылы жақын маңдағы балаңыздан сұрау қабылдап, бірден бақылауды бастаңыз."
                        : "Примите запрос от ребёнка рядом по BLE и сразу начните видеть его фото, локацию и заряд."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                Button {
                    showLinkingSheet = true
                } label: {
                    Text(kk ? "Қосу" : "Добавить")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.green))
                }
            }

            if vm.linkRequests.isEmpty {
                Text(kk ? "Күтіп тұрған сұраулар жоқ." : "Ожидающих запросов пока нет.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                VStack(spacing: 10) {
                    ForEach(vm.linkRequests) { request in
                        pendingRequestRow(request)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func pendingRequestRow(_ request: ParentLinkRequest) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.green)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(request.childName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                if !request.childEmail.isEmpty {
                    Text(request.childEmail)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Text(requestTimeText(request.createdAt))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer()

            Button {
                vm.acceptLinkRequest(request)
            } label: {
                Text(kk ? "Растау" : "Принять")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.green))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Empty / Error

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: isParent ? "figure.and.child.holdinghands" : "person.2.slash")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.18))

            Text(
                isParent
                ? (kk ? "Әлі бірде-бір бала қосылмады" : "Пока не подключён ни один ребёнок")
                : (kk ? "Тіркелген мүшелер жоқ" : "Нет прикреплённых участников")
            )
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)

            Text(
                isParent
                ? (kk ? "Баланы қосқаннан кейін мұнда соңғы фото, орналасуы, батареясы және SOS көрінеді." : "После привязки здесь появятся последнее фото, местоположение, заряд и SOS ребёнка.")
                : (kk ? "Қол жетімді бақылау деректері бұл жерде көрсетіледі." : "Здесь появятся доступные данные мониторинга.")
            )
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.35))
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func errorCard(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.orange.opacity(0.28), lineWidth: 1)
                )
        )
    }

    private func requestTimeText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: kk ? "kk_KZ" : "ru_RU")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - SOS Badge (header)

private struct SOSBadge: View {
    let count: Int
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .scaleEffect(pulse ? 1.4 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(), value: pulse)
                .onAppear { pulse = true }
            Text("SOS · \(count)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.red.opacity(0.25)))
        .overlay(Capsule().strokeBorder(Color.red.opacity(0.6), lineWidth: 1))
    }
}

// MARK: - Member Card

private struct MemberCard: View {

    let member: AppUser
    let presence: MemberPresence?
    let routePoints: [LiveLocationPoint]
    let sosActive: Bool
    let kk: Bool
    let onClearSOS: () -> Void

    @State private var showDetail = false

    private var lastPhotoURLString: String? {
        presence?.lastPhotoURL ?? member.lastPhotoURL
    }

    private var lastPhotoUIImage: UIImage? {
        let base64 = presence?.lastPhotoBase64 ?? member.lastPhotoBase64
        guard let base64,
              let data = Data(base64Encoded: base64),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    init(member: AppUser, presence: MemberPresence?,
         routePoints: [LiveLocationPoint],
         sosActive: Bool, kk: Bool, onClearSOS: @escaping () -> Void) {
        self.member = member
        self.presence = presence
        self.routePoints = routePoints
        self.sosActive = sosActive
        self.kk = kk
        self.onClearSOS = onClearSOS
    }

    var body: some View {
        VStack(spacing: 0) {
            // SOS alert bar
            if sosActive {
                SOSAlertBar(name: member.name, kk: kk, onClear: onClearSOS)
            }

            HStack(alignment: .top, spacing: 14) {
                // Mini map
                if let p = presence {
                    miniMap(lat: p.lat, lng: p.lng)
                } else {
                    noLocationPlaceholder
                }

                // Info column
                VStack(alignment: .leading, spacing: 8) {
                    Text(member.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let p = presence {
                        infoRow(icon: "clock", text: lastSeenText(p.lastSeen))
                        infoRow(icon: "battery.\(batteryIcon(p.battery))",
                                text: "\(Int(p.battery * 100))%",
                                color: batteryColor(p.battery))
                        infoRow(icon: "figure.walk", text: liveMotionText(p))
                    } else {
                        Text(kk ? "Деректер жоқ" : "Нет данных")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }

                Spacer()

                // Last photo
                if let image = lastPhotoUIImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if let urlStr = lastPhotoURLString,
                          let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        default:
                            photoPlaceholder
                        }
                    }
                } else {
                    photoPlaceholder
                }
            }
            .padding(14)
        }
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(sosActive ? 0.06 : 0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(
                            sosActive ? Color.red.opacity(0.5) : Color.white.opacity(0.08),
                            lineWidth: sosActive ? 1.5 : 1
                        )
                }
        }
        .onTapGesture { showDetail = true }
        .sheet(isPresented: $showDetail) {
            MemberDetailView(member: member, presence: presence,
                             routePoints: routePoints,
                             sosActive: sosActive, kk: kk, onClearSOS: onClearSOS)
        }
    }

    // MARK: Map

    private func miniMap(lat: Double, lng: Double) -> some View {
        ChildLiveMapView(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            routePoints: routePoints,
            followsUser: true,
            compact: true
        )
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .disabled(true)
    }

    private var noLocationPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.06))
            .frame(width: 80, height: 80)
            .overlay {
                Image(systemName: "location.slash")
                    .foregroundStyle(.white.opacity(0.25))
            }
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.06))
            .frame(width: 56, height: 56)
            .overlay {
                Image(systemName: "camera.slash")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.2))
            }
    }

    // MARK: Helpers

    private func infoRow(icon: String, text: String, color: Color = .white) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color.opacity(0.6))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(color.opacity(0.75))
        }
    }

    private func lastSeenText(_ date: Date) -> String {
        let diff = Int(-date.timeIntervalSinceNow)
        if diff < 60 { return kk ? "Қазір онлайн" : "Онлайн" }
        if diff < 3600 { return kk ? "\(diff/60) мин бұрын" : "\(diff/60) мин назад" }
        if diff < 86400 { return kk ? "\(diff/3600) сағ бұрын" : "\(diff/3600) ч назад" }
        return kk ? "\(diff/86400) күн бұрын" : "\(diff/86400) д назад"
    }

    private func liveMotionText(_ p: MemberPresence) -> String {
        guard p.isLive else { return String(format: "%.4f, %.4f", p.lat, p.lng) }
        guard let speed = p.speed, speed > 0.4 else { return kk ? "Live: орнында" : "Live: на месте" }
        return kk
            ? String(format: "Live: %.1f км/сағ", speed * 3.6)
            : String(format: "Live: %.1f км/ч", speed * 3.6)
    }

    private func batteryIcon(_ level: Double) -> String {
        if level > 0.75 { return "100" }
        if level > 0.5  { return "75" }
        if level > 0.25 { return "50" }
        return "25"
    }

    private func batteryColor(_ level: Double) -> Color {
        if level > 0.5 { return .green }
        if level > 0.2 { return .yellow }
        return .red
    }
}

// MARK: - SOS Alert Bar

private struct SOSAlertBar: View {
    let name: String
    let kk: Bool
    let onClear: () -> Void
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sos")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.white)
                .scaleEffect(pulse ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(), value: pulse)
                .onAppear { pulse = true }

            Text(kk ? "\(name) жәрдем сұрауда!" : "\(name) просит помощи!")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            Button {
                onClear()
            } label: {
                Text(kk ? "Жабу" : "Закрыть")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.3))
    }
}

// MARK: - Member Detail (full-screen sheet)

private struct MemberDetailView: View {
    let member: AppUser
    let presence: MemberPresence?
    let routePoints: [LiveLocationPoint]
    let sosActive: Bool
    let kk: Bool
    let onClearSOS: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showFullPhoto = false
    @State private var followsChild = true
    @State private var mapPreviewPressed = false

    private var lastPhotoURLString: String? {
        presence?.lastPhotoURL ?? member.lastPhotoURL
    }

    private var lastPhotoUIImage: UIImage? {
        let base64 = presence?.lastPhotoBase64 ?? member.lastPhotoBase64
        guard let base64,
              let data = Data(base64Encoded: base64),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    init(member: AppUser, presence: MemberPresence?,
         routePoints: [LiveLocationPoint],
         sosActive: Bool, kk: Bool, onClearSOS: @escaping () -> Void) {
        self.member = member
        self.presence = presence
        self.routePoints = routePoints
        self.sosActive = sosActive
        self.kk = kk
        self.onClearSOS = onClearSOS
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                            Text(member.email)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 56)
                    .padding(.bottom, 20)

                    // SOS bar
                    if sosActive {
                        SOSAlertBar(name: member.name, kk: kk, onClear: {
                            onClearSOS()
                            dismiss()
                        })
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }

                    // Stats row
                    if let p = presence {
                        HStack(spacing: 12) {
                            statCard(icon: "clock.fill", color: .blue,
                                     value: lastSeenText(p.lastSeen),
                                     label: kk ? "Соңғы онлайн" : "Был онлайн")
                            statCard(icon: "battery.75", color: batteryColor(p.battery),
                                     value: "\(Int(p.battery * 100))%",
                                     label: kk ? "Батарея" : "Батарея")
                            statCard(icon: "figure.walk", color: .green,
                                     value: speedText(p),
                                     label: kk ? "Қозғалыс" : "Движение")
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }

                    // Large map
                    if let p = presence {
                        ZStack(alignment: .bottomLeading) {
                            ChildLiveMapView(
                                coordinate: p.coordinate,
                                routePoints: routePoints,
                                followsUser: followsChild,
                                compact: false
                            )
                            .allowsHitTesting(false)

                            Button {
                                openMapPreview(p)
                            } label: {
                                Color.clear
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 10) {
                                liveBadge(isLive: p.isLive)

                                HStack(spacing: 10) {
                                    actionChip(
                                        title: followsChild
                                            ? (kk ? "Ілесіп тұр" : "Следит")
                                            : (kk ? "Ілесу" : "Следить"),
                                        systemImage: followsChild ? "location.fill" : "location",
                                        fill: Color.white.opacity(0.14),
                                        foreground: .white
                                    ) {
                                        followsChild.toggle()
                                    }

                                    actionChip(
                                        title: kk ? "Маршрут" : "Маршрут",
                                        systemImage: "arrow.triangle.turn.up.right.diamond.fill",
                                        fill: Color.green,
                                        foreground: .black
                                    ) {
                                        openRouteInMaps(p)
                                    }
                                }
                            }
                            .padding(16)
                            .zIndex(2)

                        }
                        .frame(height: 292)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .scaleEffect(mapPreviewPressed ? 0.99 : 1.0)
                        .animation(.easeOut(duration: 0.18), value: mapPreviewPressed)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                        // Coordinates
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.red.opacity(0.7))
                            Text(String(format: "%.5f, %.5f", p.lat, p.lng))
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                            if let accuracy = p.accuracy {
                                Text("±\(Int(accuracy)) м")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    } else {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 200)
                            .overlay {
                                VStack(spacing: 8) {
                                    Image(systemName: "location.slash.fill")
                                        .font(.system(size: 32))
                                        .foregroundStyle(.white.opacity(0.2))
                                    Text(kk ? "Орналасу белгісіз" : "Местоположение неизвестно")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }

                    // Last photo
                    VStack(alignment: .leading, spacing: 12) {
                        Text(kk ? "Соңғы фото" : "Последнее фото")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 20)

                        if let image = lastPhotoUIImage {
                            imagePreview(
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            )
                        } else if let urlStr = lastPhotoURLString, let url = URL(string: urlStr) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    imagePreview(img)
                                default:
                                    photoPlaceholder
                                }
                            }
                            .padding(.horizontal, 16)
                        } else {
                            photoPlaceholder.padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showFullPhoto) {
            if let image = lastPhotoUIImage {
                ZStack {
                    Color.black.ignoresSafeArea()
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
                .preferredColorScheme(.dark)
            } else if let urlStr = lastPhotoURLString, let url = URL(string: urlStr) {
                ZStack {
                    Color.black.ignoresSafeArea()
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFit()
                        }
                    }
                }
                .preferredColorScheme(.dark)
            }
        }
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.05))
            .frame(maxWidth: .infinity).frame(height: 160)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "camera.slash.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.2))
                    Text(kk ? "Фото жоқ" : "Нет фото")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
    }

    @ViewBuilder
    private func imagePreview<Content: View>(_ content: Content) -> some View {
        VStack(spacing: 12) {
            content
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )

            Button {
                showFullPhoto = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                    Text(kk ? "Фотоны ашу" : "Открыть фото")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private func statCard(icon: String, color: Color, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
        .frame(maxWidth: .infinity)
    }

    private func lastSeenText(_ date: Date) -> String {
        let diff = Int(-date.timeIntervalSinceNow)
        if diff < 60 { return kk ? "Қазір" : "Онлайн" }
        if diff < 3600 { return kk ? "\(diff/60) мин" : "\(diff/60) мин" }
        if diff < 86400 { return kk ? "\(diff/3600) сағ" : "\(diff/3600) ч" }
        return kk ? "\(diff/86400) күн" : "\(diff/86400) д"
    }

    private func batteryColor(_ level: Double) -> Color {
        if level > 0.5 { return .green }
        if level > 0.2 { return .yellow }
        return .red
    }

    private func speedText(_ p: MemberPresence) -> String {
        guard p.isLive else { return kk ? "Офлайн" : "Офлайн" }
        guard let speed = p.speed, speed > 0.4 else { return kk ? "Орнында" : "На месте" }
        return kk
            ? String(format: "%.1f км/сағ", speed * 3.6)
            : String(format: "%.1f км/ч", speed * 3.6)
    }

    private func liveBadge(isLive: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isLive ? Color.green : Color.gray)
                .frame(width: 7, height: 7)
            Text(isLive ? "LIVE" : (kk ? "ОФЛАЙН" : "ОФЛАЙН"))
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill((isLive ? Color.green : Color.gray).opacity(0.16)))
    }

    private func actionChip(
        title: String,
        systemImage: String,
        fill: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
    }

    private func openMapPreview(_ p: MemberPresence) {
        mapPreviewPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            mapPreviewPressed = false
        }
        let placemark = MKPlacemark(coordinate: p.coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = member.name
        item.openInMaps()
    }

    private func openRouteInMaps(_ p: MemberPresence) {
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: p.coordinate))
        destination.name = member.name
        MKMapItem.openMaps(
            with: [MKMapItem.forCurrentLocation(), destination],
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ]
        )
    }
}

// MARK: - Live Map

private struct ChildLiveMapView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let routePoints: [LiveLocationPoint]
    let followsUser: Bool
    let compact: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .includingAll
        mapView.showsCompass = !compact
        mapView.showsScale = !compact
        mapView.isPitchEnabled = !compact
        mapView.isRotateEnabled = !compact
        mapView.isScrollEnabled = !compact
        mapView.isZoomEnabled = !compact
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let annotation = context.coordinator.annotation
        annotation.coordinate = coordinate
        annotation.heading = routePoints.last?.coordinate.bearing(to: coordinate)

        if !mapView.annotations.contains(where: { $0 === annotation }) {
            mapView.addAnnotation(annotation)
        }

        mapView.removeOverlays(mapView.overlays)
        let routeCoordinates = routePoints.map(\.coordinate)
        if routeCoordinates.count > 1 {
            let polyline = MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
            mapView.addOverlay(polyline)
        }

        guard followsUser || compact || !context.coordinator.hasPositionedMap else { return }
        context.coordinator.hasPositionedMap = true
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: compact ? 420 : 950,
            longitudinalMeters: compact ? 420 : 950
        )
        mapView.setRegion(region, animated: !compact)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let annotation = ChildLocationAnnotation()
        var hasPositionedMap = false

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is ChildLocationAnnotation else { return nil }
            let identifier = "child-live-marker"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.markerTintColor = UIColor.systemRed
            view.glyphImage = UIImage(systemName: "figure.walk")
            view.animatesWhenAdded = true
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemGreen.withAlphaComponent(0.85)
            renderer.lineWidth = 5
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
    }
}

private final class ChildLocationAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    var heading: CLLocationDirection?
}

private extension CLLocationCoordinate2D {
    func bearing(to destination: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let lon2 = destination.longitude * .pi / 180
        let y = sin(lon2 - lon1) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lon2 - lon1)
        return fmod((atan2(y, x) * 180 / .pi) + 360, 360)
    }
}
