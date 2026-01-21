import Foundation
import FirebaseCore
import FirebaseFirestore

enum InvitationError: LocalizedError {
    case notAuthorized
    case invalidCode
    case codeAlreadyUsed
    case codeExpired
    case creationFailed
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "You are not authorized to create invitations."
        case .invalidCode:
            return "Invalid invitation code."
        case .codeAlreadyUsed:
            return "This invitation code has already been used."
        case .codeExpired:
            return "This invitation code has expired."
        case .creationFailed:
            return "Failed to create invitation."
        case .unknown(let message):
            return message
        }
    }
}

class InvitationService: ObservableObject, InvitationServiceProtocol {
    static let shared = InvitationService()

    @Published var myInvitations: [Invitation] = []
    @Published var isLoading = false

    private var db: Firestore { Firestore.firestore() }
    private var listener: ListenerRegistration?

    private init() {}

    deinit {
        listener?.remove()
    }

    // MARK: - Create Invitation

    func createInvitation(by user: User, expiresInDays: Int? = 7) async throws -> Invitation {
        guard user.isAdmin || user.canInvite else {
            throw InvitationError.notAuthorized
        }

        guard let userId = user.id else {
            throw InvitationError.creationFailed
        }

        let code = generateUniqueCode()

        var expiresAt: Date? = nil
        if let days = expiresInDays {
            expiresAt = Calendar.current.date(byAdding: .day, value: days, to: Date())
        }

        let invitation = Invitation(
            code: code,
            createdBy: userId,
            createdAt: Date(),
            expiresAt: expiresAt
        )

        let docRef = db.collection("invitations").document()
        try docRef.setData(from: invitation)

        var savedInvitation = invitation
        savedInvitation.id = docRef.documentID

        return savedInvitation
    }

    // MARK: - Validate Invitation

    func validateInvitation(code: String) async throws -> Invitation {
        let snapshot = try await db.collection("invitations")
            .whereField("code", isEqualTo: code.uppercased().trimmed)
            .limit(to: 1)
            .getDocuments()

        guard let document = snapshot.documents.first else {
            throw InvitationError.invalidCode
        }

        let invitation = try document.data(as: Invitation.self)

        if invitation.isUsed {
            throw InvitationError.codeAlreadyUsed
        }

        if invitation.isExpired {
            throw InvitationError.codeExpired
        }

        return invitation
    }

    // MARK: - Get Invitations

    func getInvitations(createdBy userId: String) async throws -> [Invitation] {
        let snapshot = try await db.collection("invitations")
            .whereField("createdBy", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { try? $0.data(as: Invitation.self) }
    }

    func listenToMyInvitations(userId: String) {
        listener?.remove()

        listener = db.collection("invitations")
            .whereField("createdBy", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if error != nil {
                    return
                }

                guard let snapshot = snapshot else { return }

                self.myInvitations = snapshot.documents.compactMap {
                    try? $0.data(as: Invitation.self)
                }
            }
    }

    // MARK: - Delete Invitation

    func deleteInvitation(_ invitation: Invitation) async throws {
        guard let invitationId = invitation.id else { return }
        try await db.collection("invitations").document(invitationId).delete()
    }

    // MARK: - Grant Invite Permission

    func grantInvitePermission(to userId: String) async throws {
        try await db.collection("users").document(userId).updateData([
            "canInvite": true
        ])
    }

    func revokeInvitePermission(from userId: String) async throws {
        try await db.collection("users").document(userId).updateData([
            "canInvite": false
        ])
    }

    // MARK: - Helpers

    private func generateUniqueCode() -> String {
        Invitation.generateCode()
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }
}
