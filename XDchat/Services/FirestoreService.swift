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
        // Try REST API first (for unsigned apps)
        guard let session = AuthTokenStorage.shared.loadSession() else {
            print("[FirestoreService] No session available")
            throw FirestoreREST.FirestoreError.notAuthenticated
        }

        // Check if token needs refresh
        if session.isExpired {
            print("[FirestoreService] Token expired, need refresh")
            throw FirestoreREST.FirestoreError.tokenExpired
        }

        print("[FirestoreService] Fetching all users via REST API...")
        let usersData = try await FirestoreREST.shared.listDocuments(
            collection: "users",
            idToken: session.idToken
        )
        print("[FirestoreService] REST API returned \(usersData.count) user documents")
        let users = usersData.compactMap { parseUserFromDict($0) }
        print("[FirestoreService] Parsed \(users.count) users from REST response")
        return users
    }

    func searchUsers(query: String, excludingUserId: String) async throws -> [User] {
        let searchQuery = query.trimmed.lowercased()
        guard !searchQuery.isEmpty else { return [] }

        print("[FirestoreService] Searching users with query: '\(searchQuery)', excluding: \(excludingUserId)")

        // Use REST API to get all users and filter locally
        let allUsers = try await getAllUsers()
        print("[FirestoreService] Got \(allUsers.count) total users to search through")

        let results = allUsers.filter { user in
            guard user.id != excludingUserId else { return false }

            let displayNameMatch = user.displayName.lowercased().contains(searchQuery)
            let emailMatch = user.email.lowercased().contains(searchQuery)

            return displayNameMatch || emailMatch
        }

        print("[FirestoreService] Search found \(results.count) matching users")
        return results
    }

    private func parseUserFromDict(_ dict: [String: Any]) -> User? {
        guard let id = dict["id"] as? String else { return nil }

        return User(
            id: id,
            email: dict["email"] as? String ?? "",
            displayName: dict["displayName"] as? String ?? "",
            isAdmin: dict["isAdmin"] as? Bool ?? false,
            invitedBy: dict["invitedBy"] as? String,
            canInvite: dict["canInvite"] as? Bool ?? false,
            avatarURL: dict["avatarURL"] as? String,
            avatarData: dict["avatarData"] as? String,
            isOnline: dict["isOnline"] as? Bool ?? false,
            lastSeen: dict["lastSeen"] as? Date,
            createdAt: dict["createdAt"] as? Date ?? Date()
        )
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
        guard let session = AuthTokenStorage.shared.loadSession() else {
            throw FirestoreREST.FirestoreError.notAuthenticated
        }

        let sortedParticipants = participants.sorted()
        print("[FirestoreService] Creating conversation for participants: \(sortedParticipants)")

        // Check if conversation already exists between these participants (via REST)
        if let existingConversation = try await findExistingConversationREST(participants: sortedParticipants, idToken: session.idToken) {
            print("[FirestoreService] Found existing conversation: \(existingConversation.id ?? "no-id")")
            return existingConversation
        }

        // Create new conversation via REST API
        let fields: [String: Any] = [
            "participants": sortedParticipants,
            "createdAt": Date(),
            "lastMessageAt": Date()
        ]

        let docId = try await FirestoreREST.shared.createDocument(
            collection: "conversations",
            documentId: nil,
            fields: fields,
            idToken: session.idToken
        )

        print("[FirestoreService] Created new conversation: \(docId)")

        return Conversation(
            id: docId,
            participants: sortedParticipants,
            createdAt: Date()
        )
    }

    private func findExistingConversationREST(participants: [String], idToken: String) async throws -> Conversation? {
        let results = try await FirestoreREST.shared.queryDocuments(
            collection: "conversations",
            field: "participants",
            values: participants,
            idToken: idToken
        )

        guard let first = results.first else { return nil }

        return Conversation(
            id: first["id"] as? String,
            participants: first["participants"] as? [String] ?? participants,
            lastMessage: first["lastMessage"] as? String,
            lastMessageAt: first["lastMessageAt"] as? Date,
            lastMessageSenderId: first["lastMessageSenderId"] as? String,
            createdAt: first["createdAt"] as? Date ?? Date()
        )
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
        guard let session = AuthTokenStorage.shared.loadSession() else {
            throw FirestoreREST.FirestoreError.notAuthenticated
        }

        try await FirestoreREST.shared.updateDocument(
            collection: "conversations",
            documentId: conversationId,
            fields: [
                "lastMessage": message,
                "lastMessageAt": Date(),
                "lastMessageSenderId": senderId
            ],
            idToken: session.idToken
        )
    }

    // MARK: - Messages

    func sendMessage(_ message: Message) async throws {
        guard let session = AuthTokenStorage.shared.loadSession() else {
            throw FirestoreREST.FirestoreError.notAuthenticated
        }

        print("[FirestoreService] Sending message to conversation: \(message.conversationId)")

        // Build message fields
        var fields: [String: Any] = [
            "conversationId": message.conversationId,
            "senderId": message.senderId,
            "content": message.content,
            "type": message.type.rawValue,
            "timestamp": message.timestamp,
            "isRead": message.isRead
        ]

        if let gifUrl = message.gifUrl {
            fields["gifUrl"] = gifUrl
        }
        if let stickerName = message.stickerName {
            fields["stickerName"] = stickerName
        }
        if let replyToId = message.replyToId {
            fields["replyToId"] = replyToId
        }
        if let replyToContent = message.replyToContent {
            fields["replyToContent"] = replyToContent
        }
        if let replyToSenderId = message.replyToSenderId {
            fields["replyToSenderId"] = replyToSenderId
        }

        // Create message document in subcollection via REST
        let messageId = try await FirestoreREST.shared.createDocument(
            collection: "conversations/\(message.conversationId)/messages",
            documentId: nil,
            fields: fields,
            idToken: session.idToken
        )

        print("[FirestoreService] Message created with ID: \(messageId)")

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
