import SwiftUI
import FirebaseAuth

// MARK: - Admin Dashboard

struct AdminDashboardView: View {

    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var onboarding = OnboardingStore.shared

    @State private var selectedTab: DashTab = .applications
    @State private var applications: [Application] = []
    @State private var users: [AppUser] = []
    @State private var isLoading = false
    @State private var errorMsg: String?
    @State private var showCreateUser = false
    @State private var rejectTarget: Application?
    @State private var rejectReason = ""
    @State private var searchText = ""
    @State private var deleteTarget: AppUser?

    enum DashTab: String, CaseIterable {
        case applications, users

        var localizedLabel: String {
            let kk = OnboardingStore.shared.profile.language == .kazakh
            switch self {
            case .applications: return kk ? "Өтініштер"       : "Заявки"
            case .users:        return kk ? "Пайдаланушылар"  : "Пользователи"
            }
        }
    }

    private var kk: Bool { onboarding.currentLanguage == .kazakh }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

                VStack(spacing: 0) {

                    // Tab bar
                    HStack(spacing: 0) {
                        ForEach(DashTab.allCases, id: \.self) { tab in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedTab = tab
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Text(tab.localizedLabel)
                                        .font(.system(size: 14, weight: selectedTab == tab ? .bold : .regular))
                                        .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.4))
                                    Rectangle()
                                        .fill(selectedTab == tab ? Color.green : Color.clear)
                                        .frame(height: 2)
                                        .clipShape(Capsule())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color.white.opacity(0.05))

                    // Search bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.white.opacity(0.4))
                            .font(.system(size: 14))
                        TextField(kk ? "Іздеу..." : "Поиск...", text: $searchText)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .tint(.green)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))

                    if isLoading {
                        Spacer()
                        ProgressView().tint(.green)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                if selectedTab == .applications {
                                    applicationsContent
                                } else {
                                    usersContent
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
            .navigationTitle(kk ? "Әкімші панелі" : "Панель администратора")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(kk ? "Жабу" : "Закрыть") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showCreateUser = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                                .foregroundStyle(.green)
                        }
                        Button {
                            Task { await loadData() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadData() }
        .sheet(isPresented: $showCreateUser) {
            CreateUserView {
                Task { await loadData() }
            }
            .environmentObject(authService)
        }
        .alert(kk ? "Жою" : "Удалить", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button(kk ? "Жою" : "Удалить", role: .destructive) {
                if let user = deleteTarget {
                    Task {
                        try? await FirestoreService.shared.deleteUserProfile(uid: user.id)
                        deleteTarget = nil
                        await loadData()
                    }
                }
            }
            Button(kk ? "Болдырмау" : "Отмена", role: .cancel) { deleteTarget = nil }
        } message: {
            if let user = deleteTarget {
                Text(kk ? "\(user.name) жойылсын ба?" : "Удалить \(user.name)?")
            }
        }
        .sheet(item: $rejectTarget) { app in
            RejectReasonSheet(app: app, reason: $rejectReason) {
                Task {
                    guard let id = app.id else { return }
                    try? await FirestoreService.shared.updateApplicationStatus(
                        appId: id, status: .rejected, reason: rejectReason)
                    rejectTarget = nil
                    await loadData()
                }
            }
        }
    }

    // MARK: - Applications Tab

    @ViewBuilder
    private var applicationsContent: some View {
        if filteredApplications.isEmpty {
            EmptyStateView(icon: "tray.fill", text: kk ? "Өтініштер жоқ" : "Заявок нет")
        } else {
            ForEach(filteredApplications) { app in
                ApplicationCard(app: app,
                    onApprove: {
                        Task {
                            guard let id = app.id else { return }
                            try? await FirestoreService.shared.updateApplicationStatus(appId: id, status: .approved)
                            await loadData()
                        }
                    },
                    onReject: {
                        rejectReason = ""
                        rejectTarget = app
                    }
                )
            }
        }
    }

    // MARK: - Users Tab

    private var filteredUsers: [AppUser] {
        guard !searchText.isEmpty else { return users }
        let q = searchText.lowercased()
        return users.filter { $0.name.lowercased().contains(q) || $0.email.lowercased().contains(q) }
    }

    private var filteredApplications: [Application] {
        guard !searchText.isEmpty else { return applications }
        let q = searchText.lowercased()
        return applications.filter { $0.name.lowercased().contains(q) || $0.phone.contains(q) }
    }

    @ViewBuilder
    private var usersContent: some View {
        let isDev = authService.currentUser?.role == .developer
        if filteredUsers.isEmpty {
            EmptyStateView(icon: "person.3.fill", text: kk ? "Пайдаланушылар жоқ" : "Пользователей нет")
        } else {
            ForEach(filteredUsers) { user in
                UserCard(user: user, showDevInfo: isDev,
                    onRoleChange: { newRole in
                        Task {
                            try? await FirestoreService.shared.updateUserRole(uid: user.id, role: newRole)
                            await loadData()
                        }
                    },
                    onDelete: {
                        deleteTarget = user
                    }
                )
            }
        }
    }

    // MARK: - Load

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        applications = (try? await FirestoreService.shared.fetchApplications()) ?? []
        users = (try? await FirestoreService.shared.fetchAllUsers()) ?? []
    }
}

