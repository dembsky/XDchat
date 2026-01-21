import Foundation
import FirebaseFirestore
import Combine

final class ListenerManager {
    static let shared = ListenerManager()

    private var listeners: [ListenerKey: ListenerRegistration] = [:]
    private let queue = DispatchQueue(label: "com.xdchat.listenerManager", attributes: .concurrent)

    private init() {}

    // MARK: - Listener Key

    struct ListenerKey: Hashable {
        let type: ListenerType
        let identifier: String

        init(_ type: ListenerType, identifier: String) {
            self.type = type
            self.identifier = identifier
        }
    }

    enum ListenerType: String, Hashable {
        case conversations
        case messages
        case user
        case invitations
    }

    // MARK: - Add Listener

    func addListener(
        key: ListenerKey,
        listener: ListenerRegistration
    ) {
        queue.async(flags: .barrier) { [weak self] in
            // Remove existing listener if any
            self?.listeners[key]?.remove()
            self?.listeners[key] = listener
        }
    }

    func addListener(
        type: ListenerType,
        identifier: String,
        listener: ListenerRegistration
    ) {
        let key = ListenerKey(type, identifier: identifier)
        addListener(key: key, listener: listener)
    }

    // MARK: - Remove Listener

    func removeListener(key: ListenerKey) {
        queue.async(flags: .barrier) { [weak self] in
            self?.listeners[key]?.remove()
            self?.listeners.removeValue(forKey: key)
        }
    }

    func removeListener(type: ListenerType, identifier: String) {
        let key = ListenerKey(type, identifier: identifier)
        removeListener(key: key)
    }

    func removeListeners(ofType type: ListenerType) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            let keysToRemove = self.listeners.keys.filter { $0.type == type }
            for key in keysToRemove {
                self.listeners[key]?.remove()
                self.listeners.removeValue(forKey: key)
            }
        }
    }

    func removeAllListeners() {
        queue.async(flags: .barrier) { [weak self] in
            self?.listeners.values.forEach { $0.remove() }
            self?.listeners.removeAll()
        }
    }

    // MARK: - Query

    func hasListener(key: ListenerKey) -> Bool {
        queue.sync {
            listeners[key] != nil
        }
    }

    func hasListener(type: ListenerType, identifier: String) -> Bool {
        hasListener(key: ListenerKey(type, identifier: identifier))
    }

    var activeListenerCount: Int {
        queue.sync {
            listeners.count
        }
    }
}

// MARK: - Convenience Extensions

extension ListenerManager {
    func conversationsKey(userId: String) -> ListenerKey {
        ListenerKey(.conversations, identifier: userId)
    }

    func messagesKey(conversationId: String) -> ListenerKey {
        ListenerKey(.messages, identifier: conversationId)
    }

    func userKey(userId: String) -> ListenerKey {
        ListenerKey(.user, identifier: userId)
    }

    func invitationsKey(userId: String) -> ListenerKey {
        ListenerKey(.invitations, identifier: userId)
    }
}
