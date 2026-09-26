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

struct NeonBridgeSettings: Codable {
    var baseURL: String
    var apiKey: String?
    
    static let defaultBaseURL = "https://jl-workout-ingest.vercel.app"
    
    static func load() -> NeonBridgeSettings {
        guard let data = UserDefaults.standard.data(forKey: "neonBridgeSettings"),
              let settings = try? JSONDecoder().decode(NeonBridgeSettings.self, from: data) else {
            return NeonBridgeSettings(baseURL: defaultBaseURL, apiKey: nil)
        }
        return settings
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "neonBridgeSettings")
        }
    }
}
