import Foundation
import Observation

/// Entry policy and draft mutations. SwiftUI supplies user intent only.
@Observable
final class WorkoutSetEntry {
    let day: ProgramV2Day
    var lastPerformances: [String: LastPerformance] = [:]
    var editingStep: ExerciseStep? {
        didSet {
            if oldValue != editingStep, let oldValue {
                enteredDestinations[oldValue] = nil
            }
        }
    }
    private var pending: [ExerciseStep: LoggedSet] = [:]
    /// A later ghost appends the next actual set; keep its editor bound to it.
    private var enteredDestinations: [ExerciseStep: Int] = [:]
    private(set) var deletion: SetDeletionUndo?
    private var cursor = SessionStepCursor()
    private(set) var restStep: ExerciseStep?
    private(set) var nextValue: LoggedSet?
    private var nextDecision: ProgressionDecision?
    private var nextBasis: [String: [LoggedSet]] = [:]
    private var nextHistory: [String: LastPerformance] = [:]
    private var nextWasEdited = false

    func startRestAfterLogging(_ exercise: ProgramV2Exercise, at index: Int,
                               in store: WorkoutDraftStore, rest: RestSession) {
        let step = ExerciseStep(exerciseName: exercise.name,
            setIndex: cursor.logicalIndex(exerciseName: exercise.name, storageIndex: index))
        let sets = cursor.projectedSets(store.existingDraft(for: day)?.sets ?? [:], skippedReps: 0)
        if let block = order(in: store).blocks.first(where: { $0.exercises.contains { $0.name == exercise.name } }),
           let seconds = SetEntryLogic.restAfterLogging(exerciseName: exercise.name, setIndex: step.setIndex,
                                                        block: block, sets: sets) {
            rest.start(seconds: seconds)
            rest.rangeLabel = LoggerFormatting.restRange(exercise.restSeconds)
        }
        prepareNext(after: step, in: store)
        rest.stepLabel = restStep.map { "Next: \($0.exerciseName) S\($0.setIndex + 1)" } ?? "Finish → list"
    }

    func prepareNext(after step: ExerciseStep?, in store: WorkoutDraftStore) {
        let sets = store.existingDraft(for: day)?.sets ?? [:]
        nextBasis = sets
        nextHistory = lastPerformances
        nextWasEdited = false
        restStep = cursor.next(in: order(in: store).blocks, sets: sets, after: step)
        guard let restStep, let exercise = day.exercises.first(where: { $0.name == restStep.exerciseName }) else {
            nextValue = nil
            nextDecision = nil
            return
        }
        let target = prefill(for: exercise, at: restStep.setIndex, in: store)
        nextDecision = target.decision
        let index = cursor.storageIndex(for: restStep)
        let existing = sets[exercise.name].flatMap { $0.indices.contains(index) ? $0[index] : nil }
        let step = ExerciseStep(exerciseName: exercise.name, setIndex: index)
        let value = pending[step] ?? existing ?? LoggedSet(weight: target.load ?? 0,
            reps: target.reps, rir: target.rir, rpeText: "")
        var refreshed = SetEntryLogic.refreshedUnfinished(value, target: target)
        if value.editedFields?.contains(.reps) != true { refreshed.reps = target.reps }
        nextValue = refreshed
    }

    func refreshRestEntry(in store: WorkoutDraftStore, rest: RestSession) {
        let sets = store.existingDraft(for: day)?.sets ?? [:]
        guard sets != nextBasis || (!nextWasEdited && nextHistory != lastPerformances) else { return }
        prepareNext(after: restStep, in: store)
        rest.stepLabel = restStep.map { "Next: \($0.exerciseName) S\($0.setIndex + 1)" } ?? "Finish → list"
    }