// MARK: - Application Card

private struct ApplicationCard: View {
    let app: Application
    let onApprove: () -> Void
    let onReject: () -> Void
    private var kk: Bool { OnboardingStore.shared.profile.language == .kazakh }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(app.phone)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                StatusBadge(status: app.status)
            }

            Text(app.purpose)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(3)

            if app.status == .pending {
                HStack(spacing: 10) {
                    Button { onReject() } label: {
                        Label(kk ? "Қабылдамау" : "Отклонить", systemImage: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Button { onApprove() } label: {
                        Label(kk ? "Бекіту" : "Одобрить", systemImage: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            // Rejected reason chip
            if app.status == .rejected, let reason = app.rejectionReason, !reason.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble").font(.system(size: 11)).foregroundStyle(.red.opacity(0.7))
                    Text(reason).font(.system(size: 12)).foregroundStyle(.red.opacity(0.8)).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.red.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                }
        }
    }
}

// MARK: - User Card

private struct UserCard: View {
    let user: AppUser
    var showDevInfo: Bool = false
    let onRoleChange: (UserRole) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(roleColor(user.role).opacity(0.2))
                    .frame(width: 44, height: 44)
                Text(String(user.name.prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(roleColor(user.role))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(user.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(user.email)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                if showDevInfo {
                    Text("UID: \(user.id)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.purple.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Delete
            Button { onDelete() } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(.red.opacity(0.6))
                    .padding(6)
            }
            .buttonStyle(.plain)

            // Role menu
            Menu {
                ForEach([UserRole.member, .child, .parent, .mentor, .admin, .developer], id: \.self) { role in
                    Button(role.label) { onRoleChange(role) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(user.role.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(roleColor(user.role))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(roleColor(user.role).opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(roleColor(user.role).opacity(0.15))
                .clipShape(Capsule())
            }
        }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                }
        }
    }

    private func roleColor(_ role: UserRole) -> Color {
        switch role {
        case .developer: return Color(red: 0.6, green: 0.2, blue: 1.0)
        case .admin:     return .yellow
        case .mentor:    return Color(red: 0.4, green: 0.6, blue: 1.0)
        case .parent:    return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .child:     return Color(red: 0.2, green: 0.85, blue: 0.75)
        case .member:    return .green
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: ApplicationStatus

    var body: some View {
        Text(status.label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - Reject Reason Sheet

private struct RejectReasonSheet: View {
    let app: Application
    @Binding var reason: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    private var kk: Bool { OnboardingStore.shared.profile.language == .kazakh }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.red)
                        Text(kk ? "\(app.name) өтінішін қабылдамау" : "Отклонить заявку \(app.name)")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Reason field
                    VStack(alignment: .leading, spacing: 8) {
                        Text(kk ? "Себебін жазыңыз (міндетті)" : "Укажите причину (обязательно)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                            .textCase(.uppercase)
                            .tracking(0.8)

                        ZStack(alignment: .topLeading) {
                            if reason.isEmpty {
                                Text(kk
                                     ? "Мысалы: Берілген ақпарат жеткіліксіз..."
                                     : "Например: Предоставленные данные недостаточны...")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.25))
                                    .padding(.horizontal, 14)
                                    .padding(.top, 13)
                            }
                            TextEditor(text: $reason)
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 100)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                        }
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.07))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(.red.opacity(0.3), lineWidth: 1)
                                }
                        }
                    }

                    Spacer()

                    // Confirm button
                    Button {
                        onConfirm()
                        dismiss()
                    } label: {
                        Text(kk ? "Қабылдамау" : "Отклонить")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(reason.trimmingCharacters(in: .whitespaces).isEmpty
                                        ? Color.red.opacity(0.3) : Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(kk ? "Болдырмау" : "Отмена") { dismiss() }
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.2))
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Developer Dashboard

struct DeveloperDashboardView: View {

    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var users: [AppUser] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var deleteTarget: AppUser?
    @State private var resetTarget: AppUser?
    @State private var showPasswordSheet = false
    @State private var passwordMsg: String?
    @State private var expandedUID: String?

    private var kk: Bool { OnboardingStore.shared.profile.language == .kazakh }

    private var filtered: [AppUser] {
        guard !searchText.isEmpty else { return users }
        let q = searchText.lowercased()
        return users.filter {
            $0.name.lowercased().contains(q) ||
            $0.email.lowercased().contains(q) ||
            $0.id.lowercased().contains(q) ||
            $0.role.rawValue.contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header badge
                    HStack(spacing: 8) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Developer Console")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(Color(red: 0.6, green: 0.2, blue: 1.0))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(red: 0.6, green: 0.2, blue: 1.0).opacity(0.12))
                    .clipShape(Capsule())
                    .overlay { Capsule().strokeBorder(Color(red: 0.6, green: 0.2, blue: 1.0).opacity(0.3), lineWidth: 1) }
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    // Stats row
                    if !users.isEmpty { statsRow.padding(.horizontal, 16).padding(.bottom, 12) }

                    // Search
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.4)).font(.system(size: 13))
                        TextField(kk ? "UID, аты, email, рөл..." : "UID, имя, email, роль...", text: $searchText)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.white)
                            .tint(Color(red: 0.6, green: 0.2, blue: 1.0))
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.3))
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))

                    if isLoading {
                        Spacer(); ProgressView().tint(Color(red: 0.6, green: 0.2, blue: 1.0)); Spacer()
                    } else if filtered.isEmpty {
                        Spacer()
                        VStack(spacing: 10) {
                            Image(systemName: "person.3.fill").font(.system(size: 36)).foregroundStyle(.white.opacity(0.15))
                            Text(kk ? "Пайдаланушылар жоқ" : "Пользователей нет").font(.system(size: 14)).foregroundStyle(.white.opacity(0.3))
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(filtered) { user in
                                    DevUserRow(
                                        user: user,
                                        isExpanded: expandedUID == user.id,
                                        onToggle: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                expandedUID = expandedUID == user.id ? nil : user.id
                                            }
                                        },
                                        onRoleChange: { newRole in
                                            Task { try? await FirestoreService.shared.updateUserRole(uid: user.id, role: newRole); await loadData() }
                                        },
                                        onDelete: { deleteTarget = user },
                                        onResetPassword: { resetTarget = user; showPasswordSheet = true }
                                    )
                                }
                            }.padding(16)
                        }
                    }
                }
            }
            .navigationTitle(kk ? "Әзірлеуші панелі" : "Панель разработчика")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(kk ? "Жабу" : "Закрыть") { dismiss() }.foregroundStyle(.white.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await loadData() } } label: {
                        Image(systemName: "arrow.clockwise").foregroundStyle(Color(red: 0.6, green: 0.2, blue: 1.0))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadData() }
        .alert(kk ? "Жою" : "Удалить", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button(kk ? "Жою" : "Удалить", role: .destructive) {
                if let user = deleteTarget {
                    Task { try? await FirestoreService.shared.deleteUserProfile(uid: user.id); deleteTarget = nil; await loadData() }
                }
            }
            Button(kk ? "Болдырмау" : "Отмена", role: .cancel) { deleteTarget = nil }
        } message: {
            if let user = deleteTarget { Text("\(user.name)\nUID: \(user.id)") }
        }
        .sheet(isPresented: $showPasswordSheet) {
            DevPasswordResetSheet(user: resetTarget, message: $passwordMsg)
        }
    }

    @ViewBuilder
    private var statsRow: some View {
        let groups: [(UserRole, Color)] = [
            (.member, .green), (.child, Color(red:0.2,green:0.85,blue:0.75)), (.parent, Color(red:1,green:0.6,blue:0.2)),
            (.mentor, Color(red:0.4,green:0.6,blue:1)), (.admin, .yellow),
            (.developer, Color(red:0.6,green:0.2,blue:1))
        ]
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                DevStatChip(label: kk ? "Барлығы" : "Всего", value: "\(users.count)", color: .white)
                ForEach(groups, id: \.0) { role, color in
                    let cnt = users.filter { $0.role == role }.count
                    if cnt > 0 { DevStatChip(label: role.label, value: "\(cnt)", color: color) }
                }
            }
        }
    }

    private func loadData() async {
        isLoading = true; defer { isLoading = false }
        users = (try? await FirestoreService.shared.fetchAllUsers()) ?? []
    }
}

