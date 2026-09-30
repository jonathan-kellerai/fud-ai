import Foundation
import Testing
@testable import calorietracker

/// The bridge key must live in the Keychain, never in the UserDefaults JSON.
/// Every test restores the UserDefaults entry and Keychain item it found.
@Suite(.serialized)
@MainActor
struct BridgeKeyStorageTests {
    private static let defaultsKey = NeonBridgeSettings.storageKey
    private static let account = NeonBridgeSettings.apiKeyKeychainAccount
    /// Fake values for tests only.
    private static let testKey = "test-bridge-key-not-real"
    private static let testURL = "https://bridge-key-tests.invalid"

    private func withCleanState(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let savedData = defaults.data(forKey: Self.defaultsKey)
        let savedKey = KeychainHelper.load(key: Self.account)
        let pendingKey = NeonBridgeSettings.pendingKeychainWriteKey
        let savedPending = defaults.object(forKey: pendingKey)
        defaults.removeObject(forKey: pendingKey)
        defaults.removeObject(forKey: Self.defaultsKey)
        KeychainHelper.delete(key: Self.account)
        defer {
            if let savedPending {
                defaults.set(savedPending, forKey: pendingKey)
            } else {
                defaults.removeObject(forKey: pendingKey)
            }
            if let savedData {
                defaults.set(savedData, forKey: Self.defaultsKey)
            } else {
                defaults.removeObject(forKey: Self.defaultsKey)
            }
            if let savedKey {
                KeychainHelper.upsert(key: Self.account, value: savedKey)
            } else {
                KeychainHelper.delete(key: Self.account)
            }
        }
        try body()
    }

    /// Fails the test (rather than skipping it) if this host cannot use the Keychain.
    private static func requireKeychain() throws {
        let probe = account + ".probe"
        let wrote = KeychainHelper.upsert(key: probe, value: "probe")
        let works = wrote && KeychainHelper.load(key: probe) == "probe"
        KeychainHelper.delete(key: probe)
        try #require(works, "Keychain unavailable in this test host")
    }

    private func storedJSON() throws -> [String: Any] {
        let data = try #require(UserDefaults.standard.data(forKey: Self.defaultsKey))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func saveReturnsTrueAndOmitsKeyFromJSON() throws {
        try Self.requireKeychain()
        try withCleanState {
            let saved = NeonBridgeSettings(baseURL: Self.testURL, apiKey: Self.testKey).save()
            #expect(saved)
            let json = try storedJSON()
            #expect(json.keys.contains("apiKey") == false)
            #expect(json["baseURL"] as? String == Self.testURL)
        }
    }

    @Test func saveKeepsKeyInKeychainOnly() throws {
        try Self.requireKeychain()
        try withCleanState {
            #expect(NeonBridgeSettings(baseURL: Self.testURL, apiKey: Self.testKey).save())

            let json = try storedJSON()
            #expect(json["baseURL"] as? String == Self.testURL)
            #expect(json["apiKey"] == nil)
            let raw = try #require(UserDefaults.standard.data(forKey: Self.defaultsKey))
            #expect(String(decoding: raw, as: UTF8.self).contains(Self.testKey) == false)

            #expect(KeychainHelper.load(key: Self.account) == Self.testKey)

            let loaded = NeonBridgeSettings.load()
            #expect(loaded.baseURL == Self.testURL)
            #expect(loaded.apiKey == Self.testKey)
        }
    }

    @Test func legacyJSONKeyMigratesToKeychain() throws {
        try Self.requireKeychain()
        try withCleanState {
            let legacy = #"{"baseURL":"https://bridge-key-tests.invalid","apiKey":"test-bridge-key-not-real"}"#
            UserDefaults.standard.set(Data(legacy.utf8), forKey: Self.defaultsKey)
            #expect(KeychainHelper.load(key: Self.account) == nil)

            let loaded = NeonBridgeSettings.load()
            #expect(loaded.baseURL == Self.testURL)
            #expect(loaded.apiKey == Self.testKey)
            #expect(KeychainHelper.load(key: Self.account) == Self.testKey)

            let json = try storedJSON()
            #expect(json["baseURL"] as? String == Self.testURL)
            #expect(json["apiKey"] == nil)

            // A second load reads the migrated key from the Keychain.
            #expect(NeonBridgeSettings.load().apiKey == Self.testKey)
        }
    }

    @Test func plainLegacyCopyNeverOverwritesKeychainKey() throws {
        try Self.requireKeychain()
        try withCleanState {
            let newer = "newer-test-bridge-key-not-real"
            #expect(KeychainHelper.upsert(key: Self.account, value: newer))
            let legacy = #"{"baseURL":"https://bridge-key-tests.invalid","apiKey":"test-bridge-key-not-real"}"#
            UserDefaults.standard.set(Data(legacy.utf8), forKey: Self.defaultsKey)

            #expect(NeonBridgeSettings.load().apiKey == newer)
            #expect(KeychainHelper.load(key: Self.account) == newer)
            let json = try storedJSON()
            #expect(json["apiKey"] == nil)
        }
    }

    @Test func pendingLegacyCopyFromFailedSaveWins() throws {
        try Self.requireKeychain()
        try withCleanState {
            #expect(KeychainHelper.upsert(key: Self.account, value: "older-test-bridge-key-not-real"))
            let legacy = #"{"baseURL":"https://bridge-key-tests.invalid","apiKey":"test-bridge-key-not-real"}"#
            UserDefaults.standard.set(Data(legacy.utf8), forKey: Self.defaultsKey)
            UserDefaults.standard.set(true, forKey: NeonBridgeSettings.pendingKeychainWriteKey)

            #expect(NeonBridgeSettings.load().apiKey == Self.testKey)
            #expect(KeychainHelper.load(key: Self.account) == Self.testKey)
            #expect(UserDefaults.standard.object(forKey: NeonBridgeSettings.pendingKeychainWriteKey) == nil)
        }
    }

    @Test func nilOrEmptyKeyDeletesKeychainItem() throws {
        try Self.requireKeychain()
        try withCleanState {
            NeonBridgeSettings(baseURL: Self.testURL, apiKey: Self.testKey).save()
            #expect(KeychainHelper.load(key: Self.account) == Self.testKey)

            #expect(NeonBridgeSettings(baseURL: Self.testURL, apiKey: nil).save())
            #expect(KeychainHelper.load(key: Self.account) == nil)
            #expect(NeonBridgeSettings.load().apiKey == nil)

            NeonBridgeSettings(baseURL: Self.testURL, apiKey: Self.testKey).save()
            #expect(NeonBridgeSettings(baseURL: Self.testURL, apiKey: "").save())
            #expect(KeychainHelper.load(key: Self.account) == nil)
            #expect(NeonBridgeSettings.load().apiKey == nil)
        }
    }

    @Test func loadWithNothingStoredUsesDefaultURL() throws {
        try withCleanState {
            let loaded = NeonBridgeSettings.load()
            #expect(loaded.baseURL == NeonBridgeSettings.defaultBaseURL)
            #expect(loaded.apiKey == nil)
        }
    }
}
