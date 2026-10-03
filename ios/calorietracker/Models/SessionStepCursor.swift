import Foundation

/// Skips are transient session intent, never fabricated rows in the draft.
/// Project them only for nextUp, retaining its authoritative round ordering.
struct SessionStepCursor {
    private(set) var skipped: Set<ExerciseStep> = []

    mutating func skip(_ step: ExerciseStep) { skipped.insert(step) }

    func storageIndex(for step: ExerciseStep) -> Int {
        step.setIndex - skipped.filter { $0.exerciseName == step.exerciseName && $0.setIndex < step.setIndex }.count
    }

    func logicalIndex(exerciseName: String, storageIndex: Int) -> Int {
        var logical = storageIndex
        for step in skipped.filter({ $0.exerciseName == exerciseName }).sorted(by: { $0.setIndex < $1.setIndex }) {
            if step.setIndex <= logical { logical += 1 }
        }
        return logical
    }

    func projectedSets(_ sets: [String: [LoggedSet]], skippedReps: Int = 1) -> [String: [LoggedSet]] {
        var projected = sets
        for step in skipped.sorted(by: { $0.setIndex < $1.setIndex }) {
            var rows = projected[step.exerciseName] ?? []
            // nextUp only returns the first unfinished step, so all preceding
            // steps have already been entered or skipped. No padding is needed.
            guard step.setIndex <= rows.count else { continue }
            rows.insert(LoggedSet(weight: 0, reps: skippedReps, rir: nil, rpeText: ""), at: step.setIndex)
            projected[step.exerciseName] = rows
        }
        return projected
    }

    func next(in blocks: [ExerciseBlock], sets: [String: [LoggedSet]], after: ExerciseStep? = nil) -> ExerciseStep? {
        let start = after.flatMap { step in blocks.firstIndex { $0.exercises.contains { $0.name == step.exerciseName } } } ?? 0
        let projected = projectedSets(sets)
        for block in blocks.dropFirst(start) {
            if let next = SupersetGrouping.nextUp(in: block, sets: projected) { return next }
        }
        return nil
    }
}
