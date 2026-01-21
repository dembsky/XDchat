import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var authService = AuthService.shared

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 500)
        .onAppear {
            viewModel.loadProfileImage()
            viewModel.applyAppIcon()
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            profilePhotoSection
            appearanceSection
            appIconSection
            quickReactionsSection
            notificationsSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Profile Photo Section

    private var profilePhotoSection: some View {
        Section("Profile Photo") {
            HStack(spacing: Theme.Spacing.lg) {
                ZStack {
                    if let image = viewModel.profileImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Theme.Colors.accent)
                            .frame(width: 80, height: 80)

                        Text(authService.currentUser?.initials ?? "?")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Button("Change Photo") {
                        viewModel.selectProfileImage()
                    }

                    if viewModel.profileImage != nil {
                        Button("Remove Photo") {
                            viewModel.removeProfileImage()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $themeManager.selectedTheme) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - App Icon Section

    private var appIconSection: some View {
        Section("App Icon") {
            HStack(spacing: Theme.Spacing.xl) {
                appIconOption(style: "light", label: "Light")
                appIconOption(style: "dark", label: "Dark")
            }
            .padding(.vertical, Theme.Spacing.sm)

            Text("Changes the app icon in Dock")
                .font(Theme.Typography.caption)
                .foregroundColor(.secondary)
        }
    }

    private func appIconOption(style: String, label: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image("\(style == "dark" ? "AppIconDarkPreview" : "AppIconLightPreview")")
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(viewModel.appIconStyle == style ? Theme.Colors.accent : Color.clear, lineWidth: 3)
                )
                .onTapGesture {
                    viewModel.setAppIcon(style: style)
                }

            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(viewModel.appIconStyle == style ? Theme.Colors.accent : .secondary)
        }
    }

    // MARK: - Quick Reactions Section

    private var quickReactionsSection: some View {
        Section("Quick Reactions") {
            HStack(spacing: Theme.Spacing.md) {
                ForEach(Array(viewModel.quickEmojis.enumerated()), id: \.offset) { index, emoji in
                    emojiButton(emoji: emoji, index: index)
                }

                if viewModel.quickEmojis.count < 3 {
                    addEmojiButton
                }
            }
            .padding(.vertical, Theme.Spacing.xs)

            Text("Click + and select an emoji from the picker. Max 3 emojis.")
                .font(.caption)
                .foregroundColor(.secondary)

            emojiTextField
        }
    }

    private func emojiButton(emoji: String, index: Int) -> some View {
        Text(emoji)
            .font(.system(size: 28))
            .frame(width: 44, height: 44)
            .background(Color(.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                Button {
                    viewModel.removeEmoji(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .offset(x: 16, y: -16),
                alignment: .topTrailing
            )
    }

    private var addEmojiButton: some View {
        Button {
            NSApp.orderFrontCharacterPalette(nil)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20))
                .foregroundColor(.secondary)
                .frame(width: 44, height: 44)
                .background(Color(.textBackgroundColor))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var emojiTextField: some View {
        TextField("Add emoji", text: Binding(
            get: { "" },
            set: { newValue in
                guard !newValue.isEmpty else { return }
                let emoji = String(newValue.prefix(2))
                viewModel.addEmoji(emoji)
            }
        ))
        .textFieldStyle(.roundedBorder)
        .labelsHidden()
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Show notifications for new messages", isOn: .constant(true))
            Toggle("Play sound for new messages", isOn: .constant(true))
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image("AppIconLightPreview")
                .resizable()
                .interpolation(.high)
                .frame(width: 128, height: 128)
                .cornerRadius(28)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

            Text("XDchat")
                .font(Theme.Typography.largeTitle)
                .fontWeight(.bold)

            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(Theme.Typography.callout)
                .foregroundColor(.secondary)

            Text("A native macOS chat application")
                .font(Theme.Typography.caption)
                .foregroundColor(.secondary)

            Spacer()
                .frame(height: 20)

            Text("This fabulous app was created because Zuckerberg\nis a big pile of shit and he deleted the Messenger app.")
                .font(Theme.Typography.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .italic()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
}
