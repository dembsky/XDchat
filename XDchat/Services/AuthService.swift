import Foundation
import FirebaseCore
import FirebaseAuth
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
        // Ensure Firebase is configured before creating AuthService
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return AuthService()
    }()

    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false

    private var auth: Auth { Auth.auth() }
    private var db: Firestore { Firestore.firestore() }
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var userListener: ListenerRegistration?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupAuthStateListener()
    }

    deinit {
        if let listener = authStateListener {
            auth.removeStateDidChangeListener(listener)
        }
        userListener?.remove()
    }

    // MARK: - Auth State

    private func setupAuthStateListener() {
        authStateListener = auth.addStateDidChangeListener { [weak self] _, firebaseUser in
            guard let self = self else { return }

            if let firebaseUser = firebaseUser {
                self.fetchUser(userId: firebaseUser.uid)
            } else {
                self.currentUser = nil
                self.isAuthenticated = false
                self.userListener?.remove()
            }
        }
    }

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
        isLoading = true
        defer { isLoading = false }

        // Check if this is the first user (will be admin)
        let isFirstUser = try await checkIfFirstUser()

        // Validate invitation code if not first user
        var invitation: Invitation?
        if !isFirstUser {
            guard let code = invitationCode, !code.isEmpty else {
                throw AuthError.invalidInvitationCode
            }
            invitation = try await validateInvitationCode(code)
        }

        // Create Firebase Auth user
        let result = try await auth.createUser(withEmail: email, password: password)

        // Create user document
        let user = User(
            id: result.user.uid,
            email: email,
            displayName: displayName,
            isAdmin: isFirstUser,
            invitedBy: invitation?.createdBy,
            canInvite: isFirstUser,
            isOnline: true,
            createdAt: Date()
        )

        try db.collection("users").document(result.user.uid).setData(from: user)

        // Mark invitation as used
        if let invitation = invitation {
            try await markInvitationAsUsed(invitation, usedBy: result.user.uid)
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
        isLoading = true
        defer { isLoading = false }

        do {
            try await auth.signIn(withEmail: email, password: password)
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }

    // MARK: - Logout

    func logout() throws {
        updateOnlineStatus(false)
        try auth.signOut()
        currentUser = nil
        isAuthenticated = false
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async throws {
        try await auth.sendPasswordReset(withEmail: email)
    }

    // MARK: - Online Status

    func updateOnlineStatus(_ isOnline: Bool) {
        guard let userId = currentUser?.id else { return }

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

    // MARK: - Error Mapping

    private func mapFirebaseError(_ error: NSError) -> AuthError {
        guard let errorCode = AuthErrorCode(rawValue: error.code) else {
            return .unknown(error.localizedDescription)
        }

        switch errorCode {
        case .invalidEmail:
            return .invalidEmail
        case .weakPassword:
            return .weakPassword
        case .emailAlreadyInUse:
            return .emailAlreadyInUse
        case .userNotFound, .wrongPassword:
            return .wrongPassword
        case .networkError:
            return .networkError
        default:
            return .unknown(error.localizedDescription)
        }
    }
}
