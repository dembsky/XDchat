import Foundation
@preconcurrency import FirebaseFirestore

struct User: Identifiable, Codable, Equatable, Sendable {
    @DocumentID var id: String?
    let email: String
    var displayName: String
    var isAdmin: Bool
    var invitedBy: String?
    var canInvite: Bool
    var avatarURL: String?
    var avatarData: String?
    var isOnline: Bool
    var lastSeen: Date?
    let createdAt: Date

    init(
        id: String? = nil,
        email: String,
        displayName: String,
        isAdmin: Bool = false,
        invitedBy: String? = nil,
        canInvite: Bool = false,
        avatarURL: String? = nil,
        avatarData: String? = nil,
        isOnline: Bool = false,
        lastSeen: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.isAdmin = isAdmin
        self.invitedBy = invitedBy
        self.canInvite = canInvite
        self.avatarURL = avatarURL
        self.avatarData = avatarData
        self.isOnline = isOnline
        self.lastSeen = lastSeen
        self.createdAt = createdAt
    }

    var initials: String {
        let components = displayName.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }
}