private struct DevStatChip: View {
    let label: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(color)
            Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(color.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.2), lineWidth: 1) }
    }
}

private struct DevUserRow: View {
    let user: AppUser
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRoleChange: (UserRole) -> Void
    let onDelete: () -> Void
    let onResetPassword: () -> Void

    private var roleColor: Color {
        switch user.role {
        case .developer: return Color(red: 0.6, green: 0.2, blue: 1.0)
        case .admin:     return .yellow
        case .mentor:    return Color(red: 0.4, green: 0.6, blue: 1.0)
        case .parent:    return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .child:     return Color(red: 0.2, green: 0.85, blue: 0.75)
        case .member:    return .green
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(roleColor.opacity(0.15)).frame(width: 40, height: 40)
                        Text(String(user.name.prefix(1)).uppercased()).font(.system(size: 16, weight: .bold)).foregroundStyle(roleColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        Text(user.email).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    Text(user.role.rawValue)
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(roleColor)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(roleColor.opacity(0.12)).clipShape(Capsule())
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    Divider().background(Color.white.opacity(0.08))
                    VStack(spacing: 10) {
                        DevInfoRow(label: "UID", value: user.id, mono: true, copyable: true)
                        DevInfoRow(label: "Email", value: user.email, mono: false, copyable: true)
                        DevInfoRow(label: "role", value: user.role.rawValue, mono: true, copyable: false)
                        if let m = user.mentorId { DevInfoRow(label: "mentorId", value: m, mono: true, copyable: true) }
                        if let d = user.isDirectApproved { DevInfoRow(label: "isDirectApproved", value: "\(d)", mono: true, copyable: false) }
                    }.padding(12)
                    Divider().background(Color.white.opacity(0.08))
                    HStack(spacing: 0) {
                        Menu {
                            ForEach([UserRole.member, .child, .parent, .mentor, .admin, .developer], id: \.self) { role in
                                Button(role.rawValue) { onRoleChange(role) }
                            }
                        } label: {
                            Label("role", systemImage: "person.badge.key.fill")
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        Divider().frame(height: 30).background(Color.white.opacity(0.08))
                        Button(action: onResetPassword) {
                            Label("reset pwd", systemImage: "key.fill")
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.orange.opacity(0.8))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }.buttonStyle(.plain)
                        Divider().frame(height: 30).background(Color.white.opacity(0.08))
                        Button(action: onDelete) {
                            Label("delete", systemImage: "trash.fill")
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.red.opacity(0.8))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }.buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isExpanded ? 0.07 : 0.04))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(isExpanded ? roleColor.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
    }
}

private struct DevInfoRow: View {
    let label: String; let value: String; let mono: Bool; let copyable: Bool
    @State private var copied = false
    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(red: 0.6, green: 0.2, blue: 1.0).opacity(0.8))
                .frame(width: 100, alignment: .leading)
            Text(value).font(.system(size: 10, weight: .medium, design: mono ? .monospaced : .default))
                .foregroundStyle(.white.opacity(0.75)).lineLimit(1).truncationMode(.middle)
            Spacer()
            if copyable {
                Button {
                    UIPasteboard.general.string = value
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { copied = false } }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10)).foregroundStyle(copied ? .green : .white.opacity(0.3))
                }.buttonStyle(.plain)
            }
        }
    }
}

