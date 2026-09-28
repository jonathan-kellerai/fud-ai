import Foundation
import Security

struct KeychainHelper {
    private static let service = "com.apoorvdarshan.calorietracker"
    static var lastStatus: OSStatus = errSecSuccess

    private static func isThisDeviceOnly(_ accessible: CFString) -> Bool {
        accessible == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            || accessible == kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            || accessible == kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
    }

    static func save(key: String, value: String) {
        _ = save(key: key, value: value, accessible: kSecAttrAccessibleAfterFirstUnlock)
    }

    /// `ThisDeviceOnly` keeps the item out of iCloud Keychain and device backups.
    @discardableResult
    static func save(key: String, value: String, accessible: CFString) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        delete(key: key)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible,
        ]
        // ThisDeviceOnly already excludes iCloud Keychain and backups. Pairing it
        // with kSecAttrSynchronizable makes SecItemAdd fail.
        if !isThisDeviceOnly(accessible) {
            query[kSecAttrSynchronizable as String] = false
        }
        let status = SecItemAdd(query as CFDictionary, nil)
        lastStatus = status
        return status == errSecSuccess
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
