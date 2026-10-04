import Foundation
import Testing
@testable import calorietracker

extension WorkoutLoggerLogicTests {
    @Test func ghostKindsFollowPlannedCountsWithoutWritingRows() {
        var exercise = ProgramV2Templates.day1LowerA.exercises[0]
        let row = LoggedSet(weight: 150, reps: 12, rir: nil, rpeText: "")
        #expect(SetEntryLogic.rowKind(at: 0, sets: [], editing: false) == .ghost)
        #expect(SetEntryLogic.rowKind(at: 0, sets: [row], editing: false) == .logged)
        #expect(SetEntryLogic.rowKind(at: 0, sets: [row], editing: true) == .current)
        var empty = row; empty.reps = 0
        #expect(SetEntryLogic.rowKind(at: 0, sets: [empty], editing: false) == .current)
        exercise.sets = 4
        #expect(SetEntryLogic.plannedRowCount(exercise: exercise, sets: [row]) == 4)
        exercise.sets = 2
        #expect(SetEntryLogic.plannedRowCount(exercise: exercise, sets: [row]) == 2)
        #expect(SetEntryLogic.plannedRowCount(exercise: exercise, sets: [row, row, row]) == 3)
    }

    @Test func rowStepsClampAndHalfPlateLoadsUseTwoPointFive() {
        let row = LoggedSet(weight: 87.5, reps: 1, rir: nil, rpeText: "")
        #expect(SetEntryLogic.loadStep(150) == 5)
        #expect(SetEntryLogic.stepped(row, load: true, direction: 1, isHold: false).weight == 90)
        #expect(SetEntryLogic.stepped(row, load: false, direction: -1, isHold: true).reps == 0)
        var zero = row; zero.weight = 0
        #expect(SetEntryLogic.stepped(zero, load: true, direction: -1, isHold: false).weight == 0)
        var exercise = ProgramV2Templates.day1LowerA.exercises[0]
        exercise.rirTarget = "2-3 RIR"
        #expect(SetEntryLogic.targetChips(for: exercise, at: 0) == [2, 3])
        exercise.rirTarget = "3-5 RIR"
        #expect(SetEntryLogic.targetChips(for: exercise, at: 0) == [3, 4])
    }

    @Test func deletionRestoresExactIndexAndExpires() {
        let now = Date(timeIntervalSince1970: 100)
        let first = LoggedSet(weight: 150, reps: 13, rir: nil, rpeText: "7.5")
        let last = LoggedSet(weight: 155, reps: 12, rir: 2, rpeText: "")
        let undo = SetDeletionUndo(exerciseName: "Press", index: 0, set: first, expiresAt: now.addingTimeInterval(5))
        var rows = ["Press": [last]]
        #expect(undo.restore(in: &rows, at: now.addingTimeInterval(4)))
        #expect(rows["Press"] == [first, last])
        #expect(!undo.restore(in: &rows, at: now.addingTimeInterval(5)))
        let invalid = SetDeletionUndo(exerciseName: "Press", index: 9, set: first, expiresAt: now.addingTimeInterval(5))
        #expect(!invalid.restore(in: &rows, at: now))
    }
}