private struct DevPasswordResetSheet: View {
    let user: AppUser?
    @Binding var message: String?
    @Environment(\.dismiss) private var dismiss
    private var kk: Bool { OnboardingStore.shared.profile.language == .kazakh }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()
                VStack(spacing: 20) {
                    if let user = user {
                        VStack(spacing: 6) {
                            Image(systemName: "key.fill").font(.system(size: 32)).foregroundStyle(.orange)
                            Text(user.name).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            Text(user.email).font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                        }.padding(.top, 20)

                        Text(kk
                            ? "Firebase пайдаланушының email-ге құпия сөзді қалпына келтіру сілтемесі жіберіледі."
                            : "Firebase отправит ссылку для сброса пароля на email пользователя.")
                            .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(16).background(Color.orange.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.2), lineWidth: 1) }
                            .padding(.horizontal, 20)

                        if let msg = message {
                            Text(msg).font(.system(size: 12))
                                .foregroundStyle(msg.contains("жіберілді") || msg.contains("отправлена") ? .green : .red)
                                .multilineTextAlignment(.center).padding(.horizontal, 20)
                        }

                        Button {
                            Task {
                                do {
                                    try await FirebaseAuth.Auth.auth().sendPasswordReset(withEmail: user.email)
                                    message = kk ? "\(user.email) email-ге сілтеме жіберілді" : "Ссылка отправлена на \(user.email)"
                                } catch { message = error.localizedDescription }
                            }
                        } label: {
                            Text(kk ? "Сілтеме жіберу" : "Отправить ссылку")
                                .font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(Color.orange).clipShape(RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).padding(.horizontal, 20)
                    }
                    Spacer()
                }
            }
            .navigationTitle(kk ? "Құпия сөзді қалпына келтіру" : "Сброс пароля")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(kk ? "Жабу" : "Закрыть") { message = nil; dismiss() }.foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
