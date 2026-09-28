import Foundation
import Security

/// Bridge API token. Stored in the Keychain and excluded from iCloud backup.
enum NeonBridgeKeychain {
    static let account = "neonBridgeApiKey"

    /// Tests set this to force a failed write without touching the Keychain.
    static var saveResultOverride: Bool?

    static func load() -> String? {
        KeychainHelper.load(key: account)
    }

    @discardableResult
    static func save(_ value: String) -> Bool {
        if let saveResultOverride {
            return saveResultOverride
        }
        return KeychainHelper.save(
            key: account,
            value: value,
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        )
    }

    static func delete() {
        KeychainHelper.delete(key: account)
    }
}
