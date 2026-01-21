import Foundation
import FirebaseAuth

/// Stores Firebase Auth tokens in Application Support instead of Keychain
/// This allows the app to work without code signing
final class AuthTokenStorage {
    static let shared = AuthTokenStorage()

    private let fileManager = FileManager.default
    private var storageURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("XDchat", isDirectory: true)

        // Create directory if needed
        if !fileManager.fileExists(atPath: appFolder.path) {
            try? fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
        }

        return appFolder.appendingPathComponent("auth_session.json")
    }

    private init() {}

    // MARK: - Token Data Structure

    struct StoredSession: Codable {
        let userId: String
        let email: String?
        let refreshToken: String?
        let lastLogin: Date
    }

    // MARK: - Public Methods

    /// Save current user session to file
    func saveSession(user: FirebaseAuth.User) {
        let session = StoredSession(
            userId: user.uid,
            email: user.email,
            refreshToken: user.refreshToken,
            lastLogin: Date()
        )

        do {
            let data = try JSONEncoder().encode(session)
            try data.write(to: storageURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("AuthTokenStorage: Failed to save session - \(error)")
        }
    }

    /// Load stored session from file
    func loadSession() -> StoredSession? {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let session = try JSONDecoder().decode(StoredSession.self, from: data)
            return session
        } catch {
            print("AuthTokenStorage: Failed to load session - \(error)")
            return nil
        }
    }

    /// Clear stored session (logout)
    func clearSession() {
        try? fileManager.removeItem(at: storageURL)
    }

    /// Check if we have a stored session
    var hasStoredSession: Bool {
        fileManager.fileExists(atPath: storageURL.path)
    }
}
