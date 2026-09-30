import Foundation
import Security
import Testing
@testable import calorietracker

/// Memory stand-in for the Keychain. Unsigned CI simulator hosts cannot use the
/// real Keychain, so the storage rules are tested against this instead.
final class MemoryBridgeKeyStore: BridgeKeySecretStore {
    var value: String?
    var failWrites = false
    var failDeletes = false

    init(value: String? = nil) {
        self.value = value
    }

    func upsert(_ value: String) -> Bool {
        if failWrites { return false }
        self.value = value
        return true
    }

    func load() -> String? { value }

    func delete() {
        if !failDeletes { value = nil }
    }
}

/// The bridge key must live in the Keychain (secret store), never in the UserDefaults JSON.
/// Every test restores the UserDefaults entries and the secret store it found.
@Suite(.serialized)
@MainActor
struct BridgeKeyStorageTests {
    private static let defaultsKey = NeonBridgeSettings.storageKey
    private static let pendingKey = NeonBridgeSettings.pendingKeychainWriteKey
    /// Fake values for tests only.
    private static let testKey = "test-bridge-key-not-real"
    private static let testURL = "https://bridge-key-tests.invalid"
    private static let legacyJSON = #"{"baseURL":"https://bridge-key-tests.invalid","apiKey":"test-bridge-key-not-real"}"#

    private func withStore(_ store: MemoryBridgeKeyStore, _ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let savedData = defaults.data(forKey: Self.defaultsKey)
        let savedPending = defaults.object(forKey: Self.pendingKey)
        let savedStore = NeonBridgeSettings.secretStore
        defaults.removeObject(forKey: Self.defaultsKey)
        defaults.removeObject(forKey: Self.pendingKey)
        NeonBridgeSettings.secretStore = store
        defer {
            NeonBridgeSettings.secretStore = savedStore
            if let savedData {
                defaults.set(savedData, forKey: Self.defaultsKey)
            } else {
                defaults.removeObject(forKey: Self.defaultsKey)
            }
            if let savedPending {
                defaults.set(savedPending, forKey: Self.pendingKey)
            } else {
                defaults.removeObject(forKey: Self.pendingKey)
            }
        }
        try body()
    }

    private func storedJSON() throws -> [String: Any] {
        let data = try #require(UserDefaults.standard.data(forKey: Self.defaultsKey))
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private func setLegacyJSON() {
        UserDefaults.standard.set(Data(Self.legacyJSON.utf8), forKey: Self.defaultsKey)
    }

    @Test func appUsesTheKeychainStore() {
        #expect(NeonBridgeSettings.secretStore is KeychainBridgeKeyStore)
        let store = NeonBridgeSettings.secretStore as? KeychainBridgeKeyStore
        #expect(store?.account == NeonBridgeSettings.apiKeyKeychainAccount)
    }

    @Test func saveKeepsKeyInSecretStoreOnly() throws {
        let store = MemoryBridgeKeyStore()
        try withStore(store) {
            #expect(NeonBridgeSettings(baseURL: Self.testURL, apiKey: Self.testKey).save())
            #expect(store.value == Self.testKey)
            let json = try storedJSON()
            #expect(json["baseURL"] as? String == Self.testURL)
            #expect(json.keys.contains("apiKey") == false)
            let raw = try #require(UserDefaults.standard.data(forKey: Self.defaultsKey))
            #expect(String(decoding: raw, as: UTF8.self).contains(Self.testKey) == false)

            let loaded = NeonBridgeSettings.load()
            #expect(loaded.baseURL == Self.testURL)
            #expect(loaded.apiKey == Self.testKey)
        }
    }

    @Test func legacyJSONKeyMigratesToSecretStore() throws {
        let store = MemoryBridgeKeyStore()
        try withStore(store) {
            setLegacyJSON()
            let loaded = NeonBridgeSettings.load()
            #expect(loaded.baseURL == Self.testURL)
            #expect(loaded.apiKey == Self.testKey)
            #expect(store.value == Self.testKey)
            let json = try storedJSON()
            #expect(json.keys.contains("apiKey") == false)
            #expect(NeonBridgeSettings.load().apiKey == Self.testKey)
        }
    }

    @Test func failedMigrationKeepsLegacyCopy() throws {
        let store = MemoryBridgeKeyStore()
        store.failWrites = true
        try withStore(store) {
            setLegacyJSON()
            #expect(NeonBridgeSettings.load().apiKey == Self.testKey)
            let json = try storedJSON()
            #expect(json["apiKey"] as? String == Self.testKey)
        }
    }

    @Test func failedSaveKeepsKeyInDefaultsAndWinsLater() throws {
        let store = MemoryBridgeKeyStore(value: "older-test-bridge-key-not-real")
        try withStore(store) {
            store.failWrites = true
            #expect(NeonBridgeSettings(baseURL: Self.testURL, apiKey: Self.testKey).save() == false)
            let json = try storedJSON()
            #expect(json["apiKey"] as? String == Self.testKey)
            #expect(UserDefaults.standard.bool(forKey: Self.pendingKey))
            // Still unavailable: the newer defaults copy is used, never the older store value.
            #expect(NeonBridgeSettings.load().apiKey == Self.testKey)

            store.failWrites = false
            #expect(NeonBridgeSettings.load().apiKey == Self.testKey)
            #expect(store.value == Self.testKey)
            #expect(UserDefaults.standard.object(forKey: Self.pendingKey) == nil)
            let finalJSON = try storedJSON()
            #expect(finalJSON.keys.contains("apiKey") == false)
        }
    }

    @Test func plainLegacyCopyNeverOverwritesStoredKey() throws {
        let newer = "newer-test-bridge-key-not-real"
        let store = MemoryBridgeKeyStore(value: newer)
        try withStore(store) {
            setLegacyJSON()
            #expect(NeonBridgeSettings.load().apiKey == newer)
            #expect(store.value == newer)
            let finalJSON = try storedJSON()
            #expect(finalJSON.keys.contains("apiKey") == false)
        }
    }

    @Test func nilOrEmptyKeyDeletesStoredKey() throws {
        let store = MemoryBridgeKeyStore()
        try withStore(store) {
            #expect(NeonBridgeSettings(baseURL: Self.testURL, apiKey: Self.testKey).save())
            #expect(NeonBridgeSettings(baseURL: Self.testURL, apiKey: nil).save())
            #expect(store.value == nil)
            #expect(NeonBridgeSettings.load().apiKey == nil)

            #expect(NeonBridgeSettings(baseURL: Self.testURL, apiKey: Self.testKey).save())
            #expect(NeonBridgeSettings(baseURL: Self.testURL, apiKey: "").save())
            #expect(store.value == nil)
        }
    }

    @Test func failedDeleteReportsFailure() throws {
        let store = MemoryBridgeKeyStore(value: Self.testKey)
        store.failDeletes = true
        try withStore(store) {
            #expect(NeonBridgeSettings(baseURL: Self.testURL, apiKey: nil).save() == false)
        }
    }

    @Test func loadWithNothingStoredUsesDefaultURL() throws {
        try withStore(MemoryBridgeKeyStore()) {
            let loaded = NeonBridgeSettings.load()
            #expect(loaded.baseURL == NeonBridgeSettings.defaultBaseURL)
            #expect(loaded.apiKey == nil)
        }
    }
}
