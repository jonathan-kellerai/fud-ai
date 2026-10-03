import Foundation
import Observation

/// Entry policy and draft mutations. SwiftUI supplies user intent only.
@Observable
final class WorkoutSetEntry {
    let day: ProgramV2Day
    var lastPerformances: [String: LastPerformance] = [:]
    var editingStep: ExerciseStep?
    var pending: [ExerciseStep: LoggedSet] = [:]
    var deletion: SetDeletionUndo?

    func row(for exercise: ProgramV2Exercise, at index: Int, in store: WorkoutDraftStore) -> LoggedSet {
        let step = ExerciseStep(exerciseName: exercise.name, setIndex: index)
        if let pending = pending[step] { return pending }
        let rows = store.existingDraft(for: day)?.sets[exercise.name] ?? []
        if rows.indices.contains(index) { return rows[index] }
        let target = prefill(for: exercise, at: index, in: store)
        return LoggedSet(weight: target.load ?? 0, reps: target.reps, rir: target.rir, rpeText: "")
    }

    func edit(_ exercise: ProgramV2Exercise, at index: Int, in store: WorkoutDraftStore,
              startedAt: Date, _ change: (inout LoggedSet) -> Void) {
        let step = ExerciseStep(exerciseName: exercise.name, setIndex: index)
        if store.existingDraft(for: day)?.sets[exercise.name]?.indices.contains(index) == true {
            update(exercise, at: index, in: store, startedAt: startedAt, change)
        } else {
            var value = row(for: exercise, at: index, in: store)
            change(&value)
            pending[step] = value
        }
    }

    /// Missing earlier ghosts are never materialized as zero-rep placeholders.
    /// Tapping a later target records the next actual set in the exercise.
    @discardableResult
    func log(_ exercise: ProgramV2Exercise, at index: Int, in store: WorkoutDraftStore,
             startedAt: Date, value: LoggedSet? = nil) -> Int? {
        let step = ExerciseStep(exerciseName: exercise.name, setIndex: index)
        let value = value ?? row(for: exercise, at: index, in: store)
        let hasLoad = value.weight > 0 || exercise.startLoadLb == 0
        guard value.reps > 0, hasLoad else { editingStep = step; return nil }
        let count = store.existingDraft(for: day)?.sets[exercise.name]?.count ?? 0
        let destination = min(index, count)
        guard destination >= 0 else { return nil }
        store.update(day, startedAt: startedAt) { draft in
            if destination < count { draft.sets[exercise.name]![destination] = value }
            else { draft.sets[exercise.name, default: []].append(value) }
        }
        pending[step] = nil
        editingStep = nil
        return destination
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
        editingStep = nil
    }

    func undo(in store: WorkoutDraftStore, startedAt: Date, now: Date = Date()) {
        guard let deletion, deletion.canRestore(at: now) else { self.deletion = nil; return }
        store.update(day, startedAt: startedAt) { _ = deletion.restore(in: &$0.sets, at: now) }
        self.deletion = nil
        pending = [:]
        editingStep = nil
    }

    init(day: ProgramV2Day) { self.day = day }

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
        var suggestions: [String: Double] = [:]
        for exercise in day.exercises where suggestions[exercise.name] == nil {
            if let suggestion = suggestedLoad(for: exercise, in: store) { suggestions[exercise.name] = suggestion }
        }
        let refreshed = PrefillRefresh.refreshedSets(exercises: day.exercises, sets: draft.sets, suggestions: suggestions)
        guard !refreshed.isEmpty else { return }
        store.update(day, startedAt: startedAt) { draft in
            for (name, sets) in refreshed { draft.sets[name] = sets }
        }
    }
}