extension WorkoutDraftStoreTests {
    @Test func typedGhostRepsReloadAndSaveWithoutCheckmark() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let day = ProgramV2Templates.day1LowerA
        let exercise = day.exercises[0]
        let now = Date(timeIntervalSince1970: 100)
        let store = WorkoutDraftStore(directory: directory)
        let entry = WorkoutSetEntry(day: day)
        _ = entry.row(for: exercise, at: 0, in: store)
        entry.edit(exercise, at: 2, in: store, startedAt: now, field: .load) { $0.weight = 155 }
        entry.edit(exercise, at: 2, in: store, startedAt: now, field: .rir) { $0.rir = nil }
        #expect(store.draft == nil)
        entry.edit(exercise, at: 2, in: store, startedAt: now, field: .reps) { $0.reps = 1 }
        #expect(WorkoutDraftStore(directory: directory).draft?.sets[exercise.name]?.map(\.reps) == [1])
        #expect(entry.editingStep == ExerciseStep(exerciseName: exercise.name, setIndex: 2))
        entry.edit(exercise, at: 2, in: store, startedAt: now, field: .reps) { $0.reps = 13 }
        let reopened = WorkoutDraftStore(directory: directory)
        #expect(reopened.draft?.loggedSetCount == 1)
        try await confirmation("save includes only explicitly entered reps") { posted in
            try await reopened.save { payload in
                posted()
                #expect(payload.sets.count == 1)
                #expect(payload.sets.first?.reps == 13)
                #expect(payload.sets.first?.load == 155)
                #expect(payload.sets.first?.rir == nil)
            }
        }
        #expect(reopened.draft == nil)
    }

    @Test func enteringThePrefilledRepValueStillPersistsButZeroDoesNot() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let day = ProgramV2Templates.day1LowerA
        let exercise = day.exercises[0]
        let store = WorkoutDraftStore(directory: directory)
        let entry = WorkoutSetEntry(day: day)
        entry.edit(exercise, at: 0, in: store, startedAt: Date(), field: .reps) { $0.reps = 0 }
        #expect(store.draft == nil)
        entry.edit(exercise, at: 0, in: store, startedAt: Date(), field: .reps) { $0.reps = 10 }
        #expect(store.draft?.sets[exercise.name]?.map(\.reps) == [10])
        #expect(entry.editingStep?.setIndex == 0)
    }

    @Test func ghostEditsLogRepeatAndUndoPersistOnlyEnteredSets() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let day = ProgramV2Templates.day1LowerA
        let exercise = day.exercises[0]
        let store = WorkoutDraftStore(directory: dir)
        let entry = WorkoutSetEntry(day: day)
        let now = Date(timeIntervalSince1970: 100)
        entry.edit(exercise, at: 0, in: store, startedAt: now) { $0.reps = 13 }
        #expect(store.draft?.sets[exercise.name]?.first?.reps == 13)
        #expect(entry.log(exercise, at: 0, in: store, startedAt: now) == 0)
        let original = try #require(store.draft?.sets[exercise.name]?.first)
        #expect(original.reps == 13)
        #expect(entry.repeatLast(exercise, in: store, startedAt: now) == 1)
        #expect(store.draft?.sets[exercise.name] == [original, original])
        entry.remove(exercise, at: 0, in: store, startedAt: now, now: now)
        entry.undo(in: store, startedAt: now, now: now.addingTimeInterval(4))
        #expect(WorkoutDraftStore(directory: dir).draft?.sets[exercise.name] == [original, original])
        // A later ghost never manufactures preceding zero-rep draft rows.
        #expect(entry.log(exercise, at: 9, in: store, startedAt: now) == 2)
        #expect(store.draft?.sets[exercise.name]?.allSatisfy { $0.reps > 0 } == true)
    }

    @Test func selectLoadGhostCannotLogManufacturedZero() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        var day = ProgramV2Templates.day1LowerA
        day.exercises[0] = ProgramV2Exercise(key: "select", name: "Select", sets: 3, reps: "10-15",
            restSeconds: 60...60, rirTarget: "2", startLoadLb: nil, notes: "")
        let store = WorkoutDraftStore(directory: dir)
        let entry = WorkoutSetEntry(day: day)
        #expect(entry.log(day.exercises[0], at: 0, in: store, startedAt: Date()) == nil)
        #expect(store.draft == nil)
        #expect(entry.editingStep?.setIndex == 0)
    }

    @Test func typingRepsKeepsLegacyRowEditorUntilCheckmark() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let day = ProgramV2Templates.day1LowerA
        let exercise = day.exercises[0]
        let store = WorkoutDraftStore(directory: dir)
        let entry = WorkoutSetEntry(day: day)
        entry.add(exercise, in: store, startedAt: Date())
        entry.edit(exercise, at: 0, in: store, startedAt: Date()) { $0.reps = 1 }
        #expect(entry.editingStep == ExerciseStep(exerciseName: exercise.name, setIndex: 0))
        #expect(store.draft?.loggedSetCount == 1)
        entry.edit(exercise, at: 0, in: store, startedAt: Date()) { $0.reps = 13 }
        #expect(entry.log(exercise, at: 0, in: store, startedAt: Date()) == 0)
        #expect(store.draft?.sets[exercise.name]?.first?.reps == 13)
        #expect(entry.editingStep == nil)
    }
}
