import Foundation
import os.log

// MARK: - Logging

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.xdchat.app"

    static let auth = Logger(subsystem: subsystem, category: "Auth")
    static let firestore = Logger(subsystem: subsystem, category: "Firestore")
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    static let conversations = Logger(subsystem: subsystem, category: "Conversations")
}

// MARK: - Constants

enum Constants {
    // MARK: - Time Intervals

    enum TimeIntervals {
        /// Time threshold for showing timestamp between messages (5 minutes)
        static let timestampDisplayThreshold: TimeInterval = 300

        /// Debounce delay for search queries (300ms)
        static let searchDebounceMilliseconds: Int = 300

        /// Debounce delay for typing indicator (500ms)
        static let typingDebounceMilliseconds: Int = 500

        /// Auto-clear typing status after this duration (5 seconds)
        static let typingAutoClearNanoseconds: UInt64 = 5_000_000_000
    }

    // MARK: - Pagination

    enum Pagination {
        /// Default message fetch limit
        static let defaultMessageLimit: Int = 50

        /// Default user search limit
        static let defaultUserLimit: Int = 50

        /// GIF fetch limit
        static let defaultGifLimit: Int = 25
    }

    // MARK: - Validation

    enum Validation {
        /// Minimum password length
        static let minimumPasswordLength: Int = 6

        /// Maximum emoji count in quick reactions
        static let maxQuickEmojis: Int = 3

        /// Maximum emoji character count for emoji-only messages
        static let maxEmojiMessageLength: Int = 8

        /// Maximum message content length
        static let maxMessageLength: Int = 10_000

        /// Maximum notification preview length
        static let maxNotificationPreviewLength: Int = 100

        /// Invitation code length
        static let invitationCodeLength: Int = 6

        /// Maximum pending notification tasks before eviction
        static let maxPendingNotificationTasks: Int = 50
    }

    // MARK: - UI

    enum UI {
        /// Profile avatar sizes
        static let smallAvatarSize: CGFloat = 28
        static let mediumAvatarSize: CGFloat = 40
        static let largeAvatarSize: CGFloat = 80

        /// Window sizes
        static let minWindowWidth: CGFloat = 800
        static let minWindowHeight: CGFloat = 500
        static let defaultWindowWidth: CGFloat = 1100
        static let defaultWindowHeight: CGFloat = 700

        /// Settings window
        static let settingsWidth: CGFloat = 450
        static let settingsHeight: CGFloat = 500

        /// Sidebar
        static let sidebarMinWidth: CGFloat = 280
        static let sidebarIdealWidth: CGFloat = 320
        static let sidebarMaxWidth: CGFloat = 400
    }

    // MARK: - Firebase Collections

    enum Collections {
        static let users = "users"
        static let conversations = "conversations"
        static let messages = "messages"
        static let invitations = "invitations"
        static let appMeta = "app_meta"
    }

    // MARK: - Notification Names

    enum Notifications {
        static let newConversation = Notification.Name("newConversation")
        static let focusSearch = Notification.Name("focusSearch")
        static let showInviteUsers = Notification.Name("showInviteUsers")
        static let openConversation = Notification.Name("openConversation")
    }

    // MARK: - Storage Keys

    enum StorageKeys {
        static let appIconStyle = "appIconStyle"
        static let profileImageData = "profileImageData"
        static let quickEmojis = "quickEmojis"
        static let selectedTheme = "selectedTheme"
        static let wasAuthenticated = "wasAuthenticated"
        static let notificationsEnabled = "notificationsEnabled"
        static let soundEnabled = "soundEnabled"
        static let badgeEnabled = "badgeEnabled"
    }
}
