import Foundation

struct JevDecisionCache: Sendable {
    private struct Entry: Sendable {
        var response: TypeSafeResponse
        var expiresAt: Date
    }

    private let capacity: Int
    private var order: [String] = []
    private var entries: [String: Entry] = [:]

    init(capacity: Int = 256) {
        self.capacity = max(1, capacity)
    }

    mutating func value(for key: String, now: Date) -> TypeSafeResponse? {
        guard let entry = entries[key] else { return nil }
        guard entry.expiresAt > now else {
            remove(key)
            return nil
        }
        touch(key)
        return entry.response
    }

    mutating func store(_ response: TypeSafeResponse, for key: String, ttl: TimeInterval, now: Date) {
        if entries[key] != nil {
            entries[key] = Entry(response: response, expiresAt: now.addingTimeInterval(ttl))
            touch(key)
            return
        }
        while order.count >= capacity, let oldest = order.first {
            remove(oldest)
        }
        entries[key] = Entry(response: response, expiresAt: now.addingTimeInterval(ttl))
        order.append(key)
    }

    mutating func removeAll() {
        order.removeAll()
        entries.removeAll()
    }

    private mutating func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private mutating func remove(_ key: String) {
        entries[key] = nil
        order.removeAll { $0 == key }
    }
}
