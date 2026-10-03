import Foundation

enum SetEntryLogic {
    enum RowKind { case ghost, current, logged }

    static func rowKind(at index: Int, sets: [LoggedSet], editing: Bool) -> RowKind {
        if editing { return .current }
        guard sets.indices.contains(index) else { return .ghost }
        return sets[index].reps > 0 ? .logged : .current
    }

    static func loadStep(_ load: Double) -> Double {
        abs(load.truncatingRemainder(dividingBy: 1)) == 0.5 ? 2.5 : 5
    }

    static func stepped(_ row: LoggedSet, load: Bool, direction: Int, isHold: Bool) -> LoggedSet {
        var result = row
        if load { result.weight = max(0, row.weight + Double(direction) * loadStep(row.weight)) }
        else { result.reps = max(0, row.reps + direction * (isHold ? 5 : 1)) }
        return result
    }

    static func targetChips(for exercise: ProgramV2Exercise, at index: Int) -> Set<Int> {
        guard let range = RIRTargetParser.targetRange(for: RIRTargetParser.target(for: exercise),
            setIndex: index, setCount: exercise.sets) else { return [] }
        return Set((0...4).filter { range.contains($0) || ($0 == 4 && range.upperBound >= 4) })
    }

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

/// One outstanding deletion, with an injected time for deterministic expiry.
struct SetDeletionUndo {
    let exerciseName: String
    let index: Int
    let set: LoggedSet
    let expiresAt: Date

    func canRestore(at now: Date) -> Bool { now < expiresAt }

    func restore(in sets: inout [String: [LoggedSet]], at now: Date) -> Bool {
        guard canRestore(at: now), index >= 0, index <= (sets[exerciseName]?.count ?? 0) else { return false }
        sets[exerciseName, default: []].insert(set, at: index)
        return true
    }
}
