import Foundation
import FirebaseCore
import FirebaseFirestore
import Combine
import os.log

class FirestoreService: ObservableObject, FirestoreServiceProtocol {
    static let shared = FirestoreService()

    private var db: Firestore { Firestore.firestore() }
    private var listeners: [String: ListenerRegistration] = [:]
    private let listenersLock = NSLock()

    private init() {}

    deinit {
        removeAllListeners()
    }

    // MARK: - Users

    func getUser(userId: String) async throws -> User? {
        let document = try await db.collection("users").document(userId).getDocument()
        return try document.data(as: User.self)
    }

    func getUsers(userIds: [String]) async throws -> [User] {
        guard !userIds.isEmpty else { return [] }

        // Firestore 'in' queries are limited to 10 items, so batch if needed
        var allUsers: [User] = []
        let batches = stride(from: 0, to: userIds.count, by: 10).map {
            Array(userIds[$0..<min($0 + 10, userIds.count)])
        }

        for batch in batches {
            let snapshot = try await db.collection("users")
                .whereField(FieldPath.documentID(), in: batch)
                .limit(to: 10)
                .getDocuments()

            let users = snapshot.documents.compactMap { doc -> User? in
                do {
                    return try doc.data(as: User.self)
                } catch {
                    Logger.firestore.debug("Failed to decode user \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }
            allUsers.append(contentsOf: users)
        }

        return allUsers
    }

    func getAllUsers() async throws -> [User] {
        let snapshot = try await db.collection("users")
            .order(by: "displayName")
            .limit(to: 50)
            .getDocuments()

        return snapshot.documents.compactMap { doc -> User? in
            do {
                return try doc.data(as: User.self)
            } catch {
                Logger.firestore.debug("Failed to decode user \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        }
    }

    func searchUsers(query: String, excludingUserId: String) async throws -> [User] {
        let searchQuery = query.trimmed.lowercased()
        guard !searchQuery.isEmpty else { return [] }

        // Get all users and filter locally (Firestore doesn't support full-text search)
        let allUsers = try await getAllUsers()

        return allUsers.filter { user in
            guard user.id != excludingUserId else { return false }

            let displayNameMatch = user.displayName.lowercased().contains(searchQuery)
            let emailMatch = user.email.lowercased().contains(searchQuery)

            return displayNameMatch || emailMatch
        }
    }

    /// Fetches users with pagination support
    func getUsers(
        limit: Int = Constants.Pagination.defaultUserLimit,
        afterUserId: String? = nil
    ) async throws -> [User] {
        var query = db.collection("users")
            .order(by: "displayName")
            .limit(to: limit)

        if let afterUserId = afterUserId {
            let afterDoc = try await db.collection("users").document(afterUserId).getDocument()
            query = query.start(afterDocument: afterDoc)
        }

        let snapshot = try await query.getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: User.self) }
    }

    func updateUserAvatar(userId: String, avatarData: String) async throws {
        try await db.collection("users").document(userId).updateData([
            "avatarData": avatarData
        ])
    }

    // MARK: - Conversations

    func createConversation(participants: [String]) async throws -> Conversation {
        let sortedParticipants = participants.sorted()

        // Check if conversation already exists between these participants
        if let existingConversation = try await findExistingConversation(participants: sortedParticipants) {
            return existingConversation
        }

        // Create new conversation
        let conversation = Conversation(
            participants: sortedParticipants,
            createdAt: Date()
        )

        let docRef = db.collection("conversations").document()
        var newConversation = conversation
        newConversation.id = docRef.documentID

        try docRef.setData(from: newConversation)

        return newConversation
    }

    private func findExistingConversation(participants: [String]) async throws -> Conversation? {
        let snapshot = try await db.collection("conversations")
            .whereField("participants", isEqualTo: participants)
            .limit(to: 1)
            .getDocuments()

        return try snapshot.documents.first?.data(as: Conversation.self)
    }

    func deleteConversation(conversationId: String) async throws {
        let messagesCollection = db.collection("conversations")
            .document(conversationId)
            .collection("messages")

        // Delete messages in batches of 450 (Firestore batch limit is 500)
        let batchSize = 450
        var hasMore = true

        while hasMore {
            let snapshot = try await messagesCollection
                .limit(to: batchSize)
                .getDocuments()

            if snapshot.documents.isEmpty {
                hasMore = false
                break
            }

            let batch = db.batch()
            for document in snapshot.documents {
                batch.deleteDocument(document.reference)
            }
            try await batch.commit()

            hasMore = snapshot.documents.count == batchSize
        }

        // Delete the conversation document itself
        try await db.collection("conversations").document(conversationId).delete()
    }

    func getConversation(id: String) async throws -> Conversation? {
        let document = try await db.collection("conversations").document(id).getDocument()
        guard document.exists else { return nil }
        return try document.data(as: Conversation.self)
    }

    func getConversations(for userId: String) async throws -> [Conversation] {
        let snapshot = try await db.collection("conversations")
            .whereField("participants", arrayContains: userId)
            .order(by: "lastMessageAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { try? $0.data(as: Conversation.self) }
    }

    func listenToConversations(
        for userId: String,
        onChange: @escaping ([Conversation]) -> Void
    ) -> String {
        let listenerId = UUID().uuidString

        let listener = db.collection("conversations")
            .whereField("participants", arrayContains: userId)
            .order(by: "lastMessageAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil else { return }

                if let error = error {
                    Logger.firestore.error("Conversations listener error: \(error.localizedDescription)")
                    return
                }

                guard let snapshot = snapshot else { return }

                let conversations = snapshot.documents.compactMap {
                    try? $0.data(as: Conversation.self)
                }
                onChange(conversations)
            }

        listenersLock.lock()
        listeners[listenerId] = listener
        listenersLock.unlock()
        return listenerId
    }

    func updateConversationLastMessage(
        conversationId: String,
        message: String,
        senderId: String
    ) async throws {
        try await db.collection("conversations").document(conversationId).updateData([
            "lastMessage": message,
            "lastMessageAt": FieldValue.serverTimestamp(),
            "lastMessageSenderId": senderId
        ])
    }

    // MARK: - Messages

    func sendMessage(_ message: Message) async throws {
        let docRef = db.collection("conversations")
            .document(message.conversationId)
            .collection("messages")
            .document()

        var newMessage = message
        newMessage.id = docRef.documentID

        try docRef.setData(from: newMessage)

        // Update conversation last message
        let displayMessage: String
        switch message.type {
        case .text:
            displayMessage = message.content
        case .gif:
            displayMessage = "GIF"
        case .sticker:
            displayMessage = "Sticker"
        case .emoji:
            displayMessage = message.content
        }

        try await updateConversationLastMessage(
            conversationId: message.conversationId,
            message: displayMessage,
            senderId: message.senderId
        )
    }

    func getMessages(for conversationId: String, limit: Int = 50) async throws -> [Message] {
        let snapshot = try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents
            .compactMap { try? $0.data(as: Message.self) }
            .reversed()
    }

    /// Fetches older messages before a given timestamp (for pagination)
    func getOlderMessages(
        for conversationId: String,
        before timestamp: Date,
        limit: Int = Constants.Pagination.defaultMessageLimit
    ) async throws -> [Message] {
        let snapshot = try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .whereField("timestamp", isLessThan: timestamp)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents
            .compactMap { try? $0.data(as: Message.self) }
            .reversed()
    }

    func listenToMessages(
        for conversationId: String,
        limit: Int = Constants.Pagination.defaultMessageLimit,
        onChange: @escaping ([Message]) -> Void
    ) -> String {
        let listenerId = UUID().uuidString

        // Listen to the most recent messages only (with limit)
        // Order by descending to get latest, then reverse for display
        let listener = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil else { return }

                if let error = error {
                    Logger.firestore.error("Messages listener error: \(error.localizedDescription)")
                    return
                }

                guard let snapshot = snapshot else { return }

                // Reverse to get chronological order (oldest first)
                let messages = snapshot.documents
                    .compactMap { try? $0.data(as: Message.self) }
                    .reversed()

                onChange(Array(messages))
            }

        listenersLock.lock()
        listeners[listenerId] = listener
        listenersLock.unlock()
        return listenerId
    }

    /// Listen to a single conversation document (used for typing indicators)
    func listenToConversation(
        id conversationId: String,
        onChange: @escaping (Conversation?) -> Void
    ) -> String {
        let listenerId = UUID().uuidString

        let listener = db.collection("conversations").document(conversationId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil else { return }

                if let error = error {
                    Logger.firestore.error("Conversation listener error: \(error.localizedDescription)")
                    return
                }

                guard let snapshot = snapshot else { return }
                let conversation = try? snapshot.data(as: Conversation.self)
                onChange(conversation)
            }

        listenersLock.lock()
        listeners[listenerId] = listener
        listenersLock.unlock()
        return listenerId
    }

    // MARK: - Typing Indicator

    func setTypingStatus(conversationId: String, userId: String, isTyping: Bool) async throws {
        let docRef = db.collection("conversations").document(conversationId)

        if isTyping {
            try await docRef.updateData([
                "typingUsers": FieldValue.arrayUnion([userId])
            ])
        } else {
            try await docRef.updateData([
                "typingUsers": FieldValue.arrayRemove([userId])
            ])
        }
    }

    // MARK: - Read Status

    func markMessagesAsRead(conversationId: String, userId: String) async throws {
        try await db.collection("conversations").document(conversationId).updateData([
            "unreadCount.\(userId)": 0
        ])
    }

    func incrementUnreadCount(conversationId: String, for userId: String) async throws {
        try await db.collection("conversations").document(conversationId).updateData([
            "unreadCount.\(userId)": FieldValue.increment(Int64(1))
        ])
    }

    // MARK: - Listener Management

    func removeListener(id: String) {
        listenersLock.lock()
        listeners[id]?.remove()
        listeners.removeValue(forKey: id)
        listenersLock.unlock()
    }

    func removeAllListeners() {
        listenersLock.lock()
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
        listenersLock.unlock()
    }
}
