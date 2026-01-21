import Foundation

/// Firebase Auth REST API client - bypasses Keychain by not using Firebase SDK for auth
final class FirebaseAuthREST {
    static let shared = FirebaseAuthREST()

    private let apiKey: String
    private let session = URLSession.shared

    private init() {
        // Get API key from GoogleService-Info.plist
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let key = plist["API_KEY"] as? String else {
            fatalError("Missing API_KEY in GoogleService-Info.plist")
        }
        self.apiKey = key
    }

    // MARK: - Response Types

    struct AuthResponse: Codable {
        let idToken: String
        let email: String?
        let refreshToken: String
        let expiresIn: String
        let localId: String
        let registered: Bool?
    }

    struct RefreshResponse: Codable {
        let access_token: String
        let expires_in: String
        let token_type: String
        let refresh_token: String
        let id_token: String
        let user_id: String
        let project_id: String
    }

    struct ErrorResponse: Codable {
        struct ErrorDetail: Codable {
            let code: Int
            let message: String
        }
        let error: ErrorDetail
    }

    enum AuthError: LocalizedError {
        case invalidEmail
        case emailNotFound
        case wrongPassword
        case emailExists
        case weakPassword
        case tooManyAttempts
        case networkError(String)
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .invalidEmail:
                return "Please enter a valid email address."
            case .emailNotFound, .wrongPassword:
                return "Invalid email or password."
            case .emailExists:
                return "This email is already registered."
            case .weakPassword:
                return "Password must be at least 6 characters."
            case .tooManyAttempts:
                return "Too many failed attempts. Please try again later."
            case .networkError(let msg):
                return "Network error: \(msg)"
            case .unknown(let msg):
                return msg
            }
        }
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async throws -> AuthResponse {
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(apiKey)")!

        let body: [String: Any] = [
            "email": email,
            "password": password,
            "returnSecureToken": true
        ]

        return try await makeRequest(url: url, body: body)
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String) async throws -> AuthResponse {
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(apiKey)")!

        let body: [String: Any] = [
            "email": email,
            "password": password,
            "returnSecureToken": true
        ]

        return try await makeRequest(url: url, body: body)
    }

    // MARK: - Refresh Token

    func refreshToken(_ refreshToken: String) async throws -> RefreshResponse {
        let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyString = "grant_type=refresh_token&refresh_token=\(refreshToken)"
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 200 {
            return try JSONDecoder().decode(RefreshResponse.self, from: data)
        } else {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw mapError(errorResponse.error.message)
            }
            throw AuthError.unknown("Token refresh failed")
        }
    }

    // MARK: - Password Reset

    func sendPasswordReset(email: String) async throws {
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=\(apiKey)")!

        let body: [String: Any] = [
            "requestType": "PASSWORD_RESET",
            "email": email
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw mapError(errorResponse.error.message)
            }
            throw AuthError.unknown("Password reset failed")
        }
    }

    // MARK: - Private Methods

    private func makeRequest(url: URL, body: [String: Any]) async throws -> AuthResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 200 {
            return try JSONDecoder().decode(AuthResponse.self, from: data)
        } else {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw mapError(errorResponse.error.message)
            }
            throw AuthError.unknown("Authentication failed")
        }
    }

    private func mapError(_ message: String) -> AuthError {
        switch message {
        case "INVALID_EMAIL":
            return .invalidEmail
        case "EMAIL_NOT_FOUND":
            return .emailNotFound
        case "INVALID_PASSWORD", "INVALID_LOGIN_CREDENTIALS":
            return .wrongPassword
        case "EMAIL_EXISTS":
            return .emailExists
        case "WEAK_PASSWORD : Password should be at least 6 characters":
            return .weakPassword
        case let msg where msg.contains("TOO_MANY_ATTEMPTS"):
            return .tooManyAttempts
        default:
            return .unknown(message)
        }
    }
}
