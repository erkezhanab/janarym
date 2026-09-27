import SwiftUI
import FirebaseAuth

// MARK: - Create User View
// Admin тікелей пайдаланушы жасайды (Admin/Mentor/Member)

struct CreateUserView: View {

    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var onboarding = OnboardingStore.shared

    var onCreated: (() -> Void)?

    @State private var name     = ""
    @State private var email    = ""
    @State private var password = ""
    @State private var parentEmail = ""
    @State private var selectedRole: UserRole = .member
    @State private var isLoading = false
    @State private var errorMsg: String?
    @State private var isSuccess = false

    private var kk: Bool { onboarding.currentLanguage == .kazakh }
    private var language: UserProfile.Language { onboarding.currentLanguage }
    private var isChildRole: Bool { selectedRole == .child }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedParentEmail: String { parentEmail.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var displayRoleName: String {
        selectedRole.label
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

                if isSuccess {
                    successView
                } else {
                    formView
                }
            }
            .navigationTitle(AppText.pick("Пайдаланушы жасау", "Создать пользователя", language: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppText.pick("Жабу", "Закрыть", language: language)) { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Form

    @ViewBuilder
    private var formView: some View {
        ScrollView {
            VStack(spacing: 16) {

                // Header
                VStack(spacing: 8) {
                    Image(systemName: "person.badge.plus.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)
                    Text(AppText.pick("Жаңа пайдаланушы", "Новый пользователь", language: language))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 8)

                // Fields
                VStack(spacing: 12) {
                    JAuthField(icon: "person.fill", placeholder: AppText.pick("Аты-жөні", "Имя и фамилия", language: language), text: $name)
                    JAuthField(icon: "envelope.fill", placeholder: "Email", text: $email, keyboardType: .emailAddress)
                    JAuthField(icon: "lock.fill", placeholder: AppText.pick("Құпия сөз (6+ символ)", "Пароль (6+ символов)", language: language), text: $password, isSecure: true)

                    // Role picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppText.pick("РӨЛІ", "РОЛЬ", language: language))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                            .tracking(1)

                        let roles: [UserRole] = [.member, .child, .parent, .mentor, .admin, .developer]
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(roles, id: \.self) { role in
                                RoleCard(role: role, isSelected: selectedRole == role, kk: kk) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedRole = role
                                    }
                                }
                            }
                        }
                    }

                    if isChildRole {
                        VStack(alignment: .leading, spacing: 8) {
                            JAuthField(
                                icon: "figure.and.child.holdinghands",
                                placeholder: AppText.pick("Ата-ананың Email-ы", "Email родителя", language: language),
                                text: $parentEmail,
                                keyboardType: .emailAddress
                            )

                            Text(
                                AppText.pick(
                                    "Алдымен ата-ананы жасаңыз, содан кейін осы жерге оның email-ын енгізіңіз.",
                                    "Сначала создайте родителя, затем укажите здесь его email.",
                                    language: language
                                )
                            )
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
                .padding(20)
                .background {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                        }
                }

                // Error
                if let err = errorMsg {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text(err)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.9))
                }

                // Create button
                Button {
                    createUser()
                } label: {
                    ZStack {
                        if isLoading {
                            ProgressView().tint(.black)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                Text(AppText.pick("Жасау", "Создать", language: language))
                                    .fontWeight(.bold)
                            }
                            .foregroundStyle(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(isFormValid ? Color.green : Color.green.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(!isFormValid || isLoading)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Success

    @ViewBuilder
    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
            }

            Text(AppText.pick("Пайдаланушы жасалды!", "Пользователь создан!", language: language))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            Text("\(trimmedName) — \(displayRoleName)")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))

            Button {
                onCreated?()
                dismiss()
            } label: {
                Text(AppText.pick("Жарайды", "Готово", language: language))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        !trimmedName.isEmpty &&
        trimmedEmail.contains("@") &&
        password.count >= 6 &&
        (!isChildRole || trimmedParentEmail.contains("@"))
    }

    // MARK: - Create

    private func createUser() {
        errorMsg = nil
        isLoading = true

        Task {
            do {
                let parent: AppUser?
                if isChildRole {
                    guard let resolvedParent = try await FirestoreService.shared.findUser(byEmail: trimmedParentEmail) else {
                        throw createValidationError(
                            AppText.pick(
                                "Мұндай email-пен ата-ана табылмады.",
                                "Родитель с таким email не найден.",
                                language: language
                            )
                        )
                    }
                    guard resolvedParent.role == .parent else {
                        throw createValidationError(
                            AppText.pick(
                                "Көрсетілген email ата-ана аккаунтына тиесілі болуы керек.",
                                "Указанный email должен принадлежать аккаунту родителя.",
                                language: language
                            )
                        )
                    }
                    parent = resolvedParent
                } else {
                    parent = nil
                }

                _ = try await authService.createUserWithoutSwitchingSession(
                    email: trimmedEmail,
                    password: password
                ) { userID in
                    let newUser = AppUser(
                        id: userID,
                        email: trimmedEmail,
                        name: trimmedName,
                        role: selectedRole,
                        mentorId: selectedRole == .member ? authService.currentUser?.id : nil,
                        parentUid: parent?.id,
                        children: [],
                        isLinked: parent != nil
                    )

                    if let parent {
                        try await FirestoreService.shared.createDirectChild(newUser, parentUID: parent.id)
                    } else {
                        try await FirestoreService.shared.createDirectUser(newUser)
                    }
                }

                await MainActor.run {
                    isSuccess = true
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMsg = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func createValidationError(_ message: String) -> NSError {
        NSError(
            domain: "CreateUserView",
            code: 400,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

// MARK: - Role Card

private struct RoleCard: View {
    let role: UserRole
    let isSelected: Bool
    let kk: Bool
    let onTap: () -> Void

    private var color: Color {
        switch role {
        case .developer: return Color(red: 0.6, green: 0.2, blue: 1.0)
        case .admin:     return .yellow
        case .mentor:    return Color(red: 0.4, green: 0.6, blue: 1.0)
        case .parent:    return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .child:     return Color(red: 0.2, green: 0.85, blue: 0.75)
        case .member:    return .green
        }
    }

    private var icon: String {
        switch role {
        case .developer: return "terminal.fill"
        case .admin:     return "crown.fill"
        case .mentor:    return "person.2.fill"
        case .parent:    return "figure.and.child.holdinghands"
        case .child:     return "figure.child"
        case .member:    return "person.fill"
        }
    }

    private var localizedName: String {
        return role.label
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isSelected ? color : color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? .black : color)
                }

                Text(localizedName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.75))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(color)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? color.opacity(0.18) : .white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? color.opacity(0.6) : .white.opacity(0.08), lineWidth: 1)
                    }
            }
            .scaleEffect(isSelected ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}
