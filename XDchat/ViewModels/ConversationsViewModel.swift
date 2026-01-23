import Foundation
import Combine

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
    private var conversationsListenerId: String?
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private var deletingConversationIds = Set<String>()

    var currentUserId: String? {
        authService.currentUser?.id
    }

    init() {
        setupSearchDebounce()
        setupAuthObserver()
    }

    // MARK: - Auth Observer

    private func setupAuthObserver() {
        // Obserwuj zmiany currentUser w AuthService
        // Gdy użytkownik się zaloguje, pobierz listę użytkowników
        authService.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                guard let self = self, user != nil else { return }
                // Użytkownik zalogowany - pobierz listę użytkowników
                Task {
                    await self.fetchAllUsers()
                }
            }
            .store(in: &cancellables)
    }

    nonisolated func cleanup() {
        // Cleanup is handled by stopListening() which should be called when view disappears
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

        conversationsListenerId = firestoreService.listenToConversations(for: userId) { [weak self] conversations in
            Task { @MainActor in
                guard let self = self else { return }
                // Filter out conversations that are being deleted
                let filteredConversations = conversations.filter { conversation in
                    guard let id = conversation.id else { return true }
                    return !self.deletingConversationIds.contains(id)
                }
                self.conversations = filteredConversations
                await self.fetchParticipantUsers(for: filteredConversations)
            }
        }
    }

    func stopListening() {
        if let listenerId = conversationsListenerId {
            firestoreService.removeListener(id: listenerId)
            conversationsListenerId = nil
        }
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
        } catch {
            // Silently handle user fetch errors
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
                }
            }
        }
    }

    // MARK: - Create Conversation

    func startConversation(with user: User) async {
        guard let currentUserId = currentUserId,
              let otherUserId = user.id else { return }

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

    // MARK: - Fetch All Users

    func fetchAllUsers() async {
        // Pobierz currentUserId - jeśli nil, i tak spróbuj pobrać użytkowników
        let excludeUserId = currentUserId

        do {
            let fetchedUsers = try await firestoreService.getAllUsers()
            // Filtruj bieżącego użytkownika jeśli znany
            if let excludeId = excludeUserId {
                allUsers = fetchedUsers.filter { $0.id != excludeId }
            } else {
                allUsers = fetchedUsers
            }
            print("[ConversationsViewModel] Loaded \(allUsers.count) users")
        } catch {
            print("[ConversationsViewModel] Error fetching users: \(error)")
            errorMessage = "Failed to load users: \(error.localizedDescription)"
        }
    }

    // MARK: - Delete Conversation

    @MainActor
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
            // Keep in deletingConversationIds to prevent re-adding from any pending listener updates
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
        await MainActor.run {
            self.conversations = fetchedConversations
        }
    }
}