    func restDetails(in store: WorkoutDraftStore, isHold: Bool) -> RestNextSet? {
        guard let step = restStep, let value = nextValue, let decision = nextDecision,
              let exercise = day.exercises.first(where: { $0.name == step.exerciseName }) else { return nil }
        let rows = store.existingDraft(for: day)?.sets[exercise.name] ?? []
        let previous = rows.last { $0.reps > 0 }
        let last = lastPerformance(for: exercise)
        let reference = previous.map { WorkingSetSummary(load: $0.weight, reps: $0.reps, rir: $0.rir) } ?? last?.firstSet
        return RestNextSet(step: step, exercise: exercise, value: value,
            targetChips: SetEntryLogic.targetChips(for: exercise, at: step.setIndex),
            reference: LoggerFormatting.nextSetReference(sets: rows, last: last, at: step.setIndex),
            referenceLoad: reference?.load ?? exercise.startLoadLb,
            reason: LoggerFormatting.progressionReason(decision, exercise: exercise, reference: reference), isHold: isHold)
    }

    func editNext(_ change: (inout LoggedSet) -> Void) {
        guard var value = nextValue else { return }
        change(&value)
        nextValue = value
        nextWasEdited = true
    }

    func stepNext(load: Bool, direction: Int, isHold: Bool) {
        editNext { $0 = SetEntryLogic.stepped($0, load: load, direction: direction, isHold: isHold) }
    }

    func logNext(in store: WorkoutDraftStore, startedAt: Date, rest: RestSession) {
        guard let step = restStep, let value = nextValue,
              let exercise = day.exercises.first(where: { $0.name == step.exerciseName }),
              let index = log(exercise, at: cursor.storageIndex(for: step), in: store, startedAt: startedAt, value: value) else { return }
        startRestAfterLogging(exercise, at: index, in: store, rest: rest)
    }

    func skipNext(in store: WorkoutDraftStore, rest: RestSession) {
        guard let step = restStep else { return }
        cursor.skip(step)
        rest.stop()
        prepareNext(after: step, in: store)
        rest.stepLabel = restStep.map { "Next: \($0.exerciseName) S\($0.setIndex + 1)" } ?? "Finish → list"
    }

    func row(for exercise: ProgramV2Exercise, at index: Int, in store: WorkoutDraftStore) -> LoggedSet {
        let step = ExerciseStep(exerciseName: exercise.name, setIndex: index)
        let target = prefill(for: exercise, at: index, in: store)
        if let pending = pending[step] { return SetEntryLogic.refreshedUnfinished(pending, target: target) }
        let rows = store.existingDraft(for: day)?.sets[exercise.name] ?? []
        let destination = (editingStep == step ? enteredDestinations[step] : nil) ?? index
        if rows.indices.contains(destination) {
            let value = rows[destination]
            return value.reps > 0 ? value : SetEntryLogic.refreshedUnfinished(value, target: target)
        }
        return LoggedSet(weight: target.load ?? 0, reps: target.reps, rir: target.rir, rpeText: "")
    }

    func edit(_ exercise: ProgramV2Exercise, at index: Int, in store: WorkoutDraftStore,
              startedAt: Date, field: LoggedSet.Field? = nil, _ change: (inout LoggedSet) -> Void) {
        let step = ExerciseStep(exerciseName: exercise.name, setIndex: index)
        // Reps still count as logged immediately, but a live editor must not
        // disappear after the first digit of a multi-digit entry.
        editingStep = step
        let destination = (editingStep == step ? enteredDestinations[step] : nil) ?? index
        if store.existingDraft(for: day)?.sets[exercise.name]?.indices.contains(destination) == true {
            var value = row(for: exercise, at: index, in: store)
            let previous = value
            change(&value)
            value.recordEdits(from: previous, field: field)
            update(exercise, at: destination, in: store, startedAt: startedAt) { $0 = value }
        } else {
            var value = row(for: exercise, at: index, in: store)
            let previous = value
            change(&value)
            value.recordEdits(from: previous, field: field)
            if value.reps > 0, value.editedFields?.contains(.reps) == true, hasLoad(value, for: exercise) {
                let count = store.existingDraft(for: day)?.sets[exercise.name]?.count ?? 0
                store.update(day, startedAt: startedAt) { $0.sets[exercise.name, default: []].append(value) }
                enteredDestinations[step] = count
                pending[step] = nil
                pending[ExerciseStep(exerciseName: exercise.name, setIndex: count)] = nil
            } else {
                pending[step] = value
            }
        }
    }

