import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import Combine
import os.log

/// Error codes used inside Firestore transactions where only NSError can be thrown.
private enum InvitationTransactionError: Int {
    case notFound = -1
    case alreadyUsed = -2
    case expired = -3

    static let domain = "AuthService.InvitationTransaction"

    func nsError(description: String) -> NSError {
        NSError(domain: Self.domain, code: rawValue,
                userInfo: [NSLocalizedDescriptionKey: description])
    }
}

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

@MainActor
class AuthService: ObservableObject, AuthServiceProtocol {
    static let shared: AuthService = {
        // Configure Firebase before Auth is accessed
        FirebaseApp.configure()
        return AuthService()
    }()

    @Published var currentUser: User?
    @Published var isAuthenticated: Bool
    @Published var isLoading = false

    private var db: Firestore { Firestore.firestore() }
    private var authStateListener: AuthStateDidChangeListenerHandle?

    private init() {
        // Use cached auth state for instant UI - Firebase will update if wrong
        self.isAuthenticated = UserDefaults.standard.bool(forKey: Constants.StorageKeys.wasAuthenticated)
        setupAuthStateListener()
    }

    private func setAuthenticated(_ value: Bool) {
        isAuthenticated = value
        UserDefaults.standard.set(value, forKey: Constants.StorageKeys.wasAuthenticated)
    }

    // Note: deinit is omitted because AuthService is a singleton (never deallocated).
    // The auth state listener lives for the entire app lifecycle.

    // MARK: - Auth State Listener

