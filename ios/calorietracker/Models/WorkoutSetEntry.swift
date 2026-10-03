import Foundation
import Observation

/// Entry policy and draft mutations. SwiftUI supplies user intent only.
@Observable
final class WorkoutSetEntry {
    let day: ProgramV2Day
    var lastPerformances: [String: LastPerformance] = [:]

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
