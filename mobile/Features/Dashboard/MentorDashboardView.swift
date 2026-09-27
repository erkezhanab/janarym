import SwiftUI

// MARK: - Mentor Dashboard

struct MentorDashboardView: View {

    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var applications: [Application] = []
    @State private var isLoading = false

    private var kk: Bool { OnboardingStore.shared.profile.language == .kazakh }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

                if isLoading {
                    ProgressView().tint(.green)
                } else {
                    applicationsTab
                }
            }
            .navigationTitle(kk ? "Ментор панелі" : "Панель ментора")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(kk ? "Жабу" : "Закрыть") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await loadData() } } label: {
                        Image(systemName: "arrow.clockwise").foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadData() }
    }

    // MARK: - Tabs

    private var applicationsTab: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if applications.isEmpty {
                    EmptyStateView(icon: "person.2.fill", text: kk ? "Өтініштер жоқ" : "Заявок нет")
                } else {
                    ForEach(applications) { app in
                        MentorApplicationCard(app: app) { newStatus in
                            Task {
                                guard let id = app.id else { return }
                                try? await FirestoreService.shared.updateApplicationStatus(
                                    appId: id, status: newStatus)
                                await loadData()
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        applications = (try? await FirestoreService.shared.fetchApplications()) ?? []
    }
}

// MARK: - Mentor Application Card

private struct MentorApplicationCard: View {
    let app: Application
    let onDecision: (ApplicationStatus) -> Void
    private var kk: Bool { OnboardingStore.shared.profile.language == .kazakh }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                // Avatar initials
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Text(String(app.name.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(red: 0.4, green: 0.6, blue: 1.0))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(app.phone)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()
                StatusBadge(status: app.status)
            }

            Text(app.purpose)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(4)

            // Date
            HStack {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                Text(app.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
            }

            if app.status == .pending {
                HStack(spacing: 10) {
                    Button {
                        onDecision(.rejected)
                    } label: {
                        Text(kk ? "Қабылдамау" : "Отклонить")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(.red.opacity(0.3), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDecision(.approved)
                    } label: {
                        Text(kk ? "Бекіту" : "Одобрить")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(.green.opacity(0.3), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
        }
    }
}
