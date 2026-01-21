import Foundation
import FirebaseCore
import FirebaseFirestore
import Combine

class FirestoreService: ObservableObject, FirestoreServiceProtocol {
    static let shared = FirestoreService()

    private var db: Firestore { Firestore.firestore() }
    private var listeners: [String: ListenerRegistration] = [:]

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

            let users = snapshot.documents.compactMap { try? $0.data(as: User.self) }
            allUsers.append(contentsOf: users)
        }

        return allUsers
    }

    func getAllUsers() async throws -> [User] {
        let snapshot = try await db.collection("users")
            .limit(to: Constants.Pagination.defaultUserLimit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: User.self) }
    }

    func searchUsers(query: String, excludingUserId: String) async throws -> [User] {
        let searchQuery = query.trimmed
        guard !searchQuery.isEmpty else { return [] }

        var usersDict: [String: User] = [:]

        // Search by displayName (case-sensitive prefix match)
        let displayNameSnapshot = try await db.collection("users")
            .whereField("displayName", isGreaterThanOrEqualTo: searchQuery)
            .whereField("displayName", isLessThanOrEqualTo: searchQuery + "\u{f8ff}")
            .limit(to: Constants.Pagination.defaultUserLimit)
            .getDocuments()

        for doc in displayNameSnapshot.documents {
            if let user = try? doc.data(as: User.self), let id = user.id {
                usersDict[id] = user
            }
        }

        // Search by email (lowercase prefix match)
        let emailSnapshot = try await db.collection("users")
            .whereField("email", isGreaterThanOrEqualTo: searchQuery.lowercased())
            .whereField("email", isLessThanOrEqualTo: searchQuery.lowercased() + "\u{f8ff}")
            .limit(to: Constants.Pagination.defaultUserLimit)
            .getDocuments()

        for doc in emailSnapshot.documents {
            if let user = try? doc.data(as: User.self), let id = user.id {
                usersDict[id] = user
            }
        }

        // Also search by displayName lowercase for partial matches
        let lowerSearchQuery = searchQuery.lowercased()
        let allUsersSnapshot = try await db.collection("users")
            .limit(to: Constants.Pagination.defaultUserLimit)
            .getDocuments()

        for doc in allUsersSnapshot.documents {
            if let user = try? doc.data(as: User.self), let id = user.id {
                let displayNameLower = user.displayName.lowercased()
                if displayNameLower.contains(lowerSearchQuery) {
                    usersDict[id] = user
                }
            }
        }

        return Array(usersDict.values).filter { $0.id != excludingUserId }
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
        // Check if conversation already exists between these participants
        if let existingConversation = try await findExistingConversation(participants: participants) {
            return existingConversation
        }

        let conversation = Conversation(
            participants: participants,
            createdAt: Date()
        )

        let docRef = db.collection("conversations").document()
        var newConversation = conversation
        newConversation.id = docRef.documentID

        try docRef.setData(from: newConversation)

        return newConversation
    }

    func deleteConversation(conversationId: String) async throws {
        // Delete all messages in the conversation first
        let messagesSnapshot = try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .getDocuments()

        let batch = db.batch()

        for document in messagesSnapshot.documents {
            batch.deleteDocument(document.reference)
        }

        // Delete the conversation document
        batch.deleteDocument(db.collection("conversations").document(conversationId))

        try await batch.commit()
    }

    private func findExistingConversation(participants: [String]) async throws -> Conversation? {
        let sortedParticipants = participants.sorted()

        let snapshot = try await db.collection("conversations")
            .whereField("participants", isEqualTo: sortedParticipants)
            .limit(to: 1)
            .getDocuments()

        return try snapshot.documents.first?.data(as: Conversation.self)
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
            .addSnapshotListener { snapshot, error in
                if error != nil {
                    return
                }

                guard let snapshot = snapshot else { return }

                let conversations = snapshot.documents.compactMap {
                    try? $0.data(as: Conversation.self)
                }
                onChange(conversations)
            }

        listeners[listenerId] = listener
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
        onChange: @escaping ([Message]) -> Void
    ) -> String {
        let listenerId = UUID().uuidString

        let listener = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("[FirestoreService] Messages listener error: \(error.localizedDescription)")
                    return
                }

                guard let snapshot = snapshot else {
                    print("[FirestoreService] Messages snapshot is nil")
                    return
                }

                let messages = snapshot.documents.compactMap { doc -> Message? in
                    try? doc.data(as: Message.self)
                }
                print("[FirestoreService] Loaded \(messages.count) messages")
                onChange(messages)
            }

        listeners[listenerId] = listener
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
        listeners[id]?.remove()
        listeners.removeValue(forKey: id)
    }

    func removeAllListeners() {
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
    }
}
