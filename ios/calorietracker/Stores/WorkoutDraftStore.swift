//
//  WorkoutDraftStore.swift
//  calorietracker
//
//  In-progress JL Neon workout, kept on disk until the bridge confirms the save
//

import Foundation
import Observation

/// Everything the logger needs to rebuild an unsaved session, including a
/// snapshot of the program day so it can be reopened from the Resume card.
struct WorkoutDraft: Codable, Equatable {
    struct Exercise: Codable, Equatable {
        var key: String
        var name: String
        var sets: Int
        var reps: String
        var restLowerSeconds: Int
        var restUpperSeconds: Int
        var rirTarget: String
        var startLoadLb: Double?
        var notes: String
        var loadNote: String
        /// Optional so drafts written before supersets still decode.
        var supersetGroup: String?
    }

    var programDay: String
    var title: String
    var conditioning: String
    var conditioningMinimum: String
    var exercises: [Exercise]
    /// Logged sets keyed by exercise name, same shape as the logger used.
    var sets: [String: [LoggedSet]]
    var conditioningCompleted: Bool
    /// yyyy-MM-dd of the day the session was started.
    var sessionDate: String
    /// When the session was started. Optional so older drafts on disk still decode.
    var startedAt: Date?
    var updatedAt: Date

    init(day: ProgramV2Day, now: Date = Date()) {
        programDay = day.id
        title = day.title
        conditioning = day.conditioning
        conditioningMinimum = day.conditioningMinimum
        exercises = Self.exercises(of: day)
        sets = [:]
        conditioningCompleted = false
        sessionDate = Self.sessionDateString(from: now)
        startedAt = now
        updatedAt = now
    }

    /// Keeps the day snapshot in step with the day the logger is showing, so
    /// the payload lists exercises exactly as the logger did before drafts.
    mutating func adopt(_ day: ProgramV2Day) {
        title = day.title
        conditioning = day.conditioning
        conditioningMinimum = day.conditioningMinimum
        exercises = Self.exercises(of: day)
    }

    private static func exercises(of day: ProgramV2Day) -> [Exercise] {
        day.exercises.map { exercise in
            Exercise(
                key: exercise.key,
                name: exercise.name,
                sets: exercise.sets,
                reps: exercise.reps,
                restLowerSeconds: exercise.restSeconds.lowerBound,
                restUpperSeconds: exercise.restSeconds.upperBound,
                rirTarget: exercise.rirTarget,
                startLoadLb: exercise.startLoadLb,
                notes: exercise.notes,
                loadNote: exercise.loadNote,
                supersetGroup: exercise.supersetGroup
            )
        }
    }

    var loggedSetCount: Int {
        sets.values.reduce(0) { total, loggedSets in
            total + loggedSets.filter { $0.reps > 0 }.count
        }
    }

    /// Rebuilds the program day the draft was started from.
    var programV2Day: ProgramV2Day {
        ProgramV2Day(
            id: programDay,
            title: title,
            conditioning: conditioning,
            conditioningMinimum: conditioningMinimum,
            exercises: exercises.map { exercise in
                ProgramV2Exercise(
                    key: exercise.key,
                    name: exercise.name,
                    sets: exercise.sets,
                    reps: exercise.reps,
                    restSeconds: min(exercise.restLowerSeconds, exercise.restUpperSeconds)...max(exercise.restLowerSeconds, exercise.restUpperSeconds),
                    rirTarget: exercise.rirTarget,
                    startLoadLb: exercise.startLoadLb,
                    notes: exercise.notes,
                    loadNote: exercise.loadNote,
                    supersetGroup: exercise.supersetGroup
                )
            }
        )
    }

