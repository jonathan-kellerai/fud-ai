//
//  WorkoutRecords.swift
//  calorietracker
//
//  A JL workout and its sets, in the bridge's JSON shape: the logger's
//  payload, History's rows, and what last performance and next-in-cycle read.
//

import Foundation

// MARK: - Workout Payload

struct WorkoutSet: Codable, Equatable, Hashable {
    let exercise: String
    let load: Double
    let reps: Int
    let rir: Int?
    let rpe: Double?
    let order: Int
    var exercisePosition: Int? = nil
    var plannedPosition: Int? = nil

    enum CodingKeys: String, CodingKey {
        case exercise, load, reps, rir, rpe, order
        case exercisePosition = "exercise_position"
        case plannedPosition = "planned_position"
    }
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

/// The history editor's plain values and bridge conversion live together.
struct EditableBridgeSet: Identifiable {
    let id: String
    var exercise: String
    var load: Double
    var reps: Int
    var rir: Int?
    var rpeText: String
    let order: Int
    let exercisePosition: Int?
    let plannedPosition: Int?

    init(_ set: RemoteWorkoutSet) {
        id = set.id
        exercise = set.exercise
        load = set.loadLb
        reps = set.reps
        rir = set.rir
        rpeText = set.rpe.map { String($0) } ?? ""
        order = set.setOrder
        exercisePosition = set.exercisePosition
        plannedPosition = set.plannedPosition
    }

    var payload: WorkoutSet {
        WorkoutSet(exercise: exercise, load: load, reps: reps, rir: rir,
                   rpe: Double(rpeText.replacingOccurrences(of: ",", with: ".")), order: order,
                   exercisePosition: exercisePosition, plannedPosition: plannedPosition)
    }
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
    var exercisePosition: Int? = nil
    var plannedPosition: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case workoutId = "workout_id"
        case setOrder = "set_order"
        case exercise
        case loadLb = "load_lb"
        case reps
        case rir
        case rpe
        case exercisePosition = "exercise_position"
        case plannedPosition = "planned_position"
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
