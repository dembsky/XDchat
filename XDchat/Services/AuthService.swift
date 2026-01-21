import Foundation
import FirebaseCore
import FirebaseFirestore
import Combine

enum AuthError: LocalizedError {
    case invalidEmail
    case weakPassword
    case emailAlreadyInUse
    case userNotFound
    case wrongPassword
    case invalidInvitationCode
    case expiredInvitationCode
    case usedInvitationCode
    case networkError
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Please enter a valid email address."
        case .weakPassword:
            return "Password must be at least 6 characters."
        case .emailAlreadyInUse:
            return "This email is already registered."
        case .userNotFound, .wrongPassword:
            return "Invalid email or password."
        case .invalidInvitationCode:
            return "Invalid invitation code."
        case .expiredInvitationCode:
            return "This invitation code has expired."
        case .usedInvitationCode:
            return "This invitation code has already been used."
        case .networkError:
            return "Network error. Please check your connection."
        case .unknown(let message):
            return message
        }
    }
}

class AuthService: ObservableObject, AuthServiceProtocol {
    static let shared: AuthService = {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return AuthService()
    }()

    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false

    private var db: Firestore { Firestore.firestore() }
    private var userListener: ListenerRegistration?
    private var cancellables = Set<AnyCancellable>()

    /// Current user ID from stored session
    private var currentUserId: String?

    private init() {
        restoreSession()
    }

    deinit {
        userListener?.remove()
    }

    // MARK: - Session Restoration

    private func restoreSession() {
        guard let session = AuthTokenStorage.shared.loadSession() else {
            return
        }

        // Check if token is expired and refresh if needed
        if session.isExpired {
            Task {
                await refreshTokenIfNeeded()
            }
        } else {
            currentUserId = session.userId
            fetchUser(userId: session.userId)
        }
    }

    private func refreshTokenIfNeeded() async {
        guard let session = AuthTokenStorage.shared.loadSession() else { return }

        do {
            let response = try await FirebaseAuthREST.shared.refreshToken(session.refreshToken)
            let expiresIn = Int(response.expires_in) ?? 3600
            AuthTokenStorage.shared.updateTokens(
                idToken: response.id_token,
                refreshToken: response.refresh_token,
                expiresIn: expiresIn
            )

            await MainActor.run {
                self.currentUserId = session.userId
                self.fetchUser(userId: session.userId)
            }
        } catch {
            print("Token refresh failed: \(error)")
            await MainActor.run {
                AuthTokenStorage.shared.clearSession()
                self.currentUser = nil
                self.isAuthenticated = false
            }
        }
    }

    // MARK: - Fetch User

    private func fetchUser(userId: String) {
        userListener?.remove()

        userListener = db.collection("users").document(userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if error != nil {
                    return
                }

                guard let snapshot = snapshot, snapshot.exists else {
                    self.currentUser = nil
                    self.isAuthenticated = false
                    return
                }

                do {
                    self.currentUser = try snapshot.data(as: User.self)
                    self.isAuthenticated = true
                    self.updateOnlineStatus(true)
                } catch {
                    self.currentUser = nil
                    self.isAuthenticated = false
                }
            }
    }

    // MARK: - Registration

    func register(
        email: String,
        password: String,
        displayName: String,
        invitationCode: String?
    ) async throws {
        await MainActor.run { isLoading = true }

        do {
            print("AuthService: Starting registration for \(email)")

            // Check if this is the first user (will be admin)
            let isFirstUser = try await checkIfFirstUser()

            // Validate invitation code if not first user
            var invitation: Invitation?
            if !isFirstUser {
                guard let code = invitationCode, !code.isEmpty else {
                    await MainActor.run { self.isLoading = false }
                    throw AuthError.invalidInvitationCode
                }
                invitation = try await validateInvitationCode(code)
            }

            // Create user via REST API (bypasses Keychain)
            let authResponse = try await FirebaseAuthREST.shared.signUp(email: email, password: password)

            print("AuthService: Registration successful, userId: \(authResponse.localId)")

            // Save session to file storage
            AuthTokenStorage.shared.saveSession(response: authResponse)
            currentUserId = authResponse.localId

            // Create user document
            let user = User(
                id: authResponse.localId,
                email: email,
                displayName: displayName,
                isAdmin: isFirstUser,
                invitedBy: invitation?.createdBy,
                canInvite: isFirstUser,
                isOnline: true,
                createdAt: Date()
            )

            try db.collection("users").document(authResponse.localId).setData(from: user)

            // Mark invitation as used
            if let invitation = invitation {
                try await markInvitationAsUsed(invitation, usedBy: authResponse.localId)
            }

            // Fetch user to update UI
            await MainActor.run {
                self.isLoading = false
                self.fetchUser(userId: authResponse.localId)
            }
        } catch let error as FirebaseAuthREST.AuthError {
            print("AuthService: Registration failed with REST error: \(error)")
            await MainActor.run { self.isLoading = false }
            throw mapRESTError(error)
        } catch let error as AuthError {
            print("AuthService: Registration failed with AuthError: \(error)")
            await MainActor.run { self.isLoading = false }
            throw error
        } catch {
            print("AuthService: Registration failed with error: \(error)")
            await MainActor.run { self.isLoading = false }
            throw AuthError.unknown(error.localizedDescription)
        }
    }

