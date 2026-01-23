import SwiftUI

struct MessageInputView: View {
    @Binding var text: String
    @Binding var showGiphyPicker: Bool
    @Binding var showEmojiPicker: Bool
    let isSending: Bool
    let onSend: () -> Void

    @AppStorage("quickEmojis") private var quickEmojisData: Data = {
        let defaultEmojis = ["👍", "❤️", "😂"]
        return (try? JSONEncoder().encode(defaultEmojis)) ?? Data()
    }()

    @FocusState private var isFocused: Bool

    private var quickEmojis: [String] {
        (try? JSONDecoder().decode([String].self, from: quickEmojisData)) ?? ["👍", "❤️", "😂"]
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.md) {
            // Attachment buttons - fixed at bottom
            HStack(spacing: Theme.Spacing.sm) {
                // GIF button
                Button {
                    showGiphyPicker = true
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20))
                        .foregroundColor(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
                .help("Send a GIF")

                // Emoji button (opens system emoji picker)
                Button {
                    isFocused = true  // Focus text field first so emoji gets inserted there
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        NSApp.orderFrontCharacterPalette(nil)
                    }
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 20))
                        .foregroundColor(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
                .help("Emoji")
            }
            .padding(.bottom, 6)  // Align with text field baseline

            // Text input
            HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                TextField("Aa", text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit {
                        if !text.trimmed.isEmpty {
                            onSend()
                        }
                    }
                    .onChange(of: text) { oldValue, newValue in
                        // Auto-send if emoji was inserted from picker
                        // Works when: empty field + only emoji inserted OR new emoji added to empty field
                        let trimmedNew = newValue.trimmed
                        let trimmedOld = oldValue.trimmed

                        if trimmedOld.isEmpty && !trimmedNew.isEmpty && trimmedNew.containsOnlyEmoji {
                            // Small delay to ensure text is set properly
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                if !text.trimmed.isEmpty {
                                    onSend()
                                }
                            }
                        }
                    }

                // Send button inside text field
                if !text.trimmed.isEmpty {
                    Button(action: onSend) {
                        if isSending {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(Theme.Colors.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Color(.textBackgroundColor))
            .cornerRadius(20)

            // Quick emoji reactions when no text
            if text.trimmed.isEmpty {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(quickEmojis.prefix(3), id: \.self) { emoji in
                        quickEmojiButton(emoji)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .animation(Theme.Animation.quick, value: text.isEmpty)
    }

    private func quickEmojiButton(_ emoji: String) -> some View {
        Button {
            text = emoji
            onSend()
        } label: {
            Text(emoji)
                .font(.system(size: 24))
        }
        .buttonStyle(.plain)
        .help("Send \(emoji)")
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()

        MessageInputView(
            text: .constant(""),
            showGiphyPicker: .constant(false),
            showEmojiPicker: .constant(false),
            isSending: false,
            onSend: {}
        )

        Divider()

        MessageInputView(
            text: .constant("Hello, this is a message!"),
            showGiphyPicker: .constant(false),
            showEmojiPicker: .constant(false),
            isSending: false,
            onSend: {}
        )
    }
    .frame(width: 500, height: 200)
}
