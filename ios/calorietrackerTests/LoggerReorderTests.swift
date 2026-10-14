import Foundation
import Testing
@testable import calorietracker

extension WorkoutDraftStoreTests {
    @Test func loggedBlocksCannotMoveOrBeDisplacedByTheirNeighbor() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let day = ProgramV2Templates.day4UpperPhysique
        let store = WorkoutDraftStore(directory: directory)
        let entry = WorkoutSetEntry(day: day)
        let rest = RestSession()
        let blocks = entry.order(in: store).blocks
        // Establish explicit positions before performing anything.
        entry.move(blocks[0], direction: .down, in: store, startedAt: Date(), rest: rest)
        let reordered = entry.order(in: store).blocks
        let performed = try #require(reordered[0].exercises.first)
        _ = entry.log(performed, at: 0, in: store, startedAt: Date(),
                      value: LoggedSet(weight: 25, reps: 12, rir: 2, rpeText: ""))
        let before = try #require(store.draft)
        #expect(!entry.canMove(reordered[0], direction: .down, in: store))
        #expect(!entry.canMove(reordered[1], direction: .up, in: store))
        entry.move(reordered[0], direction: .down, in: store, startedAt: Date(), rest: rest)
        entry.move(reordered[1], direction: .up, in: store, startedAt: Date(), rest: rest)
        #expect(store.draft == before)
        #expect(store.draft?.payload().sets == before.payload().sets)
        #expect(WorkoutDraftStore(directory: directory).draft == before)
        // Unstarted blocks farther down can still swap without changing performed positions.
        #expect(entry.canMove(reordered[2], direction: .down, in: store))
        entry.move(reordered[2], direction: .down, in: store, startedAt: Date(), rest: rest)
        #expect(store.draft?.payload().sets == before.payload().sets)
    }

    @Test func loggingAnySupersetMemberLocksTheWholeBlock() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let day = ProgramV2Templates.day4UpperPhysique
        let store = WorkoutDraftStore(directory: directory)
        let entry = WorkoutSetEntry(day: day)
        let rest = RestSession()
        let blocks = entry.order(in: store).blocks
        let index = try #require(blocks.firstIndex { $0.isSuperset })
        let pair = blocks[index]
        let member = try #require(pair.exercises.last)
        _ = entry.log(member, at: 0, in: store, startedAt: Date(),
                      value: LoggedSet(weight: 25, reps: 12, rir: nil, rpeText: ""))
        let before = store.draft
        #expect(!entry.canMove(pair, direction: .up, in: store))
        #expect(!entry.canMove(pair, direction: .down, in: store))
        #expect(!entry.canMove(blocks[index - 1], direction: .down, in: store))
        #expect(!entry.canMove(blocks[index + 1], direction: .up, in: store))
        entry.move(pair, direction: .up, in: store, startedAt: Date(), rest: rest)
        entry.move(blocks[index + 1], direction: .up, in: store, startedAt: Date(), rest: rest)
        #expect(store.draft == before)
    }

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
