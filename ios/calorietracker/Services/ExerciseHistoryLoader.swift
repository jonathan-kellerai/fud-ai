//
//  ExerciseHistoryLoader.swift
//  calorietracker
//
//  Finds the most recent logged session for each exercise in a program day,
//  across every program day, from the Neon bridge workout history.
//

import Foundation

enum ExerciseHistoryLoader {
    static let listLimit = 50
    static let maxDetailRequests = 15

    /// Last performance keyed by `LastPerformanceBuilder.key(for:)`. Bridge failures
    /// give an empty map; a detail request that fails is skipped.
    static func load(
        exerciseNames: [String],
        bridge: NeonBridgeService = .shared
    ) async -> [String: LastPerformance] {
        guard let workouts = try? await bridge.listWorkouts(limit: listLimit) else { return [:] }
        let wanted = Set(exerciseNames.map { LastPerformanceBuilder.key(for: $0) })
        var found = Set<String>()
        var details: [WorkoutDetailResponse] = []

        for workout in orderedCandidates(workouts).prefix(maxDetailRequests) {
            if Task.isCancelled || (!wanted.isEmpty && wanted.isSubset(of: found)) {
                break
            }
            guard let detail = try? await bridge.getWorkout(id: workout.id) else { continue }
            details.append(detail)
            for set in detail.sets where set.reps > 0 {
                found.insert(LastPerformanceBuilder.key(for: set.exercise))
            }
        }
        return LastPerformanceBuilder.build(from: details)
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
}
