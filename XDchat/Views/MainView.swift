import SwiftUI

struct MainView: View {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var conversationsViewModel = ConversationsViewModel()
    @ObservedObject private var themeManager = ThemeManager.shared
    @AppStorage(Constants.StorageKeys.profileImageData) private var profileImageData: Data = Data()

    @State private var showSettings = false
    @State private var showInviteUsers = false
    @State private var showManageUsers = false

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                authenticatedView
            } else {
                authView
            }
        }
        .environmentObject(themeManager)
        .preferredColorScheme(themeManager.effectiveColorScheme)
        .onChange(of: authViewModel.isAuthenticated) { _, isAuthenticated in
            if !isAuthenticated {
                // Clear local profile image on logout
                profileImageData = Data()
            }
        }
        .onChange(of: authViewModel.currentUser?.avatarData) { _, avatarData in
            // Sync profile image when user's avatarData changes
            if profileImageData.isEmpty,
               let avatarBase64 = avatarData,
               let data = Data(base64Encoded: avatarBase64) {
                profileImageData = data
            }
        }
        .onAppear {
            if authViewModel.isAuthenticated {
                syncProfileImageFromFirestore()
            }
            // Handle notification taps that arrived before the UI was ready (cold launch)
            if let pendingId = NotificationService.shared.pendingConversationId {
                NotificationService.shared.pendingConversationId = nil
                Task {
                    await conversationsViewModel.fetchAndSelectConversation(id: pendingId)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.openConversation)) { notification in
            guard let conversationId = notification.userInfo?["conversationId"] as? String else { return }
            // Clear pending since we're handling it now
            NotificationService.shared.pendingConversationId = nil

            if let conversation = conversationsViewModel.conversations.first(where: { $0.id == conversationId }) {
                conversationsViewModel.selectConversation(conversation)
            } else {
                Task {
                    await conversationsViewModel.fetchAndSelectConversation(id: conversationId)
                }
            }
        }
    }

    // MARK: - Profile Image Sync

    private func syncProfileImageFromFirestore() {
        // If local storage is empty, try to load from Firestore
        if profileImageData.isEmpty,
           let avatarBase64 = authViewModel.currentUser?.avatarData,
           let data = Data(base64Encoded: avatarBase64) {
            profileImageData = data
        }
    }

    // MARK: - Auth View

    @ViewBuilder
    private var authView: some View {
        if authViewModel.isLoginMode {
            LoginView(viewModel: authViewModel)
        } else {
            RegisterView(viewModel: authViewModel)
        }
    }

    // MARK: - Authenticated View

    private var authenticatedView: some View {
        NavigationSplitView {
            // Sidebar
            sidebar
                .navigationSplitViewColumnWidth(
                    min: Constants.UI.sidebarMinWidth,
                    ideal: Constants.UI.sidebarIdealWidth,
                    max: Constants.UI.sidebarMaxWidth
                )
        } detail: {
            // Chat area
            chatDetailView
        }
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $showInviteUsers) {
            InviteUserView()
        }
        .sheet(isPresented: $showManageUsers) {
            ManageUsersView()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ConversationListView(viewModel: conversationsViewModel)
    }

    // MARK: - Chat Detail

    @ViewBuilder
    private var chatDetailView: some View {
        if let conversation = conversationsViewModel.selectedConversation {
            ChatView(
                conversation: conversation,
                otherUser: conversationsViewModel.getOtherUser(for: conversation)
            )
            .id(conversation.id) // Force recreate view when conversation changes
        } else {
            EmptyChatView()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Spacer()

            Menu {
                if let user = authViewModel.currentUser {
                    // User info header (as Button that does nothing - required for macOS Menu)
                    Button {} label: {
                        Text(user.displayName.isEmpty ? "User" : user.displayName)
                    }
                    .disabled(true)

                    Button {} label: {
                        Text(user.email.isEmpty ? (user.id ?? "Unknown") : user.email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .disabled(true)

                    Divider()

                    if user.isAdmin || user.canInvite {
                        Button {
                            showInviteUsers = true
                        } label: {
                            Label("Invite Users", systemImage: "person.badge.plus")
                        }
                    }

                    if user.isAdmin {
                        Button {
                            showManageUsers = true
                        } label: {
                            Label("Manage Users", systemImage: "person.3")
                        }
                    }

                    if user.isAdmin || user.canInvite {
                        Divider()
                    }

                    // Theme submenu
                    Menu("Appearance") {
                        Button {
                            themeManager.setTheme(.system)
                        } label: {
                            Label("System", systemImage: themeManager.selectedTheme == "system" ? "checkmark" : "")
                        }

                        Button {
                            themeManager.setTheme(.light)
                        } label: {
                            Label("Light", systemImage: themeManager.selectedTheme == "light" ? "checkmark" : "")
                        }

                        Button {
                            themeManager.setTheme(.dark)
                        } label: {
                            Label("Dark", systemImage: themeManager.selectedTheme == "dark" ? "checkmark" : "")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        authViewModel.logout()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if let user = authViewModel.currentUser {
                        // Profile image
                        ProfileAvatarView(
                            imageData: profileImageData,
                            initials: user.initials,
                            size: 28
                        )

                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

}

#Preview {
    MainView()
        .frame(width: 1000, height: 700)
}
