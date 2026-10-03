import Foundation

enum SetEntryLogic {
    /// Kept outside the draft until logged: prefilled reps must not mark a row done.
    struct Prefill: Equatable {
        let decision: ProgressionDecision
        let reps: Int
        let rir: Int?
        var load: Double? { decision.load }
    }

    static func nextSetPrefill(exercise: ProgramV2Exercise, setIndex: Int, sets: [LoggedSet],
                               last: LastPerformance?, doneLaterThanPlanned: Bool = false,
                               holdLoads: Bool = false) -> Prefill {
        let range = ProgressionRule.repRange(exercise.reps)
        let previous = sets.last { $0.reps > 0 }
        let decision: ProgressionDecision
        if let previous {
            decision = ProgressionRule.adjustedDecision(
                after: WorkingSetSummary(load: previous.weight, reps: previous.reps, rir: previous.rir),
                range: range, doneLaterThanPlanned: doneLaterThanPlanned, holdLoads: holdLoads)
        } else {
            decision = ProgressionRule.suggestedDecision(last: last, reps: exercise.reps,
                startLoadLb: exercise.startLoadLb, holdLoads: holdLoads,
                doneLaterThanPlanned: doneLaterThanPlanned)
        }
        let sameIndex = last?.sets.indices.contains(setIndex) == true ? last?.sets[setIndex].reps : nil
        let referenceReps = previous?.reps ?? sameIndex ?? range?.low ?? 0
        let reps = range.map { min(max(referenceReps, $0.low), $0.high) } ?? referenceReps
        return Prefill(decision: decision, reps: reps,
            rir: RIRTargetParser.defaultRIR(for: RIRTargetParser.target(for: exercise),
                                           setIndex: setIndex, setCount: exercise.sets))
    }

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