    /// The bridge payload, built exactly as the logger built it before drafts existed.
    /// The session date is the day the workout started, not the day it is saved.
    func payload(now: Date = Date()) -> WorkoutPayload {
        var allSets: [WorkoutSet] = []
        var order = 0

        for exercise in exercises {
            if let loggedSets = sets[exercise.name] {
                for set in loggedSets {
                    let rpe = Double(set.rpeText.replacingOccurrences(of: ",", with: "."))
                    allSets.append(WorkoutSet(
                        exercise: exercise.name,
                        load: set.weight,
                        reps: set.reps,
                        rir: set.rir,
                        rpe: rpe,
                        order: order
                    ))
                    order += 1
                }
            }
        }

        // Sets logged under an exercise that has since left the day would
        // otherwise be dropped from the payload and deleted on save.
        let exerciseNames = Set(exercises.map(\.name))
        for name in sets.keys.sorted() where !exerciseNames.contains(name) {
            for set in sets[name] ?? [] {
                let rpe = Double(set.rpeText.replacingOccurrences(of: ",", with: "."))
                allSets.append(WorkoutSet(
                    exercise: name,
                    load: set.weight,
                    reps: set.reps,
                    rir: set.rir,
                    rpe: rpe,
                    order: order
                ))
                order += 1
            }
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let recordedAt = formatter.string(from: now)
        let openedAt = formatter.string(from: startedAt ?? now)

        return WorkoutPayload(
            kind: "COMPLETED",
            programVersion: "program-v2",
            programDay: programDay,
            title: title,
            units: "lb",
            sessionDate: sessionDate,
            conditioning: conditioningCompleted ? conditioning : nil,
            notes: [],
            recordedAtUtc: recordedAt,
            openedAtUtc: openedAt,
            source: "jl-fud-native",
            sets: allSets
        )
    }

    static func sessionDateString(from date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

/// What the Coach "log sets" handoff should do with today's program day.
/// A draft for today just opens the logger, which resumes it; a draft for
/// another day is offered back rather than pushed toward discard.
enum WorkoutHandoffDecision {
    case openToday(ProgramV2Day)
    case offerResume(draft: WorkoutDraft, today: ProgramV2Day)

    static func decide(draft: WorkoutDraft?, today: ProgramV2Day) -> WorkoutHandoffDecision {
        guard let draft, draft.programDay != today.id else { return .openToday(today) }
        return .offerResume(draft: draft, today: today)
    }
}

@Observable
final class WorkoutDraftStore {
    typealias PostWorkout = @MainActor (WorkoutPayload) async throws -> Void

    static let fileName = "jl-workout-draft.json"

    private(set) var draft: WorkoutDraft?
    /// Set when the draft could not be written to disk; the in-memory draft is kept.
    private(set) var persistError: String?

    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// `directory` defaults to Application Support; tests pass a temp dir.
    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory
        draft = Self.load(from: self.directory.appendingPathComponent(Self.fileName))
    }

    /// The draft for `day`, or nil when there is none or it belongs to another day.
    func existingDraft(for day: ProgramV2Day) -> WorkoutDraft? {
        guard let draft, draft.programDay == day.id else { return nil }
        return draft
    }

    /// True when an unsaved session for a different program day is on disk.
    func hasDraft(otherThan day: ProgramV2Day) -> Bool {
        guard let draft else { return false }
        return draft.programDay != day.id
    }

    /// Applies an edit to the draft for `day` (starting one if needed) and writes it to disk.
    /// `startedAt` is only used when a new draft is started.
    func update(_ day: ProgramV2Day, startedAt: Date = Date(), _ change: (inout WorkoutDraft) -> Void) {
        var next = existingDraft(for: day) ?? WorkoutDraft(day: day, now: startedAt)
        next.adopt(day)
        change(&next)
        next.updatedAt = Date()
        draft = next
        persist()
    }

    /// Posts the draft and clears it only once the bridge accepted it.
    /// A failure rethrows and leaves the draft untouched on disk. Edits made
    /// while the post was in flight are kept rather than cleared.
    func save(now: Date = Date(), post: PostWorkout? = nil) async throws {
        guard let snapshot = draft else { return }
        let payload = snapshot.payload(now: now)
        if let post {
            try await post(payload)
        } else {
            _ = try await NeonBridgeService.shared.postWorkout(payload)
        }
        if draft == snapshot {
            clear()
        }
    }

    func discard() {
        clear()
    }

    func dismissPersistError() {
        persistError = nil
    }

    private func clear() {
        draft = nil
        persistError = nil
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            print("Failed to remove workout draft: \(error)")
        }
    }

    private func persist() {
        guard let draft else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(draft)
            try data.write(to: fileURL, options: .atomic)
            persistError = nil
        } catch {
            print("Failed to save workout draft: \(error)")
            persistError = error.localizedDescription
        }
    }

    private static func load(from url: URL) -> WorkoutDraft? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(WorkoutDraft.self, from: data)
        } catch {
            print("Failed to decode workout draft: \(error)")
            return nil
        }
    }
}
