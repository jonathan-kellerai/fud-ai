//
//  NeonBridgeModels.swift
//  calorietracker
//
//  JL Physical — Neon training bridge models
//

import Foundation

// MARK: - Bridge Health

struct BridgeHealth: Codable {
    let ok: Bool
    let service: String
    let program: String
    let programVersion: String
    let workouts: String
    let steps: String
    let stepsTarget: Int
    
    enum CodingKeys: String, CodingKey {
        case ok
        case service
        case program
        case programVersion = "program_version"
        case workouts
        case steps
        case stepsTarget = "steps_target"
    }
}

// MARK: - Workout Payload

struct WorkoutSet: Codable, Equatable, Hashable {
    let exercise: String
    let load: Double
    let reps: Int
    let rir: Int?
    let rpe: Double?
    let order: Int
}

struct WorkoutPayload: Codable {
    let kind: String
    let programVersion: String
    let programDay: String
    let title: String
    let units: String
    let sessionDate: String
    let conditioning: String?
    let notes: [String]
    let recordedAtUtc: String
    let openedAtUtc: String
    let source: String
    let sets: [WorkoutSet]
    
    enum CodingKeys: String, CodingKey {
        case kind
        case programVersion = "program_version"
        case programDay = "program_day"
        case title
        case units
        case sessionDate = "session_date"
        case conditioning
        case notes
        case recordedAtUtc = "recorded_at_utc"
        case openedAtUtc = "opened_at_utc"
        case source
        case sets
    }
}

// MARK: - Workout Response

struct WorkoutResponse: Codable {
    let id: String?
    let ok: Bool?
    let message: String?
    let deduped: Bool?
    let action: String?
    let contentHash: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case ok
        case message
        case deduped
        case action
        case contentHash = "content_hash"
    }
}

struct ListWorkoutsResponse: Codable {
    let workouts: [RemoteWorkout]
}

struct WorkoutDetailResponse: Codable {
    let workout: RemoteWorkout
    let sets: [RemoteWorkoutSet]
}

struct RemoteWorkoutSet: Codable, Identifiable, Equatable {
    let id: String
    let workoutId: String?
    let setOrder: Int
    let exercise: String
    let loadLb: Double
    let reps: Int
    let rir: Int?
    let rpe: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case workoutId = "workout_id"
        case setOrder = "set_order"
        case exercise
        case loadLb = "load_lb"
        case reps
        case rir
        case rpe
    }
}

struct RemoteWorkout: Codable, Identifiable {
    let id: String
    let kind: String
    let programVersion: String
    let programDay: String
    let title: String
    let units: String
    let sessionDate: String
    let conditioning: String?
    let notes: [String]
    let contentHash: String?
    let synthetic: Bool?
    let recordedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case programVersion = "program_version"
        case programDay = "program_day"
        case title
        case units
        case sessionDate = "session_date"
        case conditioning
        case notes
        case contentHash = "content_hash"
        case synthetic
        case recordedAt = "recorded_at"
    }
}

// MARK: - Steps Payload

struct StepsPayload: Codable {
    let date: String?
    let steps: Int
    let device: String
    let source: String
}

struct StepsResponse: Codable {
    let ok: Bool
    let date: String?
    let steps: Int?
    let met: Bool?
    let remaining: Int?
    let action: String?
    let previousSteps: Int?
    let message: String?
    
    enum CodingKeys: String, CodingKey {
        case ok
        case date
        case steps
        case met
        case remaining
        case action
        case previousSteps = "previous_steps"
        case message
    }
}

struct StepsDay: Codable, Identifiable {
    let date: String
    let steps: Int?
    let met: Bool?
    let logged: Bool
    let source: String?
    let device: String?
    let origin: String?
    
    var id: String { date }
}

struct StepsSummary: Codable {
    let daysLogged: Int
    let daysMet: Int
    let avgSteps: Double?
    
    enum CodingKeys: String, CodingKey {
        case daysLogged = "days_logged"
        case daysMet = "days_met"
        case avgSteps = "avg_steps"
    }
}

struct StepsListResponse: Codable {
    let ok: Bool
    let programVersion: String
    let target: Int
    let startDate: String
    let today: String
    let from: String
    let days: Int
    let rows: [String]
    let series: [StepsDay]
    let summary: StepsSummary
    
    enum CodingKeys: String, CodingKey {
        case ok
        case programVersion = "program_version"
        case target
        case startDate = "start_date"
        case today
        case from
        case days
        case rows
        case series
        case summary
    }
}

// MARK: - Bridge Settings

/// Storage for the bridge bearer key.
protocol BridgeKeySecretStore {
    /// True only when the value was written.
    func upsert(_ value: String) -> Bool
    func load() -> String?
    func delete()
}

