import SwiftUI
import FirebaseCore
import FirebaseFirestore
import UniformTypeIdentifiers
import Sparkle

@main
struct XDchatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainView()
                .frame(
                    minWidth: Constants.UI.minWindowWidth,
                    minHeight: Constants.UI.minWindowHeight
                )
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(
            width: Constants.UI.defaultWindowWidth,
            height: Constants.UI.defaultWindowHeight
        )
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandMenu("Chat") {
                Button("New Conversation") {
                    NotificationCenter.default.post(
                        name: Constants.Notifications.newConversation,
                        object: nil
                    )
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("Search") {
                    NotificationCenter.default.post(
                        name: Constants.Notifications.focusSearch,
                        object: nil
                    )
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: appDelegate.updaterController.updater)
            }

            CommandGroup(after: .appSettings) {
                Button("Invite Users...") {
                    NotificationCenter.default.post(
                        name: Constants.Notifications.showInviteUsers,
                        object: nil
                    )
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController: SPUStandardUpdaterController

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Firebase is configured in AuthService.shared
        configureFirestore()
        applyAppIcon()
        registerNotificationDefaults()
        initializeNotifications()
    }

    private func registerNotificationDefaults() {
        UserDefaults.standard.register(defaults: [
            Constants.StorageKeys.notificationsEnabled: true,
            Constants.StorageKeys.soundEnabled: true,
            Constants.StorageKeys.badgeEnabled: true
        ])
    }

    private func initializeNotifications() {
        Task {
            if UserDefaults.standard.bool(forKey: Constants.StorageKeys.notificationsEnabled) {
                await NotificationService.shared.requestAuthorization()
            }
        }
    }

    private func configureFirestore() {
        let settings = FirestoreSettings()

        // Enable offline persistence with 100 MB cache
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: 100 * 1024 * 1024 as NSNumber)

        Firestore.firestore().settings = settings
    }

    private func applyAppIcon() {
        let appIconStyle = UserDefaults.standard.string(forKey: Constants.StorageKeys.appIconStyle) ?? "light"
        let iconName = appIconStyle == "dark" ? "AppIconDarkPreview" : "AppIconLightPreview"
        if let icon = NSImage(named: iconName) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NotificationService.shared.clearAllNotifications()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AuthService.shared.updateOnlineStatusSync(false)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Reopen main window when clicking dock icon
            for window in sender.windows {
                if window.canBecomeMain {
                    window.makeKeyAndOrderFront(self)
                    return true
                }
            }
        }
        return true
    }
}

// MARK: - Sparkle Update View

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @StateObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self._viewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}

