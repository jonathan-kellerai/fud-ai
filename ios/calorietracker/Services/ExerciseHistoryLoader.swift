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
    static let maxDetailRequests = 50
    static let batchSize = 5

    /// Last performance keyed by `LastPerformanceBuilder.key(for:)`. Bridge failures
    /// give an empty map; a detail request that fails is skipped. Details are fetched
    /// in concurrent batches, newest first, until every wanted exercise is found.
    static func load(
        exerciseNames: [String],
        bridge: NeonBridgeService = .shared
    ) async -> [String: LastPerformance] {
        guard let workouts = try? await bridge.listWorkouts(limit: listLimit) else { return [:] }
        let wanted = Set(exerciseNames.map { LastPerformanceBuilder.key(for: $0) })
        let ids = orderedCandidates(workouts).prefix(maxDetailRequests).map(\.id)
        var found = Set<String>()
        var details: [WorkoutDetailResponse] = []

        for start in stride(from: 0, to: ids.count, by: batchSize) {
            if Task.isCancelled || (!wanted.isEmpty && wanted.isSubset(of: found)) {
                break
            }
            let batch = Array(ids[start..<min(start + batchSize, ids.count)])
            for detail in await fetchDetails(ids: batch, bridge: bridge) {
                details.append(detail)
                for set in detail.sets where set.reps > 0 {
                    found.insert(LastPerformanceBuilder.key(for: set.exercise))
                }
            }
        }
        return LastPerformanceBuilder.build(from: details)
    }

    /// Fetches `ids` concurrently and returns the successes in `ids` order.
    private static func fetchDetails(
        ids: [String],
        bridge: NeonBridgeService
    ) async -> [WorkoutDetailResponse] {
        var results = [WorkoutDetailResponse?](repeating: nil, count: ids.count)
        await withTaskGroup(of: (Int, WorkoutDetailResponse?).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask {
                    let detail = try? await bridge.getWorkout(id: id)
                    return (index, detail)
                }
            }
            for await (index, detail) in group {
                results[index] = detail
            }
        }
        return results.compactMap { $0 }
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