struct KeychainBridgeKeyStore: BridgeKeySecretStore {
    let account: String

    /// The bridge account goes through NeonBridgeKeychain, so the key is stored
    /// ThisDeviceOnly (out of iCloud backup) and its test hooks apply.
    private var isBridgeAccount: Bool { account == NeonBridgeKeychain.account }

    func upsert(_ value: String) -> Bool {
        isBridgeAccount ? NeonBridgeKeychain.save(value) : KeychainHelper.upsert(key: account, value: value)
    }
    func load() -> String? {
        isBridgeAccount ? NeonBridgeKeychain.load() : KeychainHelper.load(key: account)
    }
    func delete() {
        isBridgeAccount ? NeonBridgeKeychain.delete() : KeychainHelper.delete(key: account)
    }
}

struct NeonBridgeSettings: Codable {
    var baseURL: String
    var apiKey: String?

    static let defaultBaseURL = "https://jl-workout-ingest.vercel.app"
    
    static let storageKey = "neonBridgeSettings"
    /// The bridge key lives in the Keychain under this account, never in UserDefaults.
    static let apiKeyKeychainAccount = NeonBridgeKeychain.account
    /// Set only when save() could not write the Keychain and kept the key in defaults.
    static let pendingKeychainWriteKey = "neonBridgeApiKeyPendingKeychainWrite"
    /// Where the key is kept. The Keychain in the app; tests swap in a memory store
    /// because unsigned CI simulator hosts have no Keychain access.
    static var secretStore: any BridgeKeySecretStore = KeychainBridgeKeyStore(account: apiKeyKeychainAccount)

    /// What goes to UserDefaults: the URL only.
    private struct Persisted: Codable {
        var baseURL: String
    }

    static func load() -> NeonBridgeSettings {
        var baseURL = defaultBaseURL
        var legacyKey: String?
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode(NeonBridgeSettings.self, from: data) {
            baseURL = stored.baseURL
            legacyKey = stored.apiKey
        }
        if let legacyKey, !legacyKey.isEmpty {
            let pending = UserDefaults.standard.bool(forKey: pendingKeychainWriteKey)
            let keychainKey = secretStore.load()
            if !pending, let keychainKey, !keychainKey.isEmpty {
                // Plain legacy copy (older build or restored defaults): the Keychain value
                // is authoritative, so never overwrite it with the older copy.
                writeDefaults(baseURL: baseURL)
                return NeonBridgeSettings(baseURL: baseURL, apiKey: keychainKey)
            }
            // Older build with an empty Keychain, or a save() whose Keychain write failed
            // (pending flag): the defaults copy is the newest. Drop it only once the
            // Keychain verifiably holds the same value.
            if storeInKeychain(legacyKey) {
                writeDefaults(baseURL: baseURL)
            }
            return NeonBridgeSettings(baseURL: baseURL, apiKey: legacyKey)
        }
        if legacyKey != nil {
            // An empty legacy key carries nothing worth keeping.
            writeDefaults(baseURL: baseURL)
        }
        let apiKey = secretStore.load()
        return NeonBridgeSettings(baseURL: baseURL, apiKey: apiKey)
    }

    /// Returns false if the Keychain write failed; the key is then kept in the
    /// UserDefaults JSON so it is never lost.
    @discardableResult
    func save() -> Bool {
        guard let apiKey, !apiKey.isEmpty else {
            Self.secretStore.delete()
            Self.writeDefaults(baseURL: baseURL)
            // Report failure if the Keychain item survived the delete.
            return Self.secretStore.load() == nil
        }
        if Self.storeInKeychain(apiKey) {
            Self.writeDefaults(baseURL: baseURL)
            return true
        }
        Self.writeLegacyDefaults(baseURL: baseURL, apiKey: apiKey)
        return false
    }

    private static func storeInKeychain(_ value: String) -> Bool {
        guard secretStore.upsert(value) else { return false }
        return secretStore.load() == value
    }

    private static func writeDefaults(baseURL: String) {
        if let data = try? JSONEncoder().encode(Persisted(baseURL: baseURL)) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        UserDefaults.standard.removeObject(forKey: pendingKeychainWriteKey)
    }

    private static func writeLegacyDefaults(baseURL: String, apiKey: String) {
        if let data = try? JSONEncoder().encode(NeonBridgeSettings(baseURL: baseURL, apiKey: apiKey)) {
            UserDefaults.standard.set(data, forKey: storageKey)
            // Marks this copy as newer than whatever the Keychain holds.
            UserDefaults.standard.set(true, forKey: pendingKeychainWriteKey)
        }
    }
}
