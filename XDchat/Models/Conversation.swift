import Foundation
import FirebaseFirestore

struct Conversation: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    let participants: [String]
    var lastMessage: String?
    var lastMessageAt: Date?
    var lastMessageSenderId: String?
    let createdAt: Date
    var unreadCount: [String: Int]
    var typingUsers: [String]

    init(
        id: String? = nil,
        participants: [String],
        lastMessage: String? = nil,
        lastMessageAt: Date? = nil,
        lastMessageSenderId: String? = nil,
        createdAt: Date = Date(),
        unreadCount: [String: Int] = [:],
        typingUsers: [String] = []
    ) {
        self.id = id
        self.participants = participants
        self.lastMessage = lastMessage
        self.lastMessageAt = lastMessageAt
        self.lastMessageSenderId = lastMessageSenderId
        self.createdAt = createdAt
        self.unreadCount = unreadCount
        self.typingUsers = typingUsers
    }

    func otherParticipantId(currentUserId: String) -> String? {
        participants.first { $0 != currentUserId }
    }

    func unreadCountFor(userId: String) -> Int {
        unreadCount[userId] ?? 0
    }

    var isGroup: Bool {
        participants.count > 2
    }
}
