//
//  WorkoutLoggerLogic.swift
//  calorietracker
//
//  Pure rules behind the Program V2 logger: superset blocks, rest timing,
//  last-session history and the next suggested load.
//

import Foundation

// MARK: - Superset blocks

/// One exercise, or an ordered superset of two or more done back to back.
struct ExerciseBlock: Identifiable {
    let exercises: [ProgramV2Exercise]

    var id: UUID { exercises.first?.id ?? UUID() }
    var isSuperset: Bool { exercises.count > 1 }

    /// "A", "B", "C" for superset members.
    static func memberLabel(at index: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard letters.indices.contains(index) else { return "\(index + 1)" }
        return String(letters[index])
    }

    func memberLabel(for exerciseName: String) -> String? {
        guard let index = exercises.firstIndex(where: { $0.name == exerciseName }) else { return nil }
        return Self.memberLabel(at: index)
    }
}

/// The next set to do inside a superset.
struct ExerciseStep: Equatable, Hashable {
    let exerciseName: String
    let setIndex: Int
}

enum SupersetGrouping {
    /// Fallback rest when every member of a superset has 0 s rest.
    static let defaultSupersetRestSeconds = 60

    /// Consecutive exercises with the same `supersetGroup` form one block. With no
    /// explicit group, an exercise with 0 s rest is paired with the next one.
    static func blocks(for exercises: [ProgramV2Exercise]) -> [ExerciseBlock] {
        var blocks: [ExerciseBlock] = []
        var current: [ProgramV2Exercise] = []
        for exercise in exercises {
            if let previous = current.last, joins(previous, exercise) {
                current.append(exercise)
            } else {
                if !current.isEmpty {
                    blocks.append(ExerciseBlock(exercises: current))
                }
                current = [exercise]
            }
        }
        if !current.isEmpty {
            blocks.append(ExerciseBlock(exercises: current))
        }
        return blocks
    }

    private static func joins(_ previous: ProgramV2Exercise, _ next: ProgramV2Exercise) -> Bool {
        let previousGroup = normalizedGroup(previous.supersetGroup)
        let nextGroup = normalizedGroup(next.supersetGroup)
        if let previousGroup {
            return previousGroup == nextGroup
        }
        if nextGroup != nil {
            return false
        }
        return previous.restSeconds.upperBound == 0
    }

    private static func normalizedGroup(_ group: String?) -> String? {
        guard let trimmed = group?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Seconds to rest after logging `setIndex` of `exerciseName`, or nil for no timer.
    /// A superset rests once per round, only after logging its last member with
    /// every member's set `setIndex` logged. Logging an earlier member never rests.
    static func restSeconds(
        afterLogging exerciseName: String,
        setIndex: Int,
        in block: ExerciseBlock,
        sets: [String: [LoggedSet]]
    ) -> Int? {
        guard block.exercises.contains(where: { $0.name == exerciseName }) else { return nil }
        guard block.isSuperset else {
            let rest = block.exercises.first?.restSeconds.lowerBound ?? 0
            return rest > 0 ? rest : nil
        }
        guard block.exercises.last?.name == exerciseName else { return nil }
        let roundComplete = block.exercises.allSatisfy { exercise in
            isLogged(sets[exercise.name], at: setIndex)
        }
        return roundComplete ? supersetRestSeconds(for: block) : nil
    }

    /// Rest of the last member, else the largest member rest, else 60 s.
    static func supersetRestSeconds(for block: ExerciseBlock) -> Int {
        if let last = block.exercises.last?.restSeconds.lowerBound, last > 0 {
            return last
        }
        let largest = block.exercises.map(\.restSeconds.lowerBound).max() ?? 0
        return largest > 0 ? largest : defaultSupersetRestSeconds
    }

    /// A1, B1, A2, B2...: the first unlogged member in the first unfinished round.
    static func nextUp(in block: ExerciseBlock, sets: [String: [LoggedSet]]) -> ExerciseStep? {
        let counts = block.exercises.map { exercise in
            SetEntryLogic.plannedRowCount(exercise: exercise, sets: sets[exercise.name] ?? [])
        }
        let rounds = counts.max() ?? 0
        for round in 0..<rounds {
            for (index, exercise) in block.exercises.enumerated() where round < counts[index] {
                if !isLogged(sets[exercise.name], at: round) {
                    return ExerciseStep(exerciseName: exercise.name, setIndex: round)
                }
            }
        }
        return nil
    }

    private static func isLogged(_ sets: [LoggedSet]?, at index: Int) -> Bool {
        guard let sets, sets.indices.contains(index) else { return false }
        return sets[index].reps > 0
    }
}

// MARK: - Last session

struct WorkingSetSummary: Equatable {
    let load: Double
    let reps: Int
    let rir: Int?
}

/// The most recent session that included an exercise.
struct LastPerformance: Equatable {
    let sessionDate: String
    let sets: [WorkingSetSummary]
    var doneLaterThanPlanned: Bool = false

