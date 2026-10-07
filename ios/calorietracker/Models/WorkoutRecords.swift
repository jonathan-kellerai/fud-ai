//
//  WorkoutRecords.swift
//  calorietracker
//
//  A JL workout and its sets, kept on this phone in the bridge's JSON shape so
//  saved and imported workouts are one format: what the logger saves, History
//  shows, and last performance, next-in-cycle and Progress read.
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

extension WorkoutPayload {
    /// A saved workout as edited in Workout History. Notes are the non-blank
    /// lines of `notesText`; an empty conditioning field means none.
    static func historyCorrection(
        programVersion: String,
        programDay: String,
        sessionDate: String,
        title: String,
        conditioning: String,
        notesText: String,
        sets: [EditableBridgeSet],
        now: Date = Date()
    ) -> WorkoutPayload {
        let stamp = ISO8601DateFormatter().string(from: now)
        let noteLines = notesText
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return WorkoutPayload(
            kind: "COMPLETED",
            programVersion: programVersion,
            programDay: programDay,
            title: title,
            units: "lb",
            sessionDate: sessionDate,
            conditioning: conditioning.isEmpty ? nil : conditioning,
            notes: noteLines,
            recordedAtUtc: stamp,
            openedAtUtc: stamp,
            source: "jl-fud-native",
            sets: sets.map(\.payload)
        )
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

struct WorkoutDetailResponse: Codable, Equatable {
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
    /// Kept from imported bridge rows; nil for sets saved on this phone.
    var loggedAt: String? = nil

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
        case loggedAt = "logged_at"
    }
}

struct RemoteWorkout: Codable, Identifiable, Equatable {
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
    /// Kept from imported bridge rows; nil for workouts saved on this phone.
    var sourceFingerprint: String? = nil

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
        case sourceFingerprint = "source_fingerprint"
    }
}

// MARK: - On-device log record

/// One workout in the on-device log: the workout and its sets, the versions a
/// correction replaced, and when it was deleted.
struct StoredWorkout: Codable, Equatable {
    var workout: RemoteWorkout
    var sets: [RemoteWorkoutSet]
    /// Versions this one replaced, oldest first.
    var revisions: [WorkoutRevision] = []
    /// ISO-8601, set by Delete. The record stays (without its sets) so a
    /// re-import can't bring the workout back; nothing reads it as a workout.
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case workout, sets, revisions
        case deletedAt = "deleted_at"
    }

    init(workout: RemoteWorkout, sets: [RemoteWorkoutSet], revisions: [WorkoutRevision] = [], deletedAt: String? = nil) {
        self.workout = workout
        self.sets = sets
        self.revisions = revisions
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workout = try container.decode(RemoteWorkout.self, forKey: .workout)
        sets = try container.decode([RemoteWorkoutSet].self, forKey: .sets)
        revisions = try container.decodeIfPresent([WorkoutRevision].self, forKey: .revisions) ?? []
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
    }

    /// A workout saved on this phone from the logger (or a correction).
    /// Sets are numbered by their order in the session.
    init(id: String, payload: WorkoutPayload) {
        workout = RemoteWorkout(
            id: id,
            kind: payload.kind,
            programVersion: payload.programVersion,
            programDay: payload.programDay,
            title: payload.title,
            units: payload.units,
            sessionDate: payload.sessionDate,
            conditioning: payload.conditioning,
            notes: payload.notes,
            contentHash: nil,
            synthetic: false,
            recordedAt: payload.recordedAtUtc
        )
        sets = Self.sets(payload.sets, workoutID: id)
        revisions = []
        deletedAt = nil
    }

    var isDeleted: Bool { deletedAt != nil }

    var detail: WorkoutDetailResponse {
        WorkoutDetailResponse(workout: workout, sets: sets)
    }

    /// Every content hash this record has carried, current and replaced.
    var contentHashes: [String] {
        ([workout.contentHash] + revisions.map(\.workout.contentHash)).compactMap { $0 }
    }

    static func sets(_ sets: [WorkoutSet], workoutID: String) -> [RemoteWorkoutSet] {
        sets.map { set in
            RemoteWorkoutSet(
                id: String(set.order),
                workoutId: workoutID,
                setOrder: set.order,
                exercise: set.exercise,
                loadLb: set.load,
                reps: set.reps,
                rir: set.rir,
                rpe: set.rpe,
                exercisePosition: set.exercisePosition,
                plannedPosition: set.plannedPosition
            )
        }
    }
}

/// A version of a workout that a correction replaced.
struct WorkoutRevision: Codable, Equatable {
    /// ISO-8601.
    var replacedAt: String
    var workout: RemoteWorkout
    var sets: [RemoteWorkoutSet]

    enum CodingKeys: String, CodingKey {
        case replacedAt = "replaced_at"
        case workout, sets
    }
}

/// Decodes one element, turning a malformed one into nil instead of failing the list.
struct WorkoutLossy<Value: Decodable>: Decodable {
    var value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
