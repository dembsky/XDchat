import Foundation
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var messageText = ""
    @Published var isLoading = false
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var showGiphyPicker = false
    @Published var showEmojiPicker = false
    @Published var otherUserIsTyping = false

    let conversation: Conversation

    private let firestoreService = FirestoreService.shared
    private let authService = AuthService.shared
    private var messagesListenerId: String?
    private var conversationListenerId: String?
    private var typingDebounceTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var currentUserId: String? {
        authService.currentUser?.id
    }

    var conversationId: String? {
        conversation.id
    }

    init(conversation: Conversation) {
        self.conversation = conversation
        setupTypingDebounce()
    }

    nonisolated func cleanup() {
        // Called when view disappears - cleanup is handled by stopListening()
        // This is nonisolated to work properly with Swift concurrency
    }

    // MARK: - Setup

    private func setupTypingDebounce() {
        $messageText
            .debounce(for: .milliseconds(Constants.TimeIntervals.typingDebounceMilliseconds), scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self = self else { return }
                Task {
                    await self.updateTypingStatus(isTyping: !text.isEmpty)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Messages

    func startListening() {
        guard let conversationId = conversationId else { return }

        // Listen to messages
        messagesListenerId = firestoreService.listenToMessages(for: conversationId) { [weak self] messages in
            Task { @MainActor in
                self?.messages = messages
            }
        }

        // Listen to conversation for typing indicator
        listenToTypingStatus()
    }

    func stopListening() {
        if let listenerId = messagesListenerId {
            firestoreService.removeListener(id: listenerId)
            messagesListenerId = nil
        }
        if let listenerId = conversationListenerId {
            firestoreService.removeListener(id: listenerId)
            conversationListenerId = nil
        }

        // Clear typing status
        Task {
            await updateTypingStatus(isTyping: false)
        }
    }

    private func listenToTypingStatus() {
        guard let conversationId = conversationId,
              let currentUserId = currentUserId else { return }

        conversationListenerId = firestoreService.listenToConversations(for: currentUserId) { [weak self] conversations in
            guard let self = self else { return }

            Task { @MainActor in
                if let updatedConversation = conversations.first(where: { $0.id == conversationId }) {
                    let typingUsers = updatedConversation.typingUsers.filter { $0 != currentUserId }
                    self.otherUserIsTyping = !typingUsers.isEmpty
                }
            }
        }
    }

    // MARK: - Send Message

    func sendTextMessage(
        replyToId: String? = nil,
        replyToContent: String? = nil,
        replyToSenderId: String? = nil
    ) async {
        // Convert emoticons to emoji (e.g., :D → 😄)
        let text = messageText.trimmed.withEmoji

        guard !text.isEmpty,
              let conversationId = conversationId,
              let senderId = currentUserId else { return }

        // Validate message length
        let maxLength = 10000
        guard text.count <= maxLength else {
            errorMessage = "Message is too long (max \(maxLength) characters)"
            return
        }

        let tempText = text
        messageText = ""

        isSending = true
        defer { isSending = false }

        // Determine message type
        let messageType: MessageType = text.containsOnlyEmoji && text.count <= 8 ? .emoji : .text

        let message = Message(
            conversationId: conversationId,
            senderId: senderId,
            content: tempText,
            type: messageType,
            replyToId: replyToId,
            replyToContent: replyToContent,
            replyToSenderId: replyToSenderId
        )

        do {
            try await firestoreService.sendMessage(message)
            await updateTypingStatus(isTyping: false)
        } catch {
            errorMessage = error.localizedDescription
            messageText = tempText // Restore text on failure
        }
    }

    func sendGif(_ gif: GiphyImage) async {
        guard let conversationId = conversationId,
              let senderId = currentUserId else { return }

        showGiphyPicker = false
        isSending = true
        defer { isSending = false }

        let message = Message(
            conversationId: conversationId,
            senderId: senderId,
            content: gif.title,
            type: .gif,
            gifUrl: gif.url.absoluteString
        )

        do {
            try await firestoreService.sendMessage(message)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendSticker(name: String, url: String) async {
        guard let conversationId = conversationId,
              let senderId = currentUserId else { return }

        isSending = true
        defer { isSending = false }

        let message = Message(
            conversationId: conversationId,
            senderId: senderId,
            content: name,
            type: .sticker,
            stickerName: name
        )

        do {
            try await firestoreService.sendMessage(message)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Typing Indicator

    private func updateTypingStatus(isTyping: Bool) async {
        guard let conversationId = conversationId,
              let userId = currentUserId else { return }

        typingDebounceTask?.cancel()

        do {
            try await firestoreService.setTypingStatus(
                conversationId: conversationId,
                userId: userId,
                isTyping: isTyping
            )

            // Auto-clear typing after timeout
            if isTyping {
                typingDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: Constants.TimeIntervals.typingAutoClearNanoseconds)
                    if !Task.isCancelled {
                        try? await firestoreService.setTypingStatus(
                            conversationId: conversationId,
                            userId: userId,
                            isTyping: false
                        )
                    }
                }
            }
        } catch {
            // Silently handle typing status errors
        }
    }

    // MARK: - Helpers

    func isFromCurrentUser(_ message: Message) -> Bool {
        message.senderId == currentUserId
    }

    func shouldShowTimestamp(for index: Int) -> Bool {
        guard index > 0 else { return true }

        let currentMessage = messages[index]
        let previousMessage = messages[index - 1]

        let timeDifference = currentMessage.timestamp.timeIntervalSince(previousMessage.timestamp)
        return timeDifference > Constants.TimeIntervals.timestampDisplayThreshold
    }

    func shouldShowAvatar(for index: Int) -> Bool {
        guard index < messages.count - 1 else { return true }

        let currentMessage = messages[index]
        let nextMessage = messages[index + 1]

        return currentMessage.senderId != nextMessage.senderId
    }

    func shouldShowMessageTimestamp(for index: Int) -> Bool {
        guard index < messages.count - 1 else { return true }

        let currentMessage = messages[index]
        let nextMessage = messages[index + 1]

        // Show timestamp if next message is from a different sender
        if currentMessage.senderId != nextMessage.senderId {
            return true
        }

        // Show timestamp if next message is in a different minute
        let currentMinute = Calendar.current.component(.minute, from: currentMessage.timestamp)
        let nextMinute = Calendar.current.component(.minute, from: nextMessage.timestamp)
        let currentHour = Calendar.current.component(.hour, from: currentMessage.timestamp)
        let nextHour = Calendar.current.component(.hour, from: nextMessage.timestamp)

        return currentMinute != nextMinute || currentHour != nextHour
    }
}
