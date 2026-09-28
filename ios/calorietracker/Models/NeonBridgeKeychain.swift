import Foundation
import Security

/// Bridge API token. Stored in the Keychain and excluded from iCloud backup.
enum NeonBridgeKeychain {
    static let account = "neonBridgeApiKey"

    /// Tests set this to force a failed write without touching the Keychain.
    static var saveResultOverride: Bool?
    /// When set, tests read and write this dictionary instead of the Keychain.
    /// The unsigned CI host rejects SecItemAdd, so the migration proof uses this store.
    static var memoryStore: [String: String]?

    static func load() -> String? {
        if let memoryStore {
            return memoryStore[account]
        }
        return KeychainHelper.load(key: account)
    }

    @discardableResult
    static func save(_ value: String) -> Bool {
        if let saveResultOverride {
            return saveResultOverride
        }
        if memoryStore != nil {
            memoryStore?[account] = value
            return true
        }
        return KeychainHelper.save(
            key: account,
            value: value,
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        )
    }

    static func delete() {
        if memoryStore != nil {
            memoryStore?[account] = nil
            return
        }
        KeychainHelper.delete(key: account)
    }
}