    var firstSet: WorkingSetSummary? { sets.first }
    var heaviestLoad: Double? { sets.map(\.load).max() }
}

enum LastPerformanceBuilder {
    static func key(for exerciseName: String) -> String {
        exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// `details` newest first. The first session containing an exercise wins,
    /// whichever program day it was logged under. With `preferredProgramDay`,
    /// sessions logged under that day win over other days; an exercise with
    /// no same-day session falls back to the newest other-day one.
    static func build(
        from details: [WorkoutDetailResponse],
        preferredProgramDay: String? = nil
    ) -> [String: LastPerformance] {
        var ordered = details
        if let preferredProgramDay {
            let preferred = key(for: preferredProgramDay)
            let sameDay = details.filter { key(for: $0.workout.programDay) == preferred }
            let otherDays = details.filter { key(for: $0.workout.programDay) != preferred }
            ordered = sameDay + otherDays
        }
        var result: [String: LastPerformance] = [:]
        for detail in ordered {
            var byExercise: [String: [RemoteWorkoutSet]] = [:]
            for set in detail.sets where set.reps > 0 {
                byExercise[key(for: set.exercise), default: []].append(set)
            }
            for (exerciseKey, sets) in byExercise where result[exerciseKey] == nil {
                let summaries = sets
                    .sorted { $0.setOrder < $1.setOrder }
                    .map { WorkingSetSummary(load: $0.loadLb, reps: $0.reps, rir: $0.rir) }
                result[exerciseKey] = LastPerformance(
                    sessionDate: String(detail.workout.sessionDate.prefix(10)),
                    sets: summaries,
                    doneLaterThanPlanned: sets.contains { row in
                        guard let performed = row.exercisePosition, let planned = row.plannedPosition else { return false }
                        return performed > planned
                    }
                )
            }
        }
        return result
    }
}

// MARK: - Progression

struct RepRange: Equatable {
    let low: Int
    let high: Int
}

enum ProgressionReason: Equatable {
    case increase, decrease, hold, holdPreFatigued, holdReductionWeek, noHistory
}

struct ProgressionDecision: Equatable {
    let load: Double?
    let reason: ProgressionReason
}

enum ProgressionRule {
    static let incrementLb: Double = 5

    /// "10-15", "10–15", "8", "8-12/leg" -> low/high. A single number is both.
    static func repRange(_ reps: String) -> RepRange? {
        let pattern = #"(\d+)(?:\s*[-–—]\s*(\d+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(reps.startIndex..., in: reps)
        guard let match = regex.firstMatch(in: reps, range: range),
              let lowRange = Range(match.range(at: 1), in: reps),
              let low = Int(reps[lowRange]) else {
            return nil
        }
        if let highRange = Range(match.range(at: 2), in: reps), let high = Int(reps[highRange]) {
            return RepRange(low: min(low, high), high: max(low, high))
        }
        return RepRange(low: low, high: low)
    }

    /// Set 1 of the last session: top of the range with 4+ RIR adds 5 lb, missing the
    /// bottom of the range or hitting 0 RIR drops 5 lb, anything else holds.
    /// No history falls back to the program start load (nil when it is picked on the day).
    static func suggestedLoad(last: LastPerformance?, reps: String, startLoadLb: Double?, holdLoads: Bool = false,
                              doneLaterThanPlanned: Bool = false) -> Double? {
        suggestedDecision(last: last, reps: reps, startLoadLb: startLoadLb, holdLoads: holdLoads,
                          doneLaterThanPlanned: doneLaterThanPlanned).load
    }

