import SwiftUI

struct ConversationListView: View {
    @ObservedObject var viewModel: ConversationsViewModel
    @State private var showNewConversation = false
    @State private var conversationToDelete: Conversation?
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Search
            searchBar
                .padding(Theme.Spacing.md)

            // Conversation List
            if viewModel.conversations.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                conversationList
            }
        }
        .background(Color(.windowBackgroundColor))
        .sheet(isPresented: $showNewConversation, onDismiss: {
            viewModel.searchQuery = ""
            viewModel.searchResults = []
        }) {
            NewConversationView(viewModel: viewModel)
        }
        .alert("Delete Conversation", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                conversationToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let conversation = conversationToDelete {
                    Task {
                        await viewModel.deleteConversation(conversation)
                    }
                }
                conversationToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this conversation? This cannot be undone.")
        }
        .onAppear {
            // Start listening if not already active.
            // Don't stop on onDisappear -- sidebar can collapse in NavigationSplitView
            // which would kill notifications. Listener is stopped on logout instead.
            viewModel.startListening()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Chats")
                .font(Theme.Typography.title)
                .fontWeight(.bold)

            Spacer()

            Button {
                showNewConversation = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18))
                    .foregroundColor(Theme.Colors.accent)
            }
            .buttonStyle(.plain)
            .help("New conversation")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
        }
        .padding(Theme.Spacing.sm)
        .background(Color(.textBackgroundColor))
        .cornerRadius(Theme.CornerRadius.medium)
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.conversations) { conversation in
                    ConversationRowView(
                        conversation: conversation,
                        otherUser: viewModel.getOtherUser(for: conversation),
                        currentUserId: viewModel.currentUserId ?? "",
                        isSelected: viewModel.selectedConversation?.id == conversation.id
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectConversation(conversation)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            conversationToDelete = conversation
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Conversation", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 50))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No conversations yet")
                .font(Theme.Typography.headline)
                .foregroundColor(.secondary)

            Text("Start a new conversation by clicking the compose button above.")
                .font(Theme.Typography.callout)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            Button {
                showNewConversation = true
            } label: {
                Text("Start a Chat")
                    .fontWeight(.semibold)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.messengerGradient)
                    .foregroundColor(.white)
                    .cornerRadius(Theme.CornerRadius.medium)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - New Conversation View

struct NewConversationView: View {
    @ObservedObject var viewModel: ConversationsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.Colors.accent)

                Spacer()

                Text("New Conversation")
                    .font(Theme.Typography.headline)

                Spacer()

                // Placeholder for symmetry
                Button("Cancel") { }
                    .buttonStyle(.plain)
                    .opacity(0)
            }
            .padding(Theme.Spacing.lg)

            Divider()

            // Search
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search users...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(Theme.Spacing.md)
            .background(Color(.textBackgroundColor))
            .cornerRadius(Theme.CornerRadius.medium)
            .padding(Theme.Spacing.lg)

            // Results
            if viewModel.searchQuery.isEmpty {
                // Empty state - prompt to search
                VStack(spacing: Theme.Spacing.lg) {
                    Spacer()
                    Image(systemName: "person.2")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Search for users")
                        .font(Theme.Typography.headline)
                        .foregroundColor(.secondary)
                    Text("Type a name or email to find people")
                        .font(Theme.Typography.callout)
                        .foregroundColor(.secondary.opacity(0.8))
                    Spacer()
                }
            } else if viewModel.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.searchResults.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    Spacer()
                    Image(systemName: "person.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No users found")
                        .font(Theme.Typography.callout)
                        .foregroundColor(.secondary)

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(Theme.Typography.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.searchResults) { user in
                            UserRowView(user: user) {
                                Task {
                                    await viewModel.startConversation(with: user)
                                    dismiss()
                                }
                            }
                            Divider()
                                .padding(.leading, 72)
                        }
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
    }
}

// MARK: - User Row View

struct UserRowView: View {
    let user: User
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Theme.Spacing.md) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(Theme.messengerGradient)
                        .frame(width: 44, height: 44)

                    Text(user.initials)
                        .font(Theme.Typography.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName)
                        .font(Theme.Typography.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(user.email)
                        .font(Theme.Typography.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Online indicator
                if user.isOnline {
                    Circle()
                        .fill(Theme.Colors.online)
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ConversationListView(viewModel: ConversationsViewModel())
        .frame(width: 320)
}