    /// Missing earlier ghosts are never materialized as zero-rep placeholders.
    /// Tapping a later target records the next actual set in the exercise.
    @discardableResult
    func log(_ exercise: ProgramV2Exercise, at index: Int, in store: WorkoutDraftStore,
             startedAt: Date, value: LoggedSet? = nil) -> Int? {
        let step = ExerciseStep(exerciseName: exercise.name, setIndex: index)
        let value = value ?? row(for: exercise, at: index, in: store)
        guard value.reps > 0, hasLoad(value, for: exercise) else { editingStep = step; return nil }
        let count = store.existingDraft(for: day)?.sets[exercise.name]?.count ?? 0
        let destination = (editingStep == step ? enteredDestinations[step] : nil) ?? min(index, count)
        guard destination >= 0 else { return nil }
        store.update(day, startedAt: startedAt) { draft in
            if destination < count { draft.sets[exercise.name]![destination] = value }
            else { draft.sets[exercise.name, default: []].append(value) }
        }
        pending[step] = nil
        if destination == count {
            pending[ExerciseStep(exerciseName: exercise.name, setIndex: destination)] = nil
        }
        enteredDestinations[step] = nil
        editingStep = nil
        return destination
    }

    private func hasLoad(_ value: LoggedSet, for exercise: ProgramV2Exercise) -> Bool {
        value.weight > 0 || exercise.startLoadLb == 0
    }

    func repeatSource(for exercise: ProgramV2Exercise, in store: WorkoutDraftStore) -> Int? {
        store.existingDraft(for: day)?.sets[exercise.name]?.lastIndex { $0.reps > 0 }
    }

    @discardableResult
    func repeatLast(_ exercise: ProgramV2Exercise, in store: WorkoutDraftStore, startedAt: Date) -> Int? {
        let rows = store.existingDraft(for: day)?.sets[exercise.name] ?? []
        guard let source = repeatSource(for: exercise, in: store) else { return nil }
        let destination = rows.firstIndex { $0.reps == 0 } ?? rows.count
        return log(exercise, at: destination, in: store, startedAt: startedAt, value: rows[source])
    }

    func remove(_ exercise: ProgramV2Exercise, at index: Int, in store: WorkoutDraftStore,
                startedAt: Date, now: Date = Date()) {
        guard let rows = store.existingDraft(for: day)?.sets[exercise.name], rows.indices.contains(index) else { return }
        deletion = SetDeletionUndo(exerciseName: exercise.name, index: index,
                                  set: rows[index], expiresAt: now.addingTimeInterval(5))
        store.update(day, startedAt: startedAt) { $0.sets[exercise.name]?.remove(at: index) }
        pending = [:]
        enteredDestinations = [:]
        editingStep = nil
    }

    func undo(in store: WorkoutDraftStore, startedAt: Date, now: Date = Date()) {
        guard let deletion, deletion.canRestore(at: now) else { self.deletion = nil; return }
        store.update(day, startedAt: startedAt) { _ = deletion.restore(in: &$0.sets, at: now) }
        self.deletion = nil
        pending = [:]
        enteredDestinations = [:]
        editingStep = nil
    }

    init(day: ProgramV2Day) { self.day = day }