    static func suggestedDecision(last: LastPerformance?, reps: String, startLoadLb: Double?,
                                  holdLoads: Bool = false, doneLaterThanPlanned: Bool = false) -> ProgressionDecision {
        guard let last, let first = last.firstSet else {
            return ProgressionDecision(load: startLoadLb, reason: .noHistory)
        }
        if holdLoads {
            return ProgressionDecision(load: last.sets.last?.load ?? first.load, reason: .holdReductionWeek)
        }
        guard first.load > 0 else { return ProgressionDecision(load: 0, reason: .hold) }
        guard let range = repRange(reps) else { return ProgressionDecision(load: first.load, reason: .hold) }
        let preFatigued = last.doneLaterThanPlanned || doneLaterThanPlanned
        let decision = adjustedDecision(after: first, range: range, doneLaterThanPlanned: preFatigued)
        // History still progresses from set 1. A later missed set explains why
        // the baseline holds after pre-exhaustion (the 9/29 chest-press case).
        if decision.reason != .increase, preFatigued,
           last.sets.contains(where: { $0.reps < range.low || $0.rir == 0 }) {
            return ProgressionDecision(load: first.load, reason: .holdPreFatigued)
        }
        return decision
    }

    static func adjustedLoad(after first: WorkingSetSummary, range: RepRange) -> Double {
        adjustedDecision(after: first, range: range).load ?? first.load
    }

    static func adjustedDecision(after first: WorkingSetSummary, range: RepRange?,
                                 doneLaterThanPlanned: Bool = false, holdLoads: Bool = false) -> ProgressionDecision {
        if holdLoads { return ProgressionDecision(load: first.load, reason: .holdReductionWeek) }
        guard first.load > 0 else { return ProgressionDecision(load: 0, reason: .hold) }
        guard let range else { return ProgressionDecision(load: first.load, reason: .hold) }
        if first.reps >= range.high, let rir = first.rir, rir >= 4 {
            return ProgressionDecision(load: first.load + incrementLb, reason: .increase)
        }
        if first.reps < range.low || first.rir == 0 {
            if doneLaterThanPlanned {
                return ProgressionDecision(load: first.load, reason: .holdPreFatigued)
            }
            return ProgressionDecision(load: max(0, first.load - incrementLb), reason: .decrease)
        }
        return ProgressionDecision(load: first.load, reason: .hold)
    }
}

// MARK: - Prefill refresh

enum PrefillRefresh {
    /// Once history arrives, sets added before it keep the no-history prefill
    /// (start load, else 0). Untouched ones (0 reps, still that load) take the
    /// suggestion. `suggestions` is keyed by exercise name. Returns the new set
    /// list for each exercise that changes; empty when nothing does.
    static func refreshedSets(
        exercises: [ProgramV2Exercise],
        sets: [String: [LoggedSet]],
        suggestions: [String: Double]
    ) -> [String: [LoggedSet]] {
        var result: [String: [LoggedSet]] = [:]
        for exercise in exercises where result[exercise.name] == nil {
            guard let suggestion = suggestions[exercise.name],
                  var exerciseSets = sets[exercise.name] else { continue }
            let noHistoryPrefill = exercise.startLoadLb ?? 0
            guard suggestion != noHistoryPrefill else { continue }
            var changed = false
            for index in exerciseSets.indices
            where exerciseSets[index].reps == 0 && exerciseSets[index].weight == noHistoryPrefill {
                exerciseSets[index].weight = suggestion
                changed = true
            }
            if changed {
                result[exercise.name] = exerciseSets
            }
        }
        return result
    }
}

// MARK: - Formatting

enum LoggerFormatting {
    /// 110 -> "110", 112.5 -> "112.5".
    static func load(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1_000_000 {
            return String(Int(value))
        }
        return String(value)
    }

    /// "Last: 110 × 12 @ RIR 2" from set 1 of the last session.
    static func lastLine(_ performance: LastPerformance) -> String? {
        guard let first = performance.firstSet else { return nil }
        var text = "Last: \(load(first.load)) × \(first.reps)"
        if let rir = first.rir {
            text += " @ RIR \(rir)"
        }
        return text
    }
}
