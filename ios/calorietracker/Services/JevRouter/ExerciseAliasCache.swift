import Foundation

/// Local fragment → exercise id map. Never included in cloud backup.
final class ExerciseAliasCache: @unchecked Sendable {
    static let shared = ExerciseAliasCache()

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var order: [String] = []
    private var ids: [String: String] = [:]
    private let capacity = 500

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: JevRouterSettings.exerciseAliasesKey),
           let stored = try? JSONDecoder().decode([Entry].self, from: data) {
            order = stored.map(\.fragment)
            ids = Dictionary(uniqueKeysWithValues: stored.map { ($0.fragment, $0.id) })
        }
    }

    func id(for fragment: String, library: [ExerciseLibraryItem]) -> String? {
        let key = JevText.normalize(fragment)
        guard !key.isEmpty else { return nil }
        lock.lock()
        let stored = ids[key]
        lock.unlock()
        guard let stored else { return nil }
        guard library.contains(where: { $0.id == stored }) else {
            remove(fragment: key)
            return nil
        }
        return stored
    }

    func store(fragment: String, id: String) {
        let key = JevText.normalize(fragment)
        guard !key.isEmpty, !id.isEmpty else { return }
        lock.lock()
        ids[key] = id
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity {
            let dropped = order.removeFirst()
            ids.removeValue(forKey: dropped)
        }
        let snapshot = order.compactMap { fragment in ids[fragment].map { Entry(fragment: fragment, id: $0) } }
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: JevRouterSettings.exerciseAliasesKey)
        }
    }

    func remove(fragment: String) {
        let key = JevText.normalize(fragment)
        lock.lock()
        ids.removeValue(forKey: key)
        order.removeAll { $0 == key }
        let snapshot = order.compactMap { fragment in ids[fragment].map { Entry(fragment: fragment, id: $0) } }
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: JevRouterSettings.exerciseAliasesKey)
        }
    }

    func clear() {
        lock.lock()
        ids.removeAll()
        order.removeAll()
        lock.unlock()
        defaults.removeObject(forKey: JevRouterSettings.exerciseAliasesKey)
    }

    private struct Entry: Codable {
        var fragment: String
        var id: String
    }
}
