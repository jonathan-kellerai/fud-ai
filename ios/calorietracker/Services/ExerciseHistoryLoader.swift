//
//  ExerciseHistoryLoader.swift
//  calorietracker
//
//  Finds the most recent logged session for each exercise in a program day
//  from the on-device workout log, preferring sessions logged under the same
//  program day and falling back to the newest session from any day. Its
//  answer is what the +5 / -5 lb progression rule reads.
//

import Foundation

enum ExerciseHistoryLoader {
    /// Last performance keyed by `LastPerformanceBuilder.key(for:)`, from every
    /// workout in the log. With `programDay`, sessions from that day win.
    static func load(programDay: String? = nil, log: WorkoutLogStore) -> [String: LastPerformance] {
        let details = orderedCandidates(log.workouts, preferring: programDay).compactMap { log.detail(id: $0.id) }
        return LastPerformanceBuilder.build(from: details, preferredProgramDay: programDay)
    }

    /// Real sessions only, newest session date first, list order breaking ties.
    static func orderedCandidates(_ workouts: [RemoteWorkout]) -> [RemoteWorkout] {
        workouts.enumerated()
            .filter { $0.element.synthetic != true }
            .sorted { lhs, rhs in
                let lhsDay = String(lhs.element.sessionDate.prefix(10))
                let rhsDay = String(rhs.element.sessionDate.prefix(10))
                if lhsDay != rhsDay { return lhsDay > rhsDay }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// `orderedCandidates(_:)` with sessions logged under `programDay` moved
    /// ahead of the rest, each group still newest first. Nil keeps the plain order.
    static func orderedCandidates(_ workouts: [RemoteWorkout], preferring programDay: String?) -> [RemoteWorkout] {
        let ordered = orderedCandidates(workouts)
        guard let programDay else { return ordered }
        let preferred = LastPerformanceBuilder.key(for: programDay)
        let sameDay = ordered.filter { LastPerformanceBuilder.key(for: $0.programDay) == preferred }
        let otherDays = ordered.filter { LastPerformanceBuilder.key(for: $0.programDay) != preferred }
        return sameDay + otherDays
    }
}
