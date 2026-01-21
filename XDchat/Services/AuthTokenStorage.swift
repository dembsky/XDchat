import Foundation

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
        let idToken: String
        let refreshToken: String
        let expiresAt: Date
        let lastLogin: Date

        var isExpired: Bool {
            Date() >= expiresAt
        }
    }

    // MARK: - Public Methods

    /// Save session from REST API response
    func saveSession(response: FirebaseAuthREST.AuthResponse) {
        let expiresIn = Int(response.expiresIn) ?? 3600
        let session = StoredSession(
            userId: response.localId,
            email: response.email,
            idToken: response.idToken,
            refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            lastLogin: Date()
        )

        do {
            let data = try JSONEncoder().encode(session)
            try data.write(to: storageURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("AuthTokenStorage: Failed to save session - \(error)")
        }
    }

    /// Update tokens after refresh
    func updateTokens(idToken: String, refreshToken: String, expiresIn: Int) {
        guard var session = loadSession() else { return }

        let updatedSession = StoredSession(
            userId: session.userId,
            email: session.email,
            idToken: idToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            lastLogin: session.lastLogin
        )

        do {
            let data = try JSONEncoder().encode(updatedSession)
            try data.write(to: storageURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("AuthTokenStorage: Failed to update tokens - \(error)")
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
