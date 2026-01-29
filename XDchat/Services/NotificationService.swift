import Foundation
import UserNotifications
import AppKit
import os.log

@MainActor
class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    @Published private(set) var isAuthorized = false
    @Published private(set) var authorizationError: Error?
    /// Conversation ID from a notification tap that arrived before the UI was ready
    @Published var pendingConversationId: String?

    private let notificationCenter = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        // Note: UNUserNotificationCenter.delegate is a weak reference, no retain cycle
        notificationCenter.delegate = self
        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    /// Request notification authorization. Returns true if granted.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            authorizationError = nil
            return granted
        } catch {
            Logger.notifications.error("Authorization failed: \(error.localizedDescription)")
            authorizationError = error
            isAuthorized = false
            return false
        }
    }

    /// Check current authorization status
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Show Notification

    func showNotification(
        title: String,
        body: String,
        conversationId: String? = nil,
        sound: Bool = true
    ) {
        guard isAuthorized else {
            Logger.notifications.debug("Notification skipped: not authorized")
            return
        }
        guard !NSApp.isActive else {
            Logger.notifications.debug("Notification skipped: app is active")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        if sound {
            content.sound = .default
        }

        if let conversationId = conversationId {
            content.userInfo = ["conversationId": conversationId]
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        notificationCenter.add(request) { error in
            if let error = error {
                Logger.notifications.error("Failed to show notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Badge

    func setBadgeCount(_ count: Int) async {
        do {
            try await notificationCenter.setBadgeCount(count)
        } catch {
            Logger.notifications.error("Failed to set badge: \(error.localizedDescription)")
        }
    }

    func clearBadge() async {
        await setBadgeCount(0)
    }

    // MARK: - Clear Notifications

    func clearAllNotifications() {
        notificationCenter.removeAllDeliveredNotifications()
        notificationCenter.removeAllPendingNotificationRequests()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Don't show banner if app is active - we're already in the app
        return []
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Extract conversationId from the notification payload on the current thread
        // (userInfo is Sendable-safe dictionary)
        let conversationId = response.notification.request.content.userInfo["conversationId"] as? String

        // All MainActor-isolated work inside a single block
        await MainActor.run { [conversationId] in
            NSApp.activate()

            guard let conversationId else { return }

            // Store as pending in case the UI is not yet ready (cold launch)
            NotificationService.shared.pendingConversationId = conversationId

            NotificationCenter.default.post(
                name: Constants.Notifications.openConversation,
                object: nil,
                userInfo: ["conversationId": conversationId]
            )
        }
    }
}
