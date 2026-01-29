import SwiftUI
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    @AppStorage(Constants.StorageKeys.quickEmojis) private var quickEmojisData: Data = {
        let defaultEmojis = ["👍", "❤️", "😂"]
        return (try? JSONEncoder().encode(defaultEmojis)) ?? Data()
    }()
    @AppStorage(Constants.StorageKeys.profileImageData) private var profileImageData: Data = Data()
    @AppStorage(Constants.StorageKeys.appIconStyle) var appIconStyle: String = "light"
    @AppStorage(Constants.StorageKeys.notificationsEnabled) var notificationsEnabled: Bool = true
    @AppStorage(Constants.StorageKeys.soundEnabled) var soundEnabled: Bool = true
    @AppStorage(Constants.StorageKeys.badgeEnabled) var badgeEnabled: Bool = true

    @Published var profileImage: NSImage?

    private let authService = AuthService.shared

    var quickEmojis: [String] {
        (try? JSONDecoder().decode([String].self, from: quickEmojisData)) ?? ["👍", "❤️", "😂"]
    }

    // MARK: - Profile Image

    func loadProfileImage() {
        // First try to load from local storage
        if !profileImageData.isEmpty {
            profileImage = NSImage(data: profileImageData)
            return
        }

        // If local storage is empty, try to load from Firestore
        if let avatarBase64 = authService.currentUser?.avatarData,
           let data = Data(base64Encoded: avatarBase64),
           let image = NSImage(data: data) {
            profileImageData = data
            profileImage = image
        }
    }

    func selectProfileImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        panel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let url = panel.url {
                if let image = NSImage(contentsOf: url) {
                    Task { @MainActor in
                        self.openCropperWindow(with: image)
                    }
                }
            }
        }
    }

    private func openCropperWindow(with image: NSImage) {
        let cropperView = ProfilePhotoCropperView(
            image: image,
            onSave: { [weak self] data in
                self?.saveProfileImage(data)
                NSApp.keyWindow?.close()
            },
            onCancel: {
                NSApp.keyWindow?.close()
            }
        )

        let hostingController = NSHostingController(rootView: cropperView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Crop Profile Photo"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 320, height: 420))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func saveProfileImage(_ data: Data) {
        profileImageData = data
        profileImage = NSImage(data: data)

        Task {
            await uploadProfileImage(data)
        }
    }

    @Published var uploadError: String?

    private func uploadProfileImage(_ data: Data) async {
        let base64String = data.base64EncodedString()
        guard let userId = authService.currentUser?.id else { return }

        do {
            try await FirestoreService.shared.updateUserAvatar(userId: userId, avatarData: base64String)
        } catch {
            self.uploadError = "Failed to upload profile image"
        }
    }

    func removeProfileImage() {
        profileImageData = Data()
        profileImage = nil
    }

    // MARK: - App Icon

    func applyAppIcon() {
        let iconName = appIconStyle == "dark" ? "AppIconDarkPreview" : "AppIconLightPreview"
        if let icon = NSImage(named: iconName) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    func setAppIcon(style: String) {
        appIconStyle = style
        applyAppIcon()
    }

    // MARK: - Quick Emojis

    private func setQuickEmojis(_ emojis: [String]) {
        if let data = try? JSONEncoder().encode(emojis) {
            quickEmojisData = data
        }
    }

    func addEmoji(_ emoji: String) {
        guard emoji.containsOnlyEmoji,
              quickEmojis.count < 3,
              !quickEmojis.contains(emoji) else { return }

        var emojis = quickEmojis
        emojis.append(emoji)
        setQuickEmojis(emojis)
    }

    func removeEmoji(at index: Int) {
        var emojis = quickEmojis
        guard index < emojis.count else { return }
        emojis.remove(at: index)
        setQuickEmojis(emojis)
    }
}
