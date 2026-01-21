import Foundation
import Combine
import AppKit

@MainActor
class InvitationViewModel: ObservableObject {
    @Published var invitations: [Invitation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var newInvitationCode: String?
    @Published var showCopiedAlert = false

    private let invitationService = InvitationService.shared
    private let authService = AuthService.shared
    private var cancellables = Set<AnyCancellable>()

    var currentUser: User? {
        authService.currentUser
    }

    var canCreateInvitations: Bool {
        guard let user = currentUser else { return false }
        return user.isAdmin || user.canInvite
    }

    init() {
        invitationService.$myInvitations
            .receive(on: DispatchQueue.main)
            .assign(to: &$invitations)
    }

    // MARK: - Actions

    func startListening() {
        guard let userId = currentUser?.id else { return }
        invitationService.listenToMyInvitations(userId: userId)
    }

    func stopListening() {
        invitationService.stopListening()
    }

    func createInvitation(expiresInDays: Int? = 7) async {
        guard let user = currentUser else {
            showError(message: "You must be logged in to create invitations.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let invitation = try await invitationService.createInvitation(
                by: user,
                expiresInDays: expiresInDays
            )
            newInvitationCode = invitation.code
        } catch let error as InvitationError {
            showError(message: error.localizedDescription)
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    func deleteInvitation(_ invitation: Invitation) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await invitationService.deleteInvitation(invitation)
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    func copyToClipboard(_ code: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        showCopiedAlert = true

        // Auto-hide after 2 seconds
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showCopiedAlert = false
        }
        #endif
    }

    // MARK: - Helpers

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }

    func clearNewInvitationCode() {
        newInvitationCode = nil
    }

    var activeInvitations: [Invitation] {
        invitations.filter { $0.isValid }
    }

    var usedInvitations: [Invitation] {
        invitations.filter { $0.isUsed }
    }

    var expiredInvitations: [Invitation] {
        invitations.filter { $0.isExpired && !$0.isUsed }
    }
}