    func canMove(_ block: ExerciseBlock, direction: SessionOrder.Direction, in store: WorkoutDraftStore) -> Bool {
        let blocks = order(in: store).blocks
        guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return false }
        let destination: Int
        switch direction {
        case .up: destination = index - 1
        case .down: destination = index + 1
        }
        guard blocks.indices.contains(destination) else { return false }
        let sets = store.existingDraft(for: day)?.sets ?? [:]
        return [blocks[index], blocks[destination]].allSatisfy { candidate in
            candidate.exercises.allSatisfy { exercise in
                !(sets[exercise.name] ?? []).contains { $0.reps > 0 }
            }
        }
    }

    func move(_ block: ExerciseBlock, direction: SessionOrder.Direction,
              in store: WorkoutDraftStore, startedAt: Date, rest: RestSession) {
        guard canMove(block, direction: direction, in: store) else { return }
        var sessionOrder = order(in: store)
        guard let index = sessionOrder.blocks.firstIndex(where: { $0.id == block.id }) else { return }
        sessionOrder.move(blockAt: index, direction: direction)
        store.update(day, startedAt: startedAt) { $0.exerciseOrder = sessionOrder.exerciseOrder }
        prepareNext(after: nil, in: store)
        rest.stepLabel = restStep.map { "Next: \($0.exerciseName) S\($0.setIndex + 1)" } ?? "Finish → list"
    }

    func preExhaustionNote(for exercise: ProgramV2Exercise, in store: WorkoutDraftStore) -> String? {
        order(in: store).isDoneLaterThanPlanned(exercise.name)
            ? "Done later than planned · a miss holds the load" : nil
    }

    func lastPerformance(for exercise: ProgramV2Exercise) -> LastPerformance? {
        lastPerformances[LastPerformanceBuilder.key(for: exercise.name)]
    }

    func order(in store: WorkoutDraftStore) -> SessionOrder {
        SessionOrder(plannedBlocks: SupersetGrouping.blocks(for: day.exercises),
                     exerciseOrder: store.existingDraft(for: day)?.exerciseOrder)
    }

    func suggestedLoad(for exercise: ProgramV2Exercise, in store: WorkoutDraftStore) -> Double? {
        ProgressionRule.suggestedLoad(last: lastPerformance(for: exercise), reps: exercise.reps,
            startLoadLb: exercise.startLoadLb, holdLoads: day.holdLoads,
            doneLaterThanPlanned: order(in: store).isDoneLaterThanPlanned(exercise.name))
    }

    func prefill(for exercise: ProgramV2Exercise, at index: Int, in store: WorkoutDraftStore) -> SetEntryLogic.Prefill {
        SetEntryLogic.nextSetPrefill(exercise: exercise, setIndex: index,
            sets: store.existingDraft(for: day)?.sets[exercise.name] ?? [],
            last: lastPerformance(for: exercise),
            doneLaterThanPlanned: order(in: store).isDoneLaterThanPlanned(exercise.name), holdLoads: day.holdLoads)
    }

    func update(_ exercise: ProgramV2Exercise, at index: Int, in store: WorkoutDraftStore,
                startedAt: Date, _ change: (inout LoggedSet) -> Void) {
        store.update(day, startedAt: startedAt) { draft in
            guard draft.sets[exercise.name]?.indices.contains(index) == true else { return }
            change(&draft.sets[exercise.name]![index])
        }
    }

    func add(_ exercise: ProgramV2Exercise, in store: WorkoutDraftStore, startedAt: Date) {
        let index = store.existingDraft(for: day)?.sets[exercise.name]?.count ?? 0
        let target = prefill(for: exercise, at: index, in: store)
        let row = LoggedSet(weight: target.load ?? 0, reps: 0, rir: target.rir, rpeText: "")
        store.update(day, startedAt: startedAt) { $0.sets[exercise.name, default: []].append(row) }
    }

    func refreshPrefilledLoads(in store: WorkoutDraftStore, startedAt: Date) {
        guard !Task.isCancelled, let draft = store.existingDraft(for: day) else { return }
        var refreshed: [String: [LoggedSet]] = [:]
        for exercise in day.exercises where refreshed[exercise.name] == nil {
            guard var rows = draft.sets[exercise.name] else { continue }
            for index in rows.indices where rows[index].reps == 0 {
                rows[index] = row(for: exercise, at: index, in: store)
            }
            if rows != draft.sets[exercise.name] { refreshed[exercise.name] = rows }
        }
        guard !refreshed.isEmpty else { return }
        store.update(day, startedAt: startedAt) { draft in
            for (name, sets) in refreshed { draft.sets[name] = sets }
        }
    }
}
