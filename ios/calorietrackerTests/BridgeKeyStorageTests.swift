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
        defaults.removeObject(forKey: Self.defaultsKey)
        KeychainHelper.delete(key: Self.account)
        defer {
            if let savedData {
                defaults.set(savedData, forKey: Self.defaultsKey)
            } else {
                defaults.removeObject(forKey: Self.defaultsKey)
            }
            if let savedKey {
                KeychainHelper.save(key: Self.account, value: savedKey)
            } else {
                KeychainHelper.delete(key: Self.account)
            }
        }
        try body()
    }

    /// CI builds the test host unsigned. If that host cannot use the Keychain,
    /// say so in the log (the CI grep prints lines with the suite name).
    private static func keychainAvailable() -> Bool {
        let probe = account + ".probe"
        KeychainHelper.save(key: probe, value: "probe")
        let works = KeychainHelper.load(key: probe) == "probe"
        KeychainHelper.delete(key: probe)
        if !works {
            print("BridgeKeyStorageTests: Keychain unavailable in this test host; Keychain assertions skipped.")
        }
        return works
    }

    private func storedJSON() throws -> [String: Any] {
        let data = try #require(UserDefaults.standard.data(forKey: Self.defaultsKey))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func saveKeepsKeyInKeychainOnly() throws {
        try withCleanState {
            NeonBridgeSettings(baseURL: Self.testURL, apiKey: Self.testKey).save()

            let json = try storedJSON()
            #expect(json["baseURL"] as? String == Self.testURL)
            #expect(json["apiKey"] == nil)
            let raw = try #require(UserDefaults.standard.data(forKey: Self.defaultsKey))
            #expect(String(decoding: raw, as: UTF8.self).contains(Self.testKey) == false)

            guard Self.keychainAvailable() else { return }
            #expect(KeychainHelper.load(key: Self.account) == Self.testKey)

            let loaded = NeonBridgeSettings.load()
            #expect(loaded.baseURL == Self.testURL)
            #expect(loaded.apiKey == Self.testKey)
        }
    }

    @Test func legacyJSONKeyMigratesToKeychain() throws {
        guard Self.keychainAvailable() else { return }
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

    @Test func nilOrEmptyKeyDeletesKeychainItem() throws {
        guard Self.keychainAvailable() else { return }
        try withCleanState {
            NeonBridgeSettings(baseURL: Self.testURL, apiKey: Self.testKey).save()
            #expect(KeychainHelper.load(key: Self.account) == Self.testKey)

            NeonBridgeSettings(baseURL: Self.testURL, apiKey: nil).save()
            #expect(KeychainHelper.load(key: Self.account) == nil)
            #expect(NeonBridgeSettings.load().apiKey == nil)

            NeonBridgeSettings(baseURL: Self.testURL, apiKey: Self.testKey).save()
            NeonBridgeSettings(baseURL: Self.testURL, apiKey: "").save()
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
