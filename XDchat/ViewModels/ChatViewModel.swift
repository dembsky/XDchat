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
    @Published var isLoadingOlder = false
    @Published var hasMoreMessages = true

    let conversation: Conversation

    private let firestoreService = FirestoreService.shared
    private let authService = AuthService.shared
    private var messagesListenerId: String?
    private var conversationListenerId: String?
    private var typingDebounceTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var olderMessages: [Message] = []
    private var listenerMessages: [Message] = []

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

        // Listen to most recent messages (with limit for performance)
        messagesListenerId = firestoreService.listenToMessages(
            for: conversationId,
            limit: Constants.Pagination.defaultMessageLimit
        ) { [weak self] messages in
            Task { @MainActor in
                guard let self = self else { return }
                self.listenerMessages = messages
                self.mergeMessages()
            }
        }

        // Listen to conversation for typing indicator
        listenToTypingStatus()
    }

    private func mergeMessages() {
        // Combine older (paginated) messages with listener messages
        // Listener messages are the most recent, older messages are historical
        var combined = olderMessages

        // Add listener messages that aren't already in older messages
        for msg in listenerMessages {
            if !combined.contains(where: { $0.id == msg.id }) {
                combined.append(msg)
            }
        }

        // Sort by timestamp (oldest first)
        combined.sort { $0.timestamp < $1.timestamp }
        messages = combined
    }

    func loadOlderMessages() async {
        guard let conversationId = conversationId,
              !isLoadingOlder,
              hasMoreMessages else { return }

        // Get the oldest message timestamp from our current messages
        guard let oldestTimestamp = messages.first?.timestamp else { return }

        isLoadingOlder = true
        defer { isLoadingOlder = false }

        do {
            let older = try await firestoreService.getOlderMessages(
                for: conversationId,
                before: oldestTimestamp,
                limit: Constants.Pagination.defaultMessageLimit
            )

            if older.isEmpty {
                hasMoreMessages = false
            } else {
                // Prepend older messages
                olderMessages = older + olderMessages
                mergeMessages()
            }
        } catch {
            errorMessage = "Failed to load older messages"
        }
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

        // Reset pagination state
        olderMessages = []
        listenerMessages = []
        hasMoreMessages = true

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
