import Foundation
import Testing
@testable import calorietracker

private func sequenceExercise(_ name: String, sets: Int = 2, group: String? = nil) -> ProgramV2Exercise {
    ProgramV2Exercise(key: name, name: name, sets: sets, reps: "10-15", restSeconds: 90...120,
        rirTarget: "2-3 RIR", startLoadLb: 145, notes: "", supersetGroup: group)
}

extension WorkoutLoggerLogicTests {
    @Test func nextSetSequenceCoversStraightPairsTriplesAndFinish() {
        for members in 1...3 {
            let exercises = (0..<members).map { sequenceExercise("\($0)", group: members > 1 ? "g" : nil) }
            let blocks = SupersetGrouping.blocks(for: exercises + [sequenceExercise("End", sets: 1)])
            let cursor = SessionStepCursor()
            var rows: [String: [LoggedSet]] = [:]
            var actual: [ExerciseStep] = []
            var previous: ExerciseStep?
            while let next = cursor.next(in: blocks, sets: rows, after: previous) {
                actual.append(next)
                rows[next.exerciseName, default: []].append(LoggedSet(weight: 145, reps: 12, rir: 2, rpeText: ""))
                previous = next
            }
            let expected = (0..<2).flatMap { round in exercises.map { ExerciseStep(exerciseName: $0.name, setIndex: round) } }
                + [ExerciseStep(exerciseName: "End", setIndex: 0)]
            #expect(actual == expected)
            #expect(cursor.next(in: blocks, sets: rows, after: previous) == nil)
        }
    }

    @Test func skipsAdvanceWithoutDraftPlaceholdersOrRepeatedSteps() throws {
        let blocks = SupersetGrouping.blocks(for: [sequenceExercise("A", group: "g"), sequenceExercise("B", group: "g")])
        var cursor = SessionStepCursor()
        let a1 = ExerciseStep(exerciseName: "A", setIndex: 0)
        cursor.skip(a1)
        #expect(cursor.next(in: blocks, sets: [:], after: a1) == ExerciseStep(exerciseName: "B", setIndex: 0))
        var rows = ["B": [LoggedSet(weight: 145, reps: 12, rir: 2, rpeText: "")]]
        let a2 = try #require(cursor.next(in: blocks, sets: rows))
        #expect(a2 == ExerciseStep(exerciseName: "A", setIndex: 1))
        #expect(cursor.storageIndex(for: a2) == 0)
        rows["A"] = [LoggedSet(weight: 145, reps: 12, rir: 2, rpeText: "")]
        #expect(cursor.logicalIndex(exerciseName: "A", storageIndex: 0) == 1)
        #expect(cursor.next(in: blocks, sets: rows) == ExerciseStep(exerciseName: "B", setIndex: 1))
        cursor.skip(ExerciseStep(exerciseName: "B", setIndex: 1))
        #expect(cursor.next(in: blocks, sets: rows) == nil)
        #expect(rows["A"]?.count == 1)
        #expect(rows["B"]?.count == 1)
    }

    @Test func restReferenceFallsBackAndReasonsExplainProgression() {
        let exercise = sequenceExercise("A")
        let last = LastPerformance(sessionDate: "2026-10-01", sets: [WorkingSetSummary(load: 145, reps: 15, rir: 4)])
        let rows = [LoggedSet(weight: 150, reps: 13, rir: 2, rpeText: "")]
        #expect(LoggerFormatting.nextSetReference(sets: rows, last: last, at: 2) == "Today S1 150 × 13 @ RIR 2 · Last time 145 × 15 @ 4")
        #expect(LoggerFormatting.progressionReason(ProgressionDecision(load: 150, reason: .increase), exercise: exercise, reference: last.firstSet) == "+5: hit 15 @ RIR 4")
        #expect(LoggerFormatting.progressionReason(ProgressionDecision(load: 140, reason: .decrease), exercise: exercise,
            reference: WorkingSetSummary(load: 145, reps: 9, rir: nil)) == "−5: below 10 reps")
        #expect(LoggerFormatting.progressionReason(ProgressionDecision(load: 145, reason: .holdPreFatigued), exercise: exercise, reference: nil) == "Hold: done later than planned — not counted as a miss")
        #expect(LoggerFormatting.restRange(90...120) == "90–120 s")
    }
}

extension WorkoutDraftStoreTests {
    @Test func restEntryLogsProgressesAndKeepsSupersetRestPolicy() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = sequenceExercise("A", group: "g")
        let b = sequenceExercise("B", group: "g")
        let day = ProgramV2Day(id: "Day", title: "Day", conditioning: "", conditioningMinimum: "", exercises: [a, b])
        let store = WorkoutDraftStore(directory: dir)
        let entry = WorkoutSetEntry(day: day)
        let rest = RestSession()
        entry.prepareNext(after: nil, in: store)
        entry.editNext { $0.reps = 15; $0.rir = 4 }
        #expect(store.draft == nil)
        entry.logNext(in: store, startedAt: Date(), rest: rest)
        #expect(entry.restStep == ExerciseStep(exerciseName: "B", setIndex: 0))
        #expect(!rest.isActive)
        entry.logNext(in: store, startedAt: Date(), rest: rest)
        #expect(rest.duration == 90)
        #expect(entry.restStep == ExerciseStep(exerciseName: "A", setIndex: 1))
        #expect(entry.nextValue?.weight == 150)
        #expect(entry.nextValue?.rir == 2)
        entry.logNext(in: store, startedAt: Date(), rest: rest)
        entry.logNext(in: store, startedAt: Date(), rest: rest)
        #expect(entry.restStep == nil)
        #expect(rest.stepLabel == "Finish → list")
        #expect(WorkoutDraftStore(directory: dir).draft?.loggedSetCount == 4)
    }

    @Test func skippingFirstStepLogsSecondWithoutWritingSkippedSet() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = sequenceExercise("A")
        let day = ProgramV2Day(id: "Day", title: "Day", conditioning: "", conditioningMinimum: "", exercises: [a])
        let store = WorkoutDraftStore(directory: dir)
        let entry = WorkoutSetEntry(day: day)
        let rest = RestSession()
        entry.prepareNext(after: nil, in: store)
        rest.start(seconds: 90)
        entry.skipNext(in: store, rest: rest)
        #expect(!rest.isActive)
        #expect(store.draft == nil)
        #expect(entry.restStep?.setIndex == 1)
        entry.logNext(in: store, startedAt: Date(), rest: rest)
        #expect(store.draft?.sets["A"]?.count == 1)
        #expect(entry.restStep == nil)
        #expect(rest.isActive)
    }

    @Test func skippedSupersetMemberDoesNotSatisfyRestPolicy() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let day = ProgramV2Day(id: "Day", title: "Day", conditioning: "", conditioningMinimum: "",
            exercises: [sequenceExercise("A", group: "g"), sequenceExercise("B", group: "g")])
        let store = WorkoutDraftStore(directory: dir)
        let entry = WorkoutSetEntry(day: day)
        let rest = RestSession()
        entry.prepareNext(after: nil, in: store)
        entry.skipNext(in: store, rest: rest)
        entry.logNext(in: store, startedAt: Date(), rest: rest)
        #expect(entry.restStep == ExerciseStep(exerciseName: "A", setIndex: 1))
        #expect(!rest.isActive)
        #expect(store.draft?.sets["A"] == nil)
    }
}
