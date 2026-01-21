import Foundation
import Combine

// MARK: - Auth Service Protocol

protocol AuthServiceProtocol: ObservableObject {
    var currentUser: User? { get }
    var isAuthenticated: Bool { get }
    var isLoading: Bool { get }

    func login(email: String, password: String) async throws
    func logout() throws
    func register(email: String, password: String, displayName: String, invitationCode: String?) async throws
    func resetPassword(email: String) async throws
    func updateOnlineStatus(_ isOnline: Bool)
    func updateDisplayName(_ displayName: String) async throws
}

// MARK: - Firestore Service Protocol

protocol FirestoreServiceProtocol {
    // Users
    func getUser(userId: String) async throws -> User?
    func getUsers(userIds: [String]) async throws -> [User]
    func getAllUsers() async throws -> [User]
    func searchUsers(query: String, excludingUserId: String) async throws -> [User]
    func updateUserAvatar(userId: String, avatarData: String) async throws

    // Conversations
    func createConversation(participants: [String]) async throws -> Conversation
    func deleteConversation(conversationId: String) async throws
    func getConversations(for userId: String) async throws -> [Conversation]
    func listenToConversations(for userId: String, onChange: @escaping ([Conversation]) -> Void) -> String
    func updateConversationLastMessage(conversationId: String, message: String, senderId: String) async throws

    // Messages
    func sendMessage(_ message: Message) async throws
    func getMessages(for conversationId: String, limit: Int) async throws -> [Message]
    func listenToMessages(for conversationId: String, onChange: @escaping ([Message]) -> Void) -> String

    // Typing
    func setTypingStatus(conversationId: String, userId: String, isTyping: Bool) async throws

    // Read Status
    func markMessagesAsRead(conversationId: String, userId: String) async throws
    func incrementUnreadCount(conversationId: String, for userId: String) async throws

    // Listener Management
    func removeListener(id: String)
    func removeAllListeners()
}

// MARK: - Invitation Service Protocol

protocol InvitationServiceProtocol: ObservableObject {
    var myInvitations: [Invitation] { get }
    var isLoading: Bool { get }

    func createInvitation(by user: User, expiresInDays: Int?) async throws -> Invitation
    func validateInvitation(code: String) async throws -> Invitation
    func getInvitations(createdBy userId: String) async throws -> [Invitation]
    func listenToMyInvitations(userId: String)
    func deleteInvitation(_ invitation: Invitation) async throws
    func grantInvitePermission(to userId: String) async throws
    func revokeInvitePermission(from userId: String) async throws
    func stopListening()
}

// MARK: - Giphy Service Protocol

protocol GiphyServiceProtocol: ObservableObject {
    var trendingGifs: [GiphyImage] { get }
    var searchResults: [GiphyImage] { get }
    var isLoading: Bool { get }

    func fetchTrending(limit: Int, offset: Int) async throws -> [GiphyImage]
    func search(query: String, limit: Int, offset: Int) async throws -> [GiphyImage]
    func clearSearch()
}

// MARK: - Default Parameter Extensions

extension FirestoreServiceProtocol {
    func getMessages(for conversationId: String) async throws -> [Message] {
        try await getMessages(for: conversationId, limit: 50)
    }
}

extension GiphyServiceProtocol {
    func fetchTrending() async throws -> [GiphyImage] {
        try await fetchTrending(limit: 25, offset: 0)
    }

    func search(query: String) async throws -> [GiphyImage] {
        try await search(query: query, limit: 25, offset: 0)
    }
}

extension InvitationServiceProtocol {
    func createInvitation(by user: User) async throws -> Invitation {
        try await createInvitation(by: user, expiresInDays: 7)
    }
}
