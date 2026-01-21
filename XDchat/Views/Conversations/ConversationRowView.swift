import SwiftUI

struct ConversationRowView: View {
    let conversation: Conversation
    let otherUser: User?
    let currentUserId: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Avatar
            avatarView

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(displayName)
                        .font(Theme.Typography.body)
                        .fontWeight(hasUnread ? .semibold : .medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    if let lastMessageAt = conversation.lastMessageAt {
                        Text(lastMessageAt.timeAgoDisplay())
                            .font(Theme.Typography.footnote)
                            .foregroundColor(hasUnread ? Theme.Colors.accent : .secondary)
                    }
                }

                HStack {
                    if conversation.lastMessage != nil {
                        Text(lastMessagePreview)
                            .font(Theme.Typography.callout)
                            .foregroundColor(hasUnread ? .primary : .secondary)
                            .lineLimit(1)
                    } else {
                        Text("No messages yet")
                            .font(Theme.Typography.callout)
                            .foregroundColor(.secondary)
                            .italic()
                    }

                    Spacer()

                    // Unread badge
                    if hasUnread {
                        unreadBadge
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }

    // MARK: - Avatar

    private var avatarView: some View {
        ZStack {
            if let avatarBase64 = otherUser?.avatarData,
               let avatarData = Data(base64Encoded: avatarBase64) {
                ProfileAvatarView(
                    imageData: avatarData,
                    initials: initials,
                    size: 50
                )
            } else {
                Circle()
                    .fill(Theme.messengerGradient)
                    .frame(width: 50, height: 50)

                Text(initials)
                    .font(Theme.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }

            // Online indicator
            if otherUser?.isOnline == true {
                Circle()
                    .fill(Theme.Colors.online)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(Color(.windowBackgroundColor), lineWidth: 2)
                    )
                    .offset(x: 18, y: 18)
            }
        }
    }

    // MARK: - Unread Badge

    private var unreadBadge: some View {
        let count = conversation.unreadCountFor(userId: currentUserId)
        return Text(count > 99 ? "99+" : "\(count)")
            .font(Theme.Typography.footnote)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.Colors.accent)
            .clipShape(Capsule())
    }

    // MARK: - Computed Properties

    private var displayName: String {
        otherUser?.displayName ?? "Unknown"
    }

    private var initials: String {
        otherUser?.initials ?? "?"
    }

    private var hasUnread: Bool {
        conversation.unreadCountFor(userId: currentUserId) > 0
    }

    private var lastMessagePreview: String {
        guard let lastMessage = conversation.lastMessage else { return "" }

        // Check if current user sent it
        if conversation.lastMessageSenderId == currentUserId {
            return "You: \(lastMessage)"
        }

        return lastMessage
    }
}

// MARK: - Preview

struct ConversationRowView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            ConversationRowView(
                conversation: Conversation(
                    id: "1",
                    participants: ["user1", "user2"],
                    lastMessage: "Hey, how are you?",
                    lastMessageAt: Date(),
                    lastMessageSenderId: "user2",
                    unreadCount: ["user1": 3]
                ),
                otherUser: User(
                    id: "user2",
                    email: "john@example.com",
                    displayName: "John Doe",
                    isOnline: true
                ),
                currentUserId: "user1",
                isSelected: false
            )

            Divider()

            ConversationRowView(
                conversation: Conversation(
                    id: "2",
                    participants: ["user1", "user3"],
                    lastMessage: "Thanks for the help!",
                    lastMessageAt: Date().addingTimeInterval(-3600),
                    lastMessageSenderId: "user1"
                ),
                otherUser: User(
                    id: "user3",
                    email: "jane@example.com",
                    displayName: "Jane Smith",
                    isOnline: false
                ),
                currentUserId: "user1",
                isSelected: true
            )
        }
        .frame(width: 320)
    }
}
