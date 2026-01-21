import SwiftUI

struct ManageUsersView: View {
    @State private var users: [User] = []
    @State private var isLoading = true
    @State private var searchQuery = ""
    @State private var selectedUser: User?
    @State private var showConfirmation = false
    @State private var confirmationAction: UserAction?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let firestoreService = FirestoreService.shared
    private let invitationService = InvitationService.shared

    enum UserAction {
        case grantInvite(User)
        case revokeInvite(User)
    }

    var filteredUsers: [User] {
        if searchQuery.isEmpty {
            return users
        }
        return users.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchQuery) ||
            $0.email.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Search
            searchBar
                .padding(Theme.Spacing.md)

            // User list
            if isLoading {
                loadingView
            } else if users.isEmpty {
                emptyView
            } else {
                userList
            }
        }
        .frame(width: 600, height: 700)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            loadUsers()
        }
        .alert("Confirm Action", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {
                confirmationAction = nil
            }
            Button("Confirm") {
                Task {
                    await performAction()
                }
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundColor(Theme.Colors.accent)

            Spacer()

            Text("Manage Users")
                .font(Theme.Typography.headline)

            Spacer()

            Button {
                loadUsers()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(Theme.Colors.accent)
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search users...", text: $searchQuery)
                .textFieldStyle(.plain)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Color(.textBackgroundColor))
        .cornerRadius(Theme.CornerRadius.medium)
    }

    // MARK: - User List

    private var userList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredUsers) { user in
                    userRow(user)
                    Divider()
                        .padding(.leading, 72)
                }
            }
        }
    }

    private func userRow(_ user: User) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            // Avatar
            ZStack {
                Circle()
                    .fill(user.isAdmin ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Theme.messengerGradient))
                    .frame(width: 44, height: 44)

                Text(user.initials)
                    .font(Theme.Typography.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                // Online indicator
                if user.isOnline {
                    Circle()
                        .fill(Theme.Colors.online)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color(.windowBackgroundColor), lineWidth: 2)
                        )
                        .offset(x: 16, y: 16)
                }
            }

            // User info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(user.displayName)
                        .font(Theme.Typography.body)
                        .fontWeight(.medium)

                    if user.isAdmin {
                        Text("Admin")
                            .font(Theme.Typography.footnote)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }

                    if user.canInvite && !user.isAdmin {
                        Text("Can Invite")
                            .font(Theme.Typography.footnote)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.accent)
                            .clipShape(Capsule())
                    }
                }

                Text(user.email)
                    .font(Theme.Typography.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: Theme.Spacing.sm) {
                    Text("Joined \(user.createdAt.timeAgoDisplay())")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(.secondary)

                    if let lastSeen = user.lastSeen, !user.isOnline {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("Last seen \(lastSeen.timeAgoDisplay())")
                            .font(Theme.Typography.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Actions
            if !user.isAdmin {
                Menu {
                    if user.canInvite {
                        Button {
                            confirmationAction = .revokeInvite(user)
                            showConfirmation = true
                        } label: {
                            Label("Revoke Invite Permission", systemImage: "xmark.circle")
                        }
                    } else {
                        Button {
                            confirmationAction = .grantInvite(user)
                            showConfirmation = true
                        } label: {
                            Label("Grant Invite Permission", systemImage: "checkmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.Colors.accent)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            ProgressView()
            Text("Loading users...")
                .font(Theme.Typography.callout)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            Image(systemName: "person.3")
                .font(.system(size: 50))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No users found")
                .font(Theme.Typography.headline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Actions

    private func loadUsers() {
        isLoading = true
        Task {
            do {
                let fetchedUsers = try await firestoreService.getAllUsers()
                await MainActor.run {
                    self.users = fetchedUsers.sorted { $0.createdAt > $1.createdAt }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load users: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    private func performAction() async {
        guard let action = confirmationAction else { return }

        do {
            switch action {
            case .grantInvite(let user):
                if let userId = user.id {
                    try await invitationService.grantInvitePermission(to: userId)
                }
            case .revokeInvite(let user):
                if let userId = user.id {
                    try await invitationService.revokeInvitePermission(from: userId)
                }
            }
            loadUsers()
        } catch {
            errorMessage = "Action failed: \(error.localizedDescription)"
        }

        confirmationAction = nil
    }

    private var confirmationMessage: String {
        guard let action = confirmationAction else { return "" }

        switch action {
        case .grantInvite(let user):
            return "Grant invite permission to \(user.displayName)? They will be able to create invitation codes."
        case .revokeInvite(let user):
            return "Revoke invite permission from \(user.displayName)? They will no longer be able to create invitation codes."
        }
    }
}

#Preview {
    ManageUsersView()
}
