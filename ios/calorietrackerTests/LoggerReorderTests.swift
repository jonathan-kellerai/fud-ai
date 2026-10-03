import Foundation
import Testing
@testable import calorietracker

extension WorkoutDraftStoreTests {
    @Test func loggerMovesAtomicBlocksAndRestFollowsSavedOrder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let day = ProgramV2Templates.day4UpperPhysique
        let store = WorkoutDraftStore(directory: dir)
        let entry = WorkoutSetEntry(day: day)
        let rest = RestSession()
        let planned = entry.order(in: store).blocks
        let pairIndex = try #require(planned.firstIndex(where: { $0.isSuperset }))
        let pair = planned[pairIndex]
        #expect(!entry.canMove(planned[0], direction: .up, in: store))
        entry.move(planned[0], direction: .up, in: store, startedAt: Date(), rest: rest)
        #expect(store.draft == nil)
        entry.move(pair, direction: .up, in: store, startedAt: Date(), rest: rest)
        let reordered = entry.order(in: store)
        #expect(reordered.blocks[pairIndex - 1].exercises.map(\.name) == pair.exercises.map(\.name))
        #expect(WorkoutDraftStore(directory: dir).draft?.exerciseOrder == reordered.exerciseOrder)
        let delayed = try #require(planned[pairIndex - 1].exercises.first)
        #expect(entry.preExhaustionNote(for: delayed, in: store) == "Done later than planned · a miss holds the load")
        for block in reordered.blocks.prefix(pairIndex - 1) {
            for exercise in block.exercises {
                for index in 0..<exercise.sets {
                    _ = entry.log(exercise, at: index, in: store, startedAt: Date())
                }
            }
        }
        entry.prepareNext(after: nil, in: store)
        #expect(entry.restStep?.exerciseName == pair.exercises.first?.name)
        #expect(store.draft?.payload().sets.first?.exercisePosition == 1)
    }

    @Test func reorderedMissShowsHoldReasonAndReductionWeekNoteSurvives() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        var day = ProgramV2Templates.day1LowerA
        day.weekNote = "Reduction week"
        let store = WorkoutDraftStore(directory: dir)
        let entry = WorkoutSetEntry(day: day)
        let rest = RestSession()
        let first = entry.order(in: store).blocks[0]
        entry.move(first, direction: .down, in: store, startedAt: Date(), rest: rest)
        let exercise = day.exercises[0]
        _ = entry.log(exercise, at: 0, in: store, startedAt: Date(),
                      value: LoggedSet(weight: 145, reps: 9, rir: 0, rpeText: ""))
        entry.prepareNext(after: ExerciseStep(exerciseName: exercise.name, setIndex: 0), in: store)
        let details = try #require(entry.restDetails(in: store, isHold: false))
        #expect(details.value.weight == 145)
        #expect(details.reason == "Hold: done later than planned — not counted as a miss")
        #expect(store.draft?.payload().sets.first?.exercisePosition == 2)
        #expect(store.draft?.payload().sets.first?.plannedPosition == 1)
        #expect(WorkoutDraftStore(directory: dir).draft?.programV2Day.weekNote == "Reduction week")
    }
}
