import Foundation
@preconcurrency import FirebaseFirestore

struct Invitation: Identifiable, Codable, Equatable, Sendable {
    @DocumentID var id: String?
    let code: String
    let createdBy: String
    var usedBy: String?
    var isUsed: Bool
    let createdAt: Date
    var expiresAt: Date?

    init(
        id: String? = nil,
        code: String,
        createdBy: String,
        usedBy: String? = nil,
        isUsed: Bool = false,
        createdAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.code = code
        self.createdBy = createdBy
        self.usedBy = usedBy
        self.isUsed = isUsed
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }

    var isValid: Bool {
        !isUsed && !isExpired
    }

    static func generateCode(length: Int = 6) -> String {
        let characters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }
}
