import Testing
@testable import calorietracker

extension WorkoutLoggerLogicTests {
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
