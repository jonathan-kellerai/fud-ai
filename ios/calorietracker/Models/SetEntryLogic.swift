import Foundation

enum SetEntryLogic {
    static func prefillLoad(sets: [LoggedSet], suggestion: Double?) -> Double {
        sets.last?.weight ?? suggestion ?? 0
    }

    static func isCurrent(setIndex: Int, sets: [LoggedSet]) -> Bool {
        sets.firstIndex { $0.reps == 0 } == setIndex
    }

    static func isPersonalRecord(set: LoggedSet, previous: LastPerformance?) -> Bool {
        set.reps > 0 && previous?.heaviestLoad.map { set.weight > $0 && $0 > 0 } == true
    }

    static func restAfterLogging(exerciseName: String, setIndex: Int, block: ExerciseBlock,
                                 sets: [String: [LoggedSet]]) -> Int? {
        guard let rows = sets[exerciseName], rows.indices.contains(setIndex),
              rows[setIndex].reps > 0 else { return nil }
        return SupersetGrouping.restSeconds(afterLogging: exerciseName, setIndex: setIndex,
                                            in: block, sets: sets)
    }

    static func plannedRowCount(exercise: ProgramV2Exercise, sets: [LoggedSet]) -> Int {
        max(exercise.sets, sets.count)
    }
}
