import Testing
@testable import calorietracker

extension WorkoutLoggerLogicTests {
    @Test func nextSetMatchesP1HistoryAcceptanceAndWithinSessionRule() {
        let exercise = ProgramV2Exercise(key: "press", name: "Press", sets: 3, reps: "10-15",
            restSeconds: 60...60, rirTarget: "2-3 RIR", startLoadLb: 100, notes: "")
        let cases: [(Int, Int?, Double, ProgressionReason)] = [
            (15, 4, 150, .increase), (9, 2, 140, .decrease),
            (12, 0, 140, .decrease), (12, 2, 145, .hold),
            (9, nil, 140, .decrease), (12, nil, 145, .hold)
        ]
        for (reps, rir, load, reason) in cases {
            let last = LastPerformance(sessionDate: "2026-10-02", sets: [WorkingSetSummary(load: 145, reps: reps, rir: rir)])
            let first = SetEntryLogic.nextSetPrefill(exercise: exercise, setIndex: 0, sets: [], last: last)
            #expect(first.decision == ProgressionDecision(load: load, reason: reason))
            let second = SetEntryLogic.nextSetPrefill(exercise: exercise, setIndex: 1,
                sets: [LoggedSet(weight: 145, reps: reps, rir: rir, rpeText: "")], last: nil)
            #expect(second.decision == first.decision)
            #expect(second.reps == min(max(reps, 10), 15))
            #expect(second.rir == 2)
            let reduction = SetEntryLogic.nextSetPrefill(exercise: exercise, setIndex: 1,
                sets: [LoggedSet(weight: 145, reps: reps, rir: rir, rpeText: "")], last: last, holdLoads: true)
            #expect(reduction.decision == ProgressionDecision(load: 145, reason: .holdReductionWeek))
        }
    }

    @Test func nextSetUsesLastLoggedSetAndSameIndexHistoryReps() {
        let exercise = ProgramV2Exercise(key: "press", name: "Press", sets: 3, reps: "10-15",
            restSeconds: 60...60, rirTarget: "2-3 RIR; last set 1-2", startLoadLb: 100, notes: "")
        let last = LastPerformance(sessionDate: "2026-10-02", sets: [
            WorkingSetSummary(load: 145, reps: 12, rir: 2), WorkingSetSummary(load: 145, reps: 14, rir: 1)
        ])
        let rows = [LoggedSet(weight: 150, reps: 15, rir: 4, rpeText: ""),
                    LoggedSet(weight: 999, reps: 0, rir: 0, rpeText: "")]
        let next = SetEntryLogic.nextSetPrefill(exercise: exercise, setIndex: 2, sets: rows, last: last)
        #expect(next.load == 155)
        #expect(next.reps == 15)
        #expect(next.rir == 1)
        let fromHistory = SetEntryLogic.nextSetPrefill(exercise: exercise, setIndex: 1, sets: [rows[1]], last: last)
        #expect(fromHistory.load == 145)
        #expect(fromHistory.reps == 14)
        let missingIndex = SetEntryLogic.nextSetPrefill(exercise: exercise, setIndex: 2, sets: [], last: last)
        #expect(missingIndex.reps == 10)
        let belowRangeHistory = LastPerformance(sessionDate: "2026-10-02",
            sets: [WorkingSetSummary(load: 145, reps: 9, rir: 0)])
        let reorderedFirst = SetEntryLogic.nextSetPrefill(exercise: exercise, setIndex: 0,
            sets: [], last: belowRangeHistory, doneLaterThanPlanned: true)
        #expect(reorderedFirst.decision == ProgressionDecision(load: 145, reason: .holdPreFatigued))
    }

    @Test func nextSetKeepsSelectLoadBlankBodyweightZeroAndHoldSeconds() {
        let select = ProgramV2Exercise(key: "select", name: "Select", sets: 2, reps: "10-15",
            restSeconds: 60...60, rirTarget: "", startLoadLb: nil, notes: "")
        let fresh = SetEntryLogic.nextSetPrefill(exercise: select, setIndex: 0, sets: [], last: nil)
        #expect(fresh.load == nil)
        #expect(fresh.decision.reason == .noHistory)
        #expect(fresh.reps == 10)
        #expect(fresh.rir == nil)
        let hold = ProgramV2Exercise(key: "hold", name: "Hold", sets: 2, reps: "10-30 sec",
            restSeconds: 60...60, rirTarget: "2", startLoadLb: 0, notes: "")
        let next = SetEntryLogic.nextSetPrefill(exercise: hold, setIndex: 1,
            sets: [LoggedSet(weight: 0, reps: 35, rir: 5, rpeText: "")], last: nil)
        #expect(next.load == 0)
        #expect(next.reps == 30)
        #expect(next.rir == 2)
        #expect(SetEntryLogic.nextSetPrefill(exercise: hold, setIndex: 0, sets: [], last: nil).load == 0)
    }

    @Test func setEntryPinsOriginalDecisions() {
        let exercise = ProgramV2Templates.day1LowerA.exercises[0]
        let empty = LoggedSet(weight: 150, reps: 0, rir: 0, rpeText: "")
        let logged = LoggedSet(weight: 155, reps: 12, rir: 2, rpeText: "")
        #expect(SetEntryLogic.prefillLoad(sets: [], suggestion: nil) == 0)
        #expect(SetEntryLogic.prefillLoad(sets: [], suggestion: 145) == 145)
        #expect(SetEntryLogic.prefillLoad(sets: [logged, empty], suggestion: 145) == 150)
        #expect(SetEntryLogic.isCurrent(setIndex: 1, sets: [logged, empty]))
        #expect(!SetEntryLogic.isCurrent(setIndex: 0, sets: [logged, empty]))
        let previous = LastPerformance(sessionDate: "2026-09-28", sets: [WorkingSetSummary(load: 150, reps: 12, rir: 2)])
        #expect(SetEntryLogic.isPersonalRecord(set: logged, previous: previous))
        #expect(!SetEntryLogic.isPersonalRecord(set: empty, previous: previous))
        #expect(!SetEntryLogic.isPersonalRecord(set: logged, previous: nil))
        #expect(SetEntryLogic.plannedRowCount(exercise: exercise, sets: []) == exercise.sets)
        #expect(SetEntryLogic.plannedRowCount(exercise: exercise, sets: Array(repeating: logged, count: 8)) == 8)
        let block = ExerciseBlock(exercises: [exercise])
        #expect(SetEntryLogic.restAfterLogging(exerciseName: exercise.name, setIndex: 0, block: block, sets: [exercise.name: [empty]]) == nil)
        #expect(SetEntryLogic.restAfterLogging(exerciseName: exercise.name, setIndex: 0, block: block, sets: [exercise.name: [logged]]) == exercise.restSeconds.lowerBound)
        #expect(SetEntryLogic.restAfterLogging(exerciseName: exercise.name, setIndex: 9, block: block, sets: [:]) == nil)
    }
}
