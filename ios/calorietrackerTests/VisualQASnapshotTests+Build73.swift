import SwiftUI
import XCTest
@testable import calorietracker

/// Shots 140-142: build 73 start flow. Today shows only Resume (with Discard &
/// start over) for an unsaved draft of the planned day, and the rest screen
/// names the exercise and set and says whether logging adds or edits a set.
extension VisualQASnapshotTests {
    func test140HomeResumeOnlyForPlannedDraft() async throws {
        let body = TrainingProgramRecord.bundledV2().body ?? .bundledV2()
        let now = Date()
        let resolved = TrainingProgramSchedule.resolve(body, on: now,
            context: TrainProgressStore.shared.context(draft: nil, days: body.days), calendar: .current)
        let day = TrainingProgramSchedule.programDay(in: body, matching: resolved)
            .map { body.programV2Day(for: $0, on: now) } ?? ProgramV2Templates.day2UpperPush
        let drafts = WorkoutDraftStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("visual-qa-b73-\(UUID().uuidString)", isDirectory: true))
        drafts.update(day) { draft in
            if let first = day.exercises.first {
                draft.sets[first.name] = [LoggedSet(weight: first.startLoadLb ?? 100, reps: 10, rir: 3, rpeText: "")]
            }
        }
        VisualQAGraveyard.keep(drafts)
        try await capture("140-home-resume-only", heightMultiplier: 1.6) { _ in
            VisualQATabShell(selected: .home) {
                HomeView(quickActionRequest: nil, onQuickActionHandled: { _ in })
            }
            .environment(drafts)
        }
    }

    private func restSheet(editing: Bool) -> some View {
        let exercise = ProgramV2Exercise(key: "chest-press", name: "Chest Press", sets: 2, reps: "8-12",
            restSeconds: 90...120, rirTarget: "3-4 RIR", startLoadLb: 100, notes: "")
        let next = RestNextSet(step: ExerciseStep(exerciseName: exercise.name, setIndex: 1), exercise: exercise,
            value: LoggedSet(weight: 100, reps: editing ? 11 : 10, rir: 3, rpeText: ""), targetChips: [3, 4],
            reference: "Today S1 100 × 12 @ RIR 4", referenceLoad: 100,
            reason: "Hold: in range", isHold: false, isEditing: editing)
        let rest = RestSession(now: { VisualQAFixtures.referenceNow })
        rest.start(seconds: 90)
        rest.rangeLabel = "90–120 s"
        VisualQAGraveyard.keep(rest)
        return NavigationStack { RestTimerSheet(session: rest, next: next) }
    }

    func test141RestScreenAddingSet() async throws {
        try await capture("141-rest-adding-set", heightMultiplier: 2.4) { _ in
            self.restSheet(editing: false)
        }
    }

    func test142RestScreenEditingSet() async throws {
        try await capture("142-rest-editing-set", heightMultiplier: 2.4) { _ in
            self.restSheet(editing: true)
        }
    }
}
