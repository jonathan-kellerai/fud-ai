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

    @Test func everyBridgeClientSendsTheConfiguredSecretStoreKey() async throws {
        // Load through the real settings/secret-store contract, restoring defaults
        // before awaiting network calls so other settings tests cannot see test state.
        var configuredSettings: NeonBridgeSettings?
        try withStore(MemoryBridgeKeyStore()) {
            #expect(NeonBridgeSettings(baseURL: Self.testURL, apiKey: Self.testKey).save())
            configuredSettings = NeonBridgeSettings.load()
            #expect(configuredSettings?.apiKey == Self.testKey)
            let json = try storedJSON()
            #expect(json["apiKey"] == nil)
        }

        let bridge = NeonBridgeService.shared
        let savedSettings = bridge.settings
        bridge.settings = try #require(configuredSettings)
        BridgeAuthorizationURLProtocol.requestLog.reset()
        #expect(URLProtocol.registerClass(BridgeAuthorizationURLProtocol.self))
        defer {
            URLProtocol.unregisterClass(BridgeAuthorizationURLProtocol.self)
            BridgeAuthorizationURLProtocol.requestLog.reset()
            bridge.settings = savedSettings
        }

        _ = try await bridge.checkHealth()
        _ = try await bridge.listWorkouts(limit: 1)
        _ = try await bridge.getWorkout(id: "auth-test-workout")
        var draft = WorkoutDraft(day: ProgramV2Templates.day1LowerA, now: Date(timeIntervalSince1970: 100))
        draft.sets[draft.exercises[0].name] = [LoggedSet(weight: 145, reps: 12, rir: 2, rpeText: "")]
        _ = try await bridge.postWorkout(draft.payload(now: Date(timeIntervalSince1970: 200)))
        _ = try await bridge.activeProgram()
        // Foreground, HealthKit observer, and BGAppRefresh step sync all use this call.
        _ = try await bridge.postSteps(StepsPayload(date: "2026-10-03", steps: 1234,
                                                   device: "Apple Health", source: "jl-fud-native-healthkit"))
        _ = try await CCLadderClient.fetchLadders(settings: bridge.settings)
        try await CCLadderClient.postEvent(CCLadderEventRequest(series: "pushup", eventType: "manual_step",
            fromStep: 1, toStep: 2, reason: "auth test", createdBy: "app"), settings: bridge.settings)
        let progressConfig = ProgressTrainingLoader.currentConfig()
        #expect(progressConfig.apiKey == Self.testKey)
        _ = try await ProgressTrainingAPI.fetchWorkouts(config: progressConfig, limit: 1)
        _ = try await ProgressTrainingAPI.fetchWorkoutTotals(config: progressConfig, id: "auth-test-workout")

        let requests = BridgeAuthorizationURLProtocol.requestLog.snapshot()
        #expect(requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" } == [
            "GET /api/bridge/health",
            "GET /api/workouts",
            "GET /api/workouts/auth-test-workout",
            "POST /api/workouts",
            "GET /api/programs/active",
            "POST /api/steps",
            "GET /api/cc/ladders",
            "POST /api/cc/events",
            "GET /api/workouts",
            "GET /api/workouts/auth-test-workout",
        ])
        for request in requests {
            #expect(request.url?.host == "bridge-key-tests.invalid")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.testKey)")
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

/// URLProtocol callbacks run on loading threads; every access to the mutable
/// request log is protected by this lock, including reset and snapshot.
nonisolated private final class BridgeAuthorizationRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
    }

    func snapshot() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        requests = []
    }
}

/// Recording transport is necessary to prove what URLSession sends without
/// production writes. It only intercepts the reserved .invalid test host.
/// URLProtocol requires restating inherited unchecked Sendable: this subclass
/// adds no mutable instance state, and its shared log is lock-protected above.
nonisolated private final class BridgeAuthorizationURLProtocol: URLProtocol, @unchecked Sendable {
    static let requestLog = BridgeAuthorizationRequestLog()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "bridge-key-tests.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestLog.record(request)
        let json: String
        switch (request.httpMethod, request.url?.path) {
        case ("GET", "/api/bridge/health"):
            json = #"{"ok":true,"service":"test","program":"v2","program_version":"v2","workouts":"ok","steps":"ok","steps_target":10000}"#
        case ("GET", "/api/workouts"):
            json = #"{"workouts":[]}"#
        case ("GET", "/api/workouts/auth-test-workout"):
            json = #"{"workout":{"id":"auth-test-workout","kind":"COMPLETED","program_version":"v2","program_day":"Day1_LowerA","title":"Lower A","units":"lb","session_date":"2026-10-03","notes":[]},"sets":[]}"#
        case ("POST", "/api/workouts"):
            json = #"{"id":"auth-test-workout","ok":true}"#
        case ("GET", "/api/programs/active"):
            json = #"{"id":"auth-test-program","lineage_id":"auth-test-lineage","version":1,"name":"Test","status":"active"}"#
        case ("POST", "/api/steps"):
            json = #"{"ok":true,"date":"2026-10-03","steps":1234}"#
        case ("GET", "/api/cc/ladders"):
            json = #"{"series":[]}"#
        case ("POST", "/api/cc/events"):
            json = #"{"ok":true}"#
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                             headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
