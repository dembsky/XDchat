import SwiftUI
import FirebaseCore
import UniformTypeIdentifiers
import Sparkle

@main
struct XDchatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandMenu("Chat") {
                Button("New Conversation") {
                    NotificationCenter.default.post(
                        name: .newConversation,
                        object: nil
                    )
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("Search") {
                    NotificationCenter.default.post(
                        name: .focusSearch,
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
                        name: .showInviteUsers,
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
        FirebaseApp.configure()
        applyAppIcon()
    }

    private func applyAppIcon() {
        let appIconStyle = UserDefaults.standard.string(forKey: "appIconStyle") ?? "light"
        let iconName = appIconStyle == "dark" ? "AppIconDarkPreview" : "AppIconLightPreview"
        if let icon = NSImage(named: iconName) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AuthService.shared.updateOnlineStatus(false)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
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
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newConversation = Notification.Name("newConversation")
    static let focusSearch = Notification.Name("focusSearch")
    static let showInviteUsers = Notification.Name("showInviteUsers")
}