    private func checkIfFirstUser() async throws -> Bool {
        let snapshot = try await db.collection("users").limit(to: 1).getDocuments()
        return snapshot.documents.isEmpty
    }

    private func validateInvitationCode(_ code: String) async throws -> Invitation {
        let snapshot = try await db.collection("invitations")
            .whereField("code", isEqualTo: code.uppercased())
            .limit(to: 1)
            .getDocuments()

        guard let document = snapshot.documents.first else {
            throw AuthError.invalidInvitationCode
        }

        let invitation = try document.data(as: Invitation.self)

        if invitation.isUsed {
            throw AuthError.usedInvitationCode
        }

        if invitation.isExpired {
            throw AuthError.expiredInvitationCode
        }

        return invitation
    }

    private func markInvitationAsUsed(_ invitation: Invitation, usedBy userId: String) async throws {
        guard let invitationId = invitation.id else { return }

        try await db.collection("invitations").document(invitationId).updateData([
            "isUsed": true,
            "usedBy": userId
        ])
    }

    // MARK: - Login

    func login(email: String, password: String) async throws {
        await MainActor.run { isLoading = true }

        do {
            print("AuthService: Starting login for \(email)")

            // Use REST API instead of Firebase SDK (bypasses Keychain)
            let authResponse = try await FirebaseAuthREST.shared.signIn(email: email, password: password)

            print("AuthService: Login successful, userId: \(authResponse.localId)")

            // Save session to file storage
            AuthTokenStorage.shared.saveSession(response: authResponse)
            currentUserId = authResponse.localId

            // Fetch user to update UI
            await MainActor.run {
                self.isLoading = false
                self.fetchUser(userId: authResponse.localId)
            }
        } catch let error as FirebaseAuthREST.AuthError {
            print("AuthService: Login failed with REST error: \(error)")
            await MainActor.run { self.isLoading = false }
            throw mapRESTError(error)
        } catch {
            print("AuthService: Login failed with error: \(error)")
            await MainActor.run { self.isLoading = false }
            throw AuthError.unknown(error.localizedDescription)
        }
    }

    // MARK: - Logout

    func logout() throws {
        updateOnlineStatus(false)
        userListener?.remove()
        AuthTokenStorage.shared.clearSession()
        currentUserId = nil
        currentUser = nil
        isAuthenticated = false
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async throws {
        do {
            try await FirebaseAuthREST.shared.sendPasswordReset(email: email)
        } catch let error as FirebaseAuthREST.AuthError {
            throw mapRESTError(error)
        }
    }

    // MARK: - Online Status

    func updateOnlineStatus(_ isOnline: Bool) {
        guard let userId = currentUser?.id ?? currentUserId else { return }

        var updateData: [String: Any] = ["isOnline": isOnline]
        if !isOnline {
            updateData["lastSeen"] = FieldValue.serverTimestamp()
        }

        db.collection("users").document(userId).updateData(updateData)
    }

    // MARK: - Update Profile

    func updateDisplayName(_ displayName: String) async throws {
        guard let userId = currentUser?.id else { return }

        try await db.collection("users").document(userId).updateData([
            "displayName": displayName
        ])
    }

    // MARK: - Get Current Token

    /// Get valid ID token for authenticated requests
    func getIdToken() async -> String? {
        guard let session = AuthTokenStorage.shared.loadSession() else { return nil }

        if session.isExpired {
            await refreshTokenIfNeeded()
            return AuthTokenStorage.shared.loadSession()?.idToken
        }

        return session.idToken
    }

    // MARK: - Error Mapping

    private func mapRESTError(_ error: FirebaseAuthREST.AuthError) -> AuthError {
        switch error {
        case .invalidEmail:
            return .invalidEmail
        case .emailNotFound, .wrongPassword:
            return .wrongPassword
        case .emailExists:
            return .emailAlreadyInUse
        case .weakPassword:
            return .weakPassword
        case .networkError:
            return .networkError
        case .tooManyAttempts:
            return .unknown("Too many failed attempts. Please try again later.")
        case .unknown(let msg):
            return .unknown(msg)
        }
    }
}
