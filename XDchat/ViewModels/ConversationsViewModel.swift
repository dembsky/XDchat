import Foundation
import Combine
import AppKit
import os.log

@MainActor
class ConversationsViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var users: [String: User] = [:]
    @Published var allUsers: [User] = []
    @Published var searchQuery = ""
    @Published var searchResults: [User] = []
    @Published var isLoading = false
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var selectedConversation: Conversation?
    @Published var showNewConversationSheet = false

    private let firestoreService = FirestoreService.shared
    private let authService = AuthService.shared
    private let notificationService = NotificationService.shared
    private var conversationsListenerId: String?
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private var notificationTasks: [Task<Void, Never>] = []
    private var deletingConversationIds = Set<String>()
    private var lastMessageTimestamps: [String: Date] = [:]
    private var isInitialLoad = true

    var currentUserId: String? {
        authService.currentUser?.id
    }

    init() {
        setupSearchDebounce()
        setupAuthObserver()
    }

    // MARK: - Auth Observer

    private func setupAuthObserver() {
        authService.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                guard let self else { return }
                if user != nil {
                    Task { [weak self] in
                        await self?.fetchAllUsers()
                    }
                } else {
                    // User logged out - stop listening and reset state
                    self.stopListening()
                    self.conversations = []
                    self.selectedConversation = nil
                    self.users = [:]
                    self.allUsers = []
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(Constants.TimeIntervals.searchDebounceMilliseconds), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.performSearch(query: query)
            }
            .store(in: &cancellables)
    }

    // MARK: - Conversations

    func startListening() {
        guard let userId = currentUserId else { return }
        // Prevent duplicate listeners if already active
        guard conversationsListenerId == nil else { return }
        isInitialLoad = true

        conversationsListenerId = firestoreService.listenToConversations(for: userId) { [weak self] conversations in
            Task { @MainActor in
                guard let self = self else { return }
                // Filter out conversations that are being deleted
                let filteredConversations = conversations.filter { conversation in
                    guard let id = conversation.id else { return true }
                    return !self.deletingConversationIds.contains(id)
                }

                // Clean up deletion guards for conversations that are no longer in the snapshot
                let activeIds = Set(conversations.compactMap(\.id))
                self.deletingConversationIds = self.deletingConversationIds.filter { activeIds.contains($0) }

                // Capture old timestamps before updating to prevent duplicate notifications
                let previousTimestamps = self.lastMessageTimestamps

                // Update stored timestamps immediately
                for conversation in filteredConversations {
                    if let id = conversation.id, let timestamp = conversation.lastMessageAt {
                        self.lastMessageTimestamps[id] = timestamp
                    }
                }

                // Check for new messages using old timestamps
                if !self.isInitialLoad {
                    self.checkForNewMessages(filteredConversations, previousTimestamps: previousTimestamps)
                }

                self.conversations = filteredConversations
                await self.fetchParticipantUsers(for: filteredConversations)

                self.isInitialLoad = false
            }
        }
    }

    func stopListening() {
        if let listenerId = conversationsListenerId {
            firestoreService.removeListener(id: listenerId)
            conversationsListenerId = nil
        }
        notificationTasks.forEach { $0.cancel() }
        notificationTasks.removeAll()
        lastMessageTimestamps.removeAll()
        isInitialLoad = true
    }

    // MARK: - Notifications

    private func checkForNewMessages(_ conversations: [Conversation], previousTimestamps: [String: Date]) {
        guard let currentUserId = currentUserId else { return }

        let notificationsEnabled = UserDefaults.standard.bool(forKey: Constants.StorageKeys.notificationsEnabled)
        guard notificationsEnabled else { return }

        let soundEnabled = UserDefaults.standard.bool(forKey: Constants.StorageKeys.soundEnabled)

        for conversation in conversations {
            notifyIfNewMessage(
                conversation,
                currentUserId: currentUserId,
                previousTimestamps: previousTimestamps,
                soundEnabled: soundEnabled
            )
        }

        Task {
            await updateBadgeCount(conversations)
        }
    }

    private func notifyIfNewMessage(
        _ conversation: Conversation,
        currentUserId: String,
        previousTimestamps: [String: Date],
        soundEnabled: Bool
    ) {
        guard let conversationId = conversation.id,
              let newTimestamp = conversation.lastMessageAt,
              let senderId = conversation.lastMessageSenderId,
              senderId != currentUserId else { return }

        // Only notify if we had a previous timestamp to compare against.
        // If oldTimestamp is nil, this conversation is new to our snapshot --
        // the message may be old, so skip to avoid stale notifications.
        guard let oldTimestamp = previousTimestamps[conversationId] else { return }
        let isNewMessage = newTimestamp > oldTimestamp
        let isCurrentConversation = selectedConversation?.id == conversationId && NSApp.isActive

        guard isNewMessage, !isCurrentConversation else { return }

        let rawPreview = conversation.lastMessage ?? "sent a message"
        let maxLength = Constants.Validation.maxNotificationPreviewLength
        let messagePreview = rawPreview.count > maxLength ? String(rawPreview.prefix(maxLength)) + "..." : rawPreview

        // Prevent unbounded growth: remove cancelled tasks and cap size
        notificationTasks.removeAll { $0.isCancelled }
        let maxTasks = Constants.Validation.maxPendingNotificationTasks
        if notificationTasks.count > maxTasks {
            notificationTasks.removeFirst(notificationTasks.count - maxTasks)
        }

        let task = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            var senderName = self.users[senderId]?.displayName
            if senderName == nil {
                if let user = try? await self.firestoreService.getUser(userId: senderId) {
                    guard !Task.isCancelled else { return }
                    self.users[senderId] = user
                    senderName = user.displayName
                }
            }

            guard !Task.isCancelled else { return }
            self.notificationService.showNotification(
                title: senderName ?? "New Message",
                body: messagePreview,
                conversationId: conversationId,
                sound: soundEnabled
            )
        }
        notificationTasks.append(task)
    }

    private func updateBadgeCount(_ conversations: [Conversation]) async {
        let badgeEnabled = UserDefaults.standard.bool(forKey: Constants.StorageKeys.badgeEnabled)

        guard badgeEnabled else {
            await notificationService.clearBadge()
            return
        }

        guard let currentUserId = currentUserId else { return }

        let unreadCount = conversations.reduce(0) { count, conversation in
            count + (conversation.unreadCount[currentUserId] ?? 0)
        }

        await notificationService.setBadgeCount(unreadCount)
    }

    private func fetchParticipantUsers(for conversations: [Conversation]) async {
        var allUserIds = Set<String>()
        for conversation in conversations {
            conversation.participants.forEach { allUserIds.insert($0) }
        }

        // Remove already fetched users
        let userIdsToFetch = allUserIds.filter { users[$0] == nil }

        guard !userIdsToFetch.isEmpty else { return }

        do {
            let fetchedUsers = try await firestoreService.getUsers(userIds: Array(userIdsToFetch))
            for user in fetchedUsers {
                if let userId = user.id {
                    users[userId] = user
                }
            }

            // Fallback: fetch individually any users that weren't returned by batch query
            let fetchedIds = Set(fetchedUsers.compactMap { $0.id })
            let missingIds = userIdsToFetch.subtracting(fetchedIds)
            for userId in missingIds {
                if let user = try? await firestoreService.getUser(userId: userId) {
                    users[userId] = user
                }
            }
        } catch {
            // Batch fetch failed - try fetching users individually
            for userId in userIdsToFetch {
                if let user = try? await firestoreService.getUser(userId: userId) {
                    users[userId] = user
                }
            }
        }
    }

    // MARK: - Search

    private func performSearch(query: String) {
        searchTask?.cancel()

        guard !query.trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        guard let currentUserId = currentUserId else { return }

        isSearching = true

        searchTask = Task {
            do {
                let results = try await firestoreService.searchUsers(
                    query: query.trimmed,
                    excludingUserId: currentUserId
                )

                if !Task.isCancelled {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                if !Task.isCancelled {
                    isSearching = false
                    Logger.conversations.debug("Search failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Create Conversation

    func startConversation(with user: User) async {
        guard let currentUserId = currentUserId,
              let otherUserId = user.id else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let participants = [currentUserId, otherUserId].sorted()
            let conversation = try await firestoreService.createConversation(participants: participants)

            // Cache the user
            users[otherUserId] = user

            selectedConversation = conversation
            showNewConversationSheet = false
            searchQuery = ""
            searchResults = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    func getOtherUser(for conversation: Conversation) -> User? {
        guard let currentUserId = currentUserId,
              let otherUserId = conversation.otherParticipantId(currentUserId: currentUserId) else {
            return nil
        }
        return users[otherUserId]
    }

    func conversationDisplayName(for conversation: Conversation) -> String {
        if let user = getOtherUser(for: conversation) {
            return user.displayName
        }
        return "Unknown"
    }

    func selectConversation(_ conversation: Conversation) {
        selectedConversation = conversation

        // Mark as read
        guard let currentUserId = currentUserId,
              let conversationId = conversation.id else { return }

        Task {
            try? await firestoreService.markMessagesAsRead(
                conversationId: conversationId,
                userId: currentUserId
            )
        }
    }

    /// Fetch and select a conversation by ID (used when opening from notification)
    func fetchAndSelectConversation(id conversationId: String) async {
        // First check if already loaded
        if let conversation = conversations.first(where: { $0.id == conversationId }) {
            selectConversation(conversation)
            return
        }

        // Fetch single conversation from Firestore
        do {
            guard let conversation = try await firestoreService.getConversation(id: conversationId) else {
                errorMessage = "Could not open conversation"
                return
            }
            await fetchParticipantUsers(for: [conversation])
            selectConversation(conversation)
        } catch {
            Logger.conversations.error("Failed to fetch conversation \(conversationId): \(error.localizedDescription)")
            errorMessage = "Could not open conversation"
        }
    }

    // MARK: - Fetch All Users

    func fetchAllUsers() async {
        let excludeUserId = currentUserId

        do {
            let fetchedUsers = try await firestoreService.getAllUsers()
            if let excludeId = excludeUserId {
                allUsers = fetchedUsers.filter { $0.id != excludeId }
            } else {
                allUsers = fetchedUsers
            }
        } catch {
            errorMessage = "Failed to load users: \(error.localizedDescription)"
        }
    }

    // MARK: - Delete Conversation

    func deleteConversation(_ conversation: Conversation) async {
        guard let conversationId = conversation.id else {
            return
        }

        // Mark as being deleted so listener ignores it
        deletingConversationIds.insert(conversationId)

        // Clear selection if deleted conversation was selected
        if selectedConversation?.id == conversationId {
            selectedConversation = nil
        }

        // Remove from local list immediately for better UX
        conversations.removeAll { $0.id == conversationId }

        do {
            try await firestoreService.deleteConversation(conversationId: conversationId)
            // deletingConversationIds is cleaned up automatically in the listener
            // when the conversation disappears from the Firestore snapshot
        } catch {
            errorMessage = error.localizedDescription
            // Remove from deleting set and re-fetch if failed
            deletingConversationIds.remove(conversationId)
            if let userId = currentUserId {
                try? await fetchConversations(for: userId)
            }
        }
    }

    private func fetchConversations(for userId: String) async throws {
        let fetchedConversations = try await firestoreService.getConversations(for: userId)
        self.conversations = fetchedConversations
    }
}