    private func setupAuthStateListener() {
        // Firebase calls this closure from a background thread.
        // fetchUser is nonisolated and hops to @MainActor internally.
        // The else branch needs an explicit @MainActor hop to mutate published properties.
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            guard let self else { return }

            if let firebaseUser = firebaseUser {
                self.fetchUser(userId: firebaseUser.uid)
            } else {
                Task { @MainActor in
                    self.currentUser = nil
                    self.setAuthenticated(false)
                }
            }
        }
    }

    // MARK: - Fetch User

    private nonisolated func fetchUser(userId: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let document = try await self.db.collection(Constants.Collections.users).document(userId).getDocument(source: .server)

                guard let data = document.data() else {
                    self.currentUser = nil
                    self.setAuthenticated(false)
                    return
                }

                // Manual decoding to avoid Codable issues
                let user = User(
                    id: document.documentID,
                    email: data["email"] as? String ?? "",
                    displayName: data["displayName"] as? String ?? "Unknown",
                    isAdmin: data["isAdmin"] as? Bool ?? false,
                    invitedBy: data["invitedBy"] as? String,
                    canInvite: data["canInvite"] as? Bool ?? false,
                    avatarURL: data["avatarURL"] as? String,
                    avatarData: data["avatarData"] as? String,
                    isOnline: data["isOnline"] as? Bool ?? false,
                    lastSeen: (data["lastSeen"] as? Timestamp)?.dateValue(),
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                )
                self.currentUser = user
                self.setAuthenticated(true)

                // Update online status
                try? await self.db.collection(Constants.Collections.users).document(userId).updateData([
                    "isOnline": true
                ])
            } catch {
                Logger.auth.error("Error fetching user: \(error.localizedDescription)")
                self.currentUser = nil
                self.setAuthenticated(false)
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
        try await performRegistration(email: email, password: password, displayName: displayName, invitationCode: invitationCode)
    }

    private func performRegistration(
        email: String,
        password: String,
        displayName: String,
        invitationCode: String?
    ) async throws {

        // Check if this is the first user (will be admin)
        let isFirstUser = try await checkIfFirstUser()

        // Validate and atomically claim invitation code if not first user
        var claimResult: InvitationClaimResult?
        if !isFirstUser {
            guard let code = invitationCode, !code.isEmpty else {
                throw AuthError.invalidInvitationCode
            }
            // This validates AND marks as used in a single transaction (prevents TOCTOU)
            do {
                claimResult = try await validateAndClaimInvitation(code: code)
            } catch let error as NSError where error.domain == InvitationTransactionError.domain {
                switch InvitationTransactionError(rawValue: error.code) {
                case .alreadyUsed: throw AuthError.usedInvitationCode
                case .expired: throw AuthError.expiredInvitationCode
                default: throw AuthError.invalidInvitationCode
                }
            }
        }

        // Create user with Firebase Auth
        let authResult: AuthDataResult
        do {
            authResult = try await Auth.auth().createUser(withEmail: email, password: password)
        } catch {
            // Rollback invitation claim if Auth account creation fails
            if let claimResult {
                try? await claimResult.invitationRef.updateData(["isUsed": false])
            }
            throw error
        }
        let userId = authResult.user.uid

        // Create user document in Firestore
        let user = User(
            id: userId,
            email: email,
            displayName: displayName,
            isAdmin: isFirstUser,
            invitedBy: claimResult?.createdBy,
            canInvite: isFirstUser,
            isOnline: true,
            createdAt: Date()
        )

        do {
            try db.collection(Constants.Collections.users).document(userId).setData(from: user)
        } catch {
            // Rollback: delete orphaned Auth account and release invitation
            try? await authResult.user.delete()
            if let claimResult {
                try? await claimResult.invitationRef.updateData(["isUsed": false])
            }
            throw error
        }

        // Record which user consumed the invitation (audit trail, non-critical)
        if let claimResult = claimResult {
            try? await claimResult.invitationRef.updateData(["usedBy": userId])
        }
    }

    private func checkIfFirstUser() async throws -> Bool {
        let snapshot = try await db.collection(Constants.Collections.users).limit(to: 1).getDocuments()
        return snapshot.documents.isEmpty
    }

    private struct InvitationClaimResult {
        let createdBy: String
        let invitationRef: DocumentReference
    }

    /// Atomically validate and claim an invitation code using a Firestore transaction.
    /// Returns the claim result containing the inviter's ID and a reference to update `usedBy` later.
    private func validateAndClaimInvitation(code: String) async throws -> InvitationClaimResult {
        // First find the invitation document
        let snapshot = try await db.collection(Constants.Collections.invitations)
            .whereField("code", isEqualTo: code.uppercased())
            .limit(to: 1)
            .getDocuments()

        guard let document = snapshot.documents.first else {
            throw AuthError.invalidInvitationCode
        }

        let invitationRef = document.reference

        // Use a transaction to atomically check and claim
        let result: Any? = try await db.runTransaction { transaction, errorPointer in
            let freshDoc: DocumentSnapshot
            do {
                freshDoc = try transaction.getDocument(invitationRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            guard let data = freshDoc.data() else {
                errorPointer?.pointee = InvitationTransactionError.notFound
                    .nsError(description: "Invitation not found")
                return nil
            }

            let isUsed = data["isUsed"] as? Bool ?? false
            if isUsed {
                errorPointer?.pointee = InvitationTransactionError.alreadyUsed
                    .nsError(description: "Invitation already used")
                return nil
            }

            if let expiresAt = (data["expiresAt"] as? Timestamp)?.dateValue(), Date() > expiresAt {
                errorPointer?.pointee = InvitationTransactionError.expired
                    .nsError(description: "Invitation expired")
                return nil
            }

            // Claim the invitation atomically
            transaction.updateData(["isUsed": true], forDocument: invitationRef)

            return data["createdBy"] as? String as Any
        }

        guard let createdBy = result as? String else {
            throw AuthError.invalidInvitationCode
        }
        return InvitationClaimResult(createdBy: createdBy, invitationRef: invitationRef)
    }

    // MARK: - Login

    func login(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }

    // MARK: - Logout

    func logout() throws {
        updateOnlineStatus(false)
        // Clean up all Firestore listeners to prevent dangling connections
        FirestoreService.shared.removeAllListeners()
        InvitationService.shared.stopListening()
        try Auth.auth().signOut()
        currentUser = nil
        setAuthenticated(false)
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    // MARK: - Online Status

    func updateOnlineStatus(_ isOnline: Bool) {
        guard let userId = currentUser?.id ?? Auth.auth().currentUser?.uid else { return }

        Task {
            try? await updateOnlineStatusAsync(userId: userId, isOnline: isOnline)
        }
    }

    /// Synchronous variant for use in applicationWillTerminate where async Tasks
    /// cannot complete before the process exits.
    /// Writes to Firestore local cache (offline persistence) without a completion
    /// handler -- this is synchronous and avoids deadlocking the main thread.
    /// The SDK will flush the write to the server in the background or on next launch.
    func updateOnlineStatusSync(_ isOnline: Bool) {
        guard let userId = currentUser?.id ?? Auth.auth().currentUser?.uid else { return }

        var updateData: [String: Any] = ["isOnline": isOnline]
        if !isOnline {
            updateData["lastSeen"] = FieldValue.serverTimestamp()
        }

        // Fire-and-forget write to Firestore local cache.
        // No completion handler = no callback thread concern = no deadlock risk.
        // Firestore offline persistence ensures this is written to disk immediately
        // and synced to the server on next launch if the process exits before sync.
        db.collection(Constants.Collections.users).document(userId).updateData(updateData)
    }

    private func updateOnlineStatusAsync(userId: String, isOnline: Bool) async throws {
        var updateData: [String: Any] = ["isOnline": isOnline]
        if !isOnline {
            updateData["lastSeen"] = FieldValue.serverTimestamp()
        }

        try await db.collection(Constants.Collections.users).document(userId).updateData(updateData)
    }

    // MARK: - Update Profile

    func updateDisplayName(_ displayName: String) async throws {
        guard let userId = currentUser?.id else { return }

        try await db.collection(Constants.Collections.users).document(userId).updateData([
            "displayName": displayName
        ])
    }

    // MARK: - Error Mapping

    private func mapFirebaseError(_ error: NSError) -> AuthError {
        guard let errorCode = AuthErrorCode(rawValue: error.code) else {
            return .unknown("An unexpected error occurred. Please try again.")
        }

        switch errorCode {
        case .invalidEmail:
            return .invalidEmail
        case .emailAlreadyInUse:
            return .emailAlreadyInUse
        case .weakPassword:
            return .weakPassword
        case .userNotFound:
            return .userNotFound
        case .wrongPassword:
            return .wrongPassword
        case .networkError:
            return .networkError
        default:
            return .unknown("An unexpected error occurred. Please try again.")
        }
    }
}
