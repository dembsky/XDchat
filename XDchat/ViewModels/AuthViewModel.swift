import Foundation
import Combine

@MainActor
class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var displayName = ""
    @Published var invitationCode = ""

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var showSuccess = false
    @Published var successMessage: String?

    @Published var isLoginMode = true
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var debugError: String?

    private let authService = AuthService.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Subscribe to auth state changes
        authService.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAuthenticated)

        authService.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)

        authService.$currentUser
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentUser)

        // Subscribe to debug errors
        authService.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: &$debugError)
    }

    // MARK: - Validation

    var isLoginFormValid: Bool {
        email.isValidEmail && password.count >= 6
    }

    var isRegisterFormValid: Bool {
        email.isValidEmail &&
        password.count >= 6 &&
        password == confirmPassword &&
        !displayName.trimmed.isEmpty
    }

    // MARK: - Actions

    func login() async {
        guard isLoginFormValid else {
            showError(message: "Please fill in all fields correctly.")
            return
        }

        do {
            try await authService.login(email: email.trimmed, password: password)
            clearForm()
        } catch let error as AuthError {
            showError(message: error.localizedDescription)
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    func register() async {
        guard isRegisterFormValid else {
            showError(message: "Please fill in all fields correctly.")
            return
        }

        do {
            try await authService.register(
                email: email.trimmed,
                password: password,
                displayName: displayName.trimmed,
                invitationCode: invitationCode.trimmed.isEmpty ? nil : invitationCode.trimmed
            )
            clearForm()
        } catch let error as AuthError {
            showError(message: error.localizedDescription)
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    func logout() {
        do {
            try authService.logout()
            clearForm()
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    func resetPassword() async {
        guard email.isValidEmail else {
            showError(message: "Please enter a valid email address.")
            return
        }

        do {
            try await authService.resetPassword(email: email.trimmed)
            showSuccessMessage("Password reset email sent. Check your inbox.")
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    func toggleMode() {
        isLoginMode.toggle()
        clearForm()
    }

    private func clearForm() {
        email = ""
        password = ""
        confirmPassword = ""
        displayName = ""
        invitationCode = ""
        errorMessage = nil
        showError = false
        successMessage = nil
        showSuccess = false
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
        showSuccess = false
    }

    private func showSuccessMessage(_ message: String) {
        successMessage = message
        showSuccess = true
        showError = false
    }
}
