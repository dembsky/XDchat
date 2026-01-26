import SwiftUI
import SDWebImageSwiftUI

struct MessageBubbleView: View {
    let message: Message
    let isFromCurrentUser: Bool
    let showAvatar: Bool
    let senderUser: User?
    var isHighlighted: Bool = false
    var showTimestamp: Bool = true
    var onReply: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var shakeOffset: CGFloat = 0
    @State private var hasAnimated = false

    private var containsXD: Bool {
        let content = message.content.lowercased()
        return content.contains("xd")
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
            if isFromCurrentUser {
                Spacer(minLength: 60)
            } else {
                // Avatar for received messages
                if showAvatar {
                    avatarView
                } else {
                    Spacer()
                        .frame(width: 32)
                }
            }

            // Reply button + Message content (hover area)
            HStack(spacing: 4) {
                if isFromCurrentUser {
                    if isHovered, let onReply = onReply {
                        replyButton(action: onReply)
                    } else if onReply != nil {
                        // Invisible placeholder to prevent layout shift
                        Color.clear.frame(width: 32, height: 32)
                    }
                }

                messageContent
                    .modifier(ShakeEffect(shakes: shakeOffset))

                if !isFromCurrentUser {
                    if isHovered, let onReply = onReply {
                        replyButton(action: onReply)
                    } else if onReply != nil {
                        // Invisible placeholder to prevent layout shift
                        Color.clear.frame(width: 32, height: 32)
                    }
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }

            if !isFromCurrentUser {
                Spacer(minLength: 60)
            }
        }
        .padding(.vertical, isHighlighted ? 4 : 0)
        .background(isHighlighted ? Theme.Colors.accentLight.opacity(0.2) : Color.clear)
        .cornerRadius(8)
        .onAppear {
            if containsXD && !hasAnimated {
                hasAnimated = true
                withAnimation(.easeInOut(duration: 0.6)) {
                    shakeOffset = 6
                }
            }
        }
    }

    private func replyButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .padding(6)
                .background(Color(.textBackgroundColor))
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Avatar

    private var avatarView: some View {
        Group {
            if let avatarBase64 = senderUser?.avatarData,
               let avatarData = Data(base64Encoded: avatarBase64) {
                ProfileAvatarView(
                    imageData: avatarData,
                    initials: senderUser?.initials ?? "?",
                    size: 32
                )
            } else {
                ZStack {
                    Circle()
                        .fill(Theme.Colors.accent)
                        .frame(width: 32, height: 32)

                    Text(senderUser?.initials ?? "?")
                        .font(Theme.Typography.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - Message Content

    @ViewBuilder
    private var messageContent: some View {
        switch message.type {
        case .text:
            textBubble
        case .gif:
            gifBubble
        case .sticker:
            stickerBubble
        case .emoji:
            emojiBubble
        }
    }

    // MARK: - Text Bubble

    private var textBubble: some View {
        VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 0) {
                // Quoted message if exists
                if let replyContent = message.replyToContent {
                    HStack(spacing: Theme.Spacing.xs) {
                        Rectangle()
                            .fill(isFromCurrentUser ? Color.white.opacity(0.5) : Theme.Colors.accent.opacity(0.5))
                            .frame(width: 3)

                        Text(replyContent)
                            .font(Theme.Typography.caption)
                            .foregroundColor(isFromCurrentUser ? .white.opacity(0.8) : .secondary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                }

                Text(message.content)
                    .font(Theme.Typography.body)
                    .foregroundColor(isFromCurrentUser ? .white : .primary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
            }
            .background(bubbleBackground)
            .cornerRadius(Theme.CornerRadius.bubble, corners: bubbleCorners)

            if showTimestamp {
                Text(message.timestamp.messageTimestamp())
                    .font(Theme.Typography.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }

    // MARK: - GIF Bubble

    private var gifBubble: some View {
        VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 2) {
            if let urlString = message.gifUrl, let url = URL(string: urlString) {
                WebImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 200, height: 150)
                        .overlay(ProgressView())
                }
                .frame(maxWidth: 250, maxHeight: 250)
                .cornerRadius(Theme.CornerRadius.large)
                .applyShadow(Theme.Shadows.small)
            }

            if showTimestamp {
                Text(message.timestamp.messageTimestamp())
                    .font(Theme.Typography.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }

    // MARK: - Sticker Bubble

    private var stickerBubble: some View {
        VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 2) {
            // Placeholder for sticker - in real implementation, this would load the sticker image
            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(Color.clear)
                    .frame(width: 120, height: 120)

                Text(message.stickerName ?? "Sticker")
                    .font(.system(size: 60))
            }

            if showTimestamp {
                Text(message.timestamp.messageTimestamp())
                    .font(Theme.Typography.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }

    // MARK: - Emoji Bubble

    private var emojiBubble: some View {
        VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 2) {
            Text(message.content)
                .font(.system(size: message.content.count <= 3 ? 48 : 32))

            if showTimestamp {
                Text(message.timestamp.messageTimestamp())
                    .font(Theme.Typography.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var bubbleBackground: some View {
        if isFromCurrentUser {
            Theme.Colors.accent
        } else {
            Color(NSColor.unemphasizedSelectedContentBackgroundColor)
        }
    }

    private var bubbleCorners: RectCorner {
        if isFromCurrentUser {
            return showAvatar ? [.topLeft, .topRight, .bottomLeft] : .allCorners
        } else {
            return showAvatar ? [.topLeft, .topRight, .bottomRight] : .allCorners
        }
    }
}

// MARK: - Preview

struct MessageBubbleView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 8) {
            // Sent text message
            MessageBubbleView(
                message: Message(
                    id: "1",
                    conversationId: "conv1",
                    senderId: "user1",
                    content: "Hey, how are you?",
                    type: .text,
                    timestamp: Date()
                ),
                isFromCurrentUser: true,
                showAvatar: true,
                senderUser: nil
            )

            // Received text message
            MessageBubbleView(
                message: Message(
                    id: "2",
                    conversationId: "conv1",
                    senderId: "user2",
                    content: "I'm doing great, thanks for asking! How about you?",
                    type: .text,
                    timestamp: Date()
                ),
                isFromCurrentUser: false,
                showAvatar: true,
                senderUser: User(
                    id: "user2",
                    email: "john@example.com",
                    displayName: "John Doe"
                )
            )

            // Emoji message
            MessageBubbleView(
                message: Message(
                    id: "3",
                    conversationId: "conv1",
                    senderId: "user1",
                    content: "😄👍",
                    type: .emoji,
                    timestamp: Date()
                ),
                isFromCurrentUser: true,
                showAvatar: true,
                senderUser: nil
            )
        }
        .padding()
        .frame(width: 400)
    }
}
