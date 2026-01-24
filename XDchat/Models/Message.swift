import Foundation
@preconcurrency import FirebaseFirestore

enum MessageType: String, Codable, Sendable {
    case text
    case gif
    case sticker
    case emoji
}

struct Message: Identifiable, Codable, Equatable, Sendable {
    @DocumentID var id: String?
    let conversationId: String
    let senderId: String
    let content: String
    let type: MessageType
    var gifUrl: String?
    var stickerName: String?
    var replyToId: String?
    var replyToContent: String?
    var replyToSenderId: String?
    let timestamp: Date
    var isRead: Bool

    init(
        id: String? = nil,
        conversationId: String,
        senderId: String,
        content: String,
        type: MessageType = .text,
        gifUrl: String? = nil,
        stickerName: String? = nil,
        replyToId: String? = nil,
        replyToContent: String? = nil,
        replyToSenderId: String? = nil,
        timestamp: Date = Date(),
        isRead: Bool = false
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.content = content
        self.type = type
        self.gifUrl = gifUrl
        self.stickerName = stickerName
        self.replyToId = replyToId
        self.replyToContent = replyToContent
        self.replyToSenderId = replyToSenderId
        self.timestamp = timestamp
        self.isRead = isRead
    }
}

extension Message {
    var isTextMessage: Bool { type == .text }
    var isGifMessage: Bool { type == .gif }
    var isStickerMessage: Bool { type == .sticker }
    var isEmojiMessage: Bool { type == .emoji }
}
