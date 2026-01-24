import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @State private var scrollProxy: ScrollViewProxy?
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var searchResults: [Message] = []
    @State private var currentSearchIndex = 0
    @State private var replyToMessage: Message? = nil

    let otherUser: User?

    private var currentHighlightedMessageId: String? {
        guard !searchResults.isEmpty, currentSearchIndex < searchResults.count else { return nil }
        return searchResults[currentSearchIndex].id
    }

    init(conversation: Conversation, otherUser: User?) {
        self._viewModel = StateObject(wrappedValue: ChatViewModel(conversation: conversation))
        self.otherUser = otherUser
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader

            // Search bar (when active)
            if isSearching {
                conversationSearchBar
            }

            Divider()

            // Messages
            messagesScrollView

            // Typing indicator
            if viewModel.otherUserIsTyping {
                typingIndicator
            }

            Divider()

            // Reply preview
            if let replyMessage = replyToMessage {
                replyPreview(for: replyMessage)
            }

            // Input
            MessageInputView(
                text: $viewModel.messageText,
                showGiphyPicker: $viewModel.showGiphyPicker,
                showEmojiPicker: $viewModel.showEmojiPicker,
                isSending: viewModel.isSending,
                onSend: {
                    Task {
                        await viewModel.sendTextMessage(
                            replyToId: replyToMessage?.id,
                            replyToContent: replyToMessage?.content,
                            replyToSenderId: replyToMessage?.senderId
                        )
                        replyToMessage = nil
                    }
                }
            )
        }
        .background(Color(.windowBackgroundColor))
        .sheet(isPresented: $viewModel.showGiphyPicker) {
            GiphyPickerView { gif in
                Task {
                    await viewModel.sendGif(gif)
                }
            }
        }
        .onAppear {
            viewModel.startListening()
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .onChange(of: viewModel.messages.count) { _, _ in
            scrollToBottom()
        }
    }

    // MARK: - Chat Header

    private var chatHeader: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Avatar
            ZStack {
                if let avatarBase64 = otherUser?.avatarData,
                   let avatarData = Data(base64Encoded: avatarBase64) {
                    ProfileAvatarView(
                        imageData: avatarData,
                        initials: otherUser?.initials ?? "?",
                        size: 40
                    )
                } else {
                    Circle()
                        .fill(Theme.Colors.accent)
                        .frame(width: 40, height: 40)

                    Text(otherUser?.initials ?? "?")
                        .font(Theme.Typography.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }

                // Online indicator
                if otherUser?.isOnline == true {
                    Circle()
                        .fill(Theme.Colors.online)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color(.windowBackgroundColor), lineWidth: 2)
                        )
                        .offset(x: 14, y: 14)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(otherUser?.displayName ?? "Unknown")
                    .font(Theme.Typography.headline)
                    .fontWeight(.semibold)

                if let user = otherUser {
                    Text(user.isOnline ? "Active now" : "Offline")
                        .font(Theme.Typography.caption)
                        .foregroundColor(user.isOnline ? Theme.Colors.online : .secondary)
                }
            }

            Spacer()

            // Search button
            Button {
                withAnimation(Theme.Animation.quick) {
                    isSearching.toggle()
                    if !isSearching {
                        searchText = ""
                        searchResults = []
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundColor(isSearching ? .white : Theme.Colors.accent)
                    .padding(6)
                    .background(isSearching ? Theme.Colors.accent : Color.clear)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("Search in conversation")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Messages

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.xs) {
                    // Load more button at top
                    if viewModel.hasMoreMessages && !viewModel.messages.isEmpty {
                        loadMoreButton
                    }

                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                        VStack(spacing: Theme.Spacing.xs) {
                            if viewModel.shouldShowTimestamp(for: index) {
                                timestampView(for: message)
                            }

                            MessageBubbleView(
                                message: message,
                                isFromCurrentUser: viewModel.isFromCurrentUser(message),
                                showAvatar: viewModel.shouldShowAvatar(for: index),
                                senderUser: viewModel.isFromCurrentUser(message) ? nil : otherUser,
                                isHighlighted: message.id == currentHighlightedMessageId,
                                showTimestamp: viewModel.shouldShowMessageTimestamp(for: index),
                                onReply: {
                                    withAnimation(Theme.Animation.quick) {
                                        replyToMessage = message
                                    }
                                }
                            )
                            .id(message.id)
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .onAppear {
                scrollProxy = proxy
                scrollToBottom()
            }
        }
    }

    private var loadMoreButton: some View {
        Button {
            Task {
                await viewModel.loadOlderMessages()
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                if viewModel.isLoadingOlder {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 14))
                }
                Text(viewModel.isLoadingOlder ? "Loading..." : "Load older messages")
                    .font(Theme.Typography.caption)
            }
            .foregroundColor(Theme.Colors.accent)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoadingOlder)
        .frame(maxWidth: .infinity)
    }

    private func timestampView(for message: Message) -> some View {
        Text(message.timestamp.fullTimestamp())
            .font(Theme.Typography.footnote)
            .foregroundColor(.secondary)
            .padding(.vertical, Theme.Spacing.sm)
    }

    private func scrollToBottom() {
        guard let lastMessage = viewModel.messages.last else { return }
        withAnimation(Theme.Animation.quick) {
            scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }

    // MARK: - Typing Indicator

    private var typingIndicator: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Mini avatar
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent)
                    .frame(width: 24, height: 24)

                Text(otherUser?.initials.prefix(1) ?? "?")
                    .font(Theme.Typography.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }

            // Typing dots
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(0.6)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: viewModel.otherUserIsTyping
                        )
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Color(.textBackgroundColor))
            .cornerRadius(Theme.CornerRadius.bubble)

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xs)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Reply Preview

    private func replyPreview(for message: Message) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.Colors.accent)
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Replying to")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.accent)

                Text(message.content)
                    .font(Theme.Typography.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                withAnimation(Theme.Animation.quick) {
                    replyToMessage = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Color(.textBackgroundColor).opacity(0.5))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Conversation Search Bar

    private var conversationSearchBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14))

            TextField("Search in conversation...", text: $searchText)
                .textFieldStyle(.plain)
                .font(Theme.Typography.callout)
                .onSubmit {
                    performSearch()
                }
                .onChange(of: searchText) { _, newValue in
                    if newValue.isEmpty {
                        searchResults = []
                        currentSearchIndex = 0
                    } else {
                        performSearch()
                    }
                }

            if !searchResults.isEmpty {
                Text("\(currentSearchIndex + 1)/\(searchResults.count)")
                    .font(Theme.Typography.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                Button {
                    navigateToPreviousResult()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
                .disabled(searchResults.isEmpty)

                Button {
                    navigateToNextResult()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
                .disabled(searchResults.isEmpty)
            }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                    currentSearchIndex = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Color(.textBackgroundColor))
        .cornerRadius(Theme.CornerRadius.medium)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Search Functions

    private func performSearch() {
        guard !searchText.trimmed.isEmpty else {
            searchResults = []
            return
        }

        let query = searchText.lowercased()
        searchResults = viewModel.messages.filter { message in
            message.content.lowercased().contains(query)
        }

        if !searchResults.isEmpty {
            currentSearchIndex = searchResults.count - 1 // Start from most recent
            scrollToSearchResult()
        }
    }

    private func navigateToNextResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex + 1) % searchResults.count
        scrollToSearchResult()
    }

    private func navigateToPreviousResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = currentSearchIndex > 0 ? currentSearchIndex - 1 : searchResults.count - 1
        scrollToSearchResult()
    }

    private func scrollToSearchResult() {
        guard currentSearchIndex < searchResults.count else { return }
        let message = searchResults[currentSearchIndex]
        withAnimation(Theme.Animation.standard) {
            scrollProxy?.scrollTo(message.id, anchor: .center)
        }
    }
}

// MARK: - Empty Chat View

struct EmptyChatView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.3))

            Text("Select a conversation")
                .font(Theme.Typography.title)
                .foregroundColor(.secondary)

            Text("Choose a conversation from the sidebar or start a new one")
                .font(Theme.Typography.callout)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
}

#Preview {
    ChatView(
        conversation: Conversation(
            id: "1",
            participants: ["user1", "user2"]
        ),
        otherUser: User(
            id: "user2",
            email: "john@example.com",
            displayName: "John Doe",
            isOnline: true
        )
    )
    .frame(width: 600, height: 500)
}
