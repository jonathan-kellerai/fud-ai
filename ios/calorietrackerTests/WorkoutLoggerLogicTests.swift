import Foundation
import Testing
@testable import calorietracker

/// Supersets, rest timing, last-session history and load progression in the
/// Program V2 logger are pure rules; these pin them down.
@MainActor
struct WorkoutLoggerLogicTests {
    // MARK: - Grouping

    @Test func explicitGroupFormsOneBlock() {
        let exercises = [
            exercise("Cable lateral raise", rest: 60),
            exercise("Curl", rest: 60, group: "arms"),
            exercise("Pressdown", rest: 60, group: "arms"),
            exercise("Bridge", rest: 60),
        ]

        let blocks = SupersetGrouping.blocks(for: exercises)

        #expect(blocks.map { $0.exercises.map(\.name) } == [
            ["Cable lateral raise"],
            ["Curl", "Pressdown"],
            ["Bridge"],
        ])
        #expect(blocks[1].isSuperset)
        #expect(!blocks[0].isSuperset)
    }

    @Test func explicitGroupWinsOverRestZeroFallback() {
        let exercises = [
            exercise("Curl", rest: 0, group: "arms"),
            exercise("Pressdown", rest: 60, group: "arms"),
            exercise("Bridge", rest: 60),
        ]

        let blocks = SupersetGrouping.blocks(for: exercises)

        #expect(blocks.map { $0.exercises.map(\.name) } == [["Curl", "Pressdown"], ["Bridge"]])
    }

    @Test func bundledDayFourPairsCurlAndPressdown() throws {
        let day = TrainingProgramBody.bundledV2().days[3]
        let names = day.exercises.map(\.name)
        #expect(names == [
            "Incline chest press machine",
            "Reverse pec deck / rear-delt machine",
            "Cable lateral raise",
            "Cable or DB curl",
            "Triceps pressdown",
            "CC bridge ladder - step 1 Short bridge",
        ])
        let curl = try #require(day.exercises.first { $0.name == "Cable or DB curl" })
        #expect(curl.restSec == 0)
        #expect(curl.supersetGroup == "curl-pressdown")

        let blocks = SupersetGrouping.blocks(for: day.asProgramV2Day().exercises)
        #expect(blocks.map { $0.exercises.map(\.name) } == [
            ["Incline chest press machine"],
            ["Reverse pec deck / rear-delt machine"],
            ["Cable lateral raise"],
            ["Cable or DB curl", "Triceps pressdown"],
            ["CC bridge ladder - step 1 Short bridge"],
        ])
    }

    @Test func restZeroFallbackGroupsBundledDayFourWithoutGroups() {
        var day = TrainingProgramBody.bundledV2().days[3]
        for index in day.exercises.indices {
            day.exercises[index].supersetGroup = nil
        }

        let blocks = SupersetGrouping.blocks(for: day.asProgramV2Day().exercises)

        let superset = blocks.filter(\.isSuperset)
        #expect(superset.count == 1)
        #expect(superset.first?.exercises.map(\.name) == ["Cable or DB curl", "Triceps pressdown"])
        #expect(blocks.count == 5)
    }

    @Test func restZeroFallbackGroupsDecodedProgramJSON() throws {
        let json = """
        {"day_index": 4, "weekday": "thu", "name": "Upper Physique", "conditioning": null,
         "exercises": [
           {"order": 3, "name": "Cable lateral raise", "sets": 2, "reps": "12-15", "rir": "2-3 RIR", "rest_sec": 60},
           {"order": 4, "name": "Cable or DB curl", "sets": 2, "reps": "12-15", "rir": "2-3 RIR", "rest_sec": 0,
            "load_note": "SELECT ON FIRST SESSION"},
           {"order": 5, "name": "Triceps pressdown", "sets": 2, "reps": "12-15", "rir": "2-3 RIR", "rest_sec": 60,
            "load_note": "Start 125 lb"}
         ]}
        """
        let day = try JSONDecoder().decode(TrainingProgramDay.self, from: Data(json.utf8))
        #expect(day.exercises.allSatisfy { $0.supersetGroup == nil })

        let exercises = day.asProgramV2Day().exercises
        let blocks = SupersetGrouping.blocks(for: exercises)

        #expect(blocks.map { $0.exercises.map(\.name) } == [
            ["Cable lateral raise"],
            ["Cable or DB curl", "Triceps pressdown"],
        ])
        #expect(exercises[1].startLoadLb == nil)
        #expect(exercises[2].startLoadLb == 125)
    }

    @Test func restZeroFallbackChainsConsecutiveZeroRests() {
        let blocks = SupersetGrouping.blocks(for: [
            exercise("A", rest: 0),
            exercise("B", rest: 0),
            exercise("C", rest: 90),
            exercise("D", rest: 60),
        ])

        #expect(blocks.map { $0.exercises.map(\.name) } == [["A", "B", "C"], ["D"]])
    }

    @Test func restZeroExerciseThatIsLastStaysSingle() {
        let blocks = SupersetGrouping.blocks(for: [
            exercise("Row", rest: 90),
            exercise("Finisher", rest: 0),
        ])

        #expect(blocks.map { $0.exercises.map(\.name) } == [["Row"], ["Finisher"]])
        #expect(blocks.allSatisfy { !$0.isSuperset })
    }

    // MARK: - Rest policy

    @Test func noTimerAfterFirstMemberSet() {
        let block = curlPressdown()
        let sets: [String: [LoggedSet]] = [
            "Curl": [logged(12), empty()],
            "Pressdown": [empty(), empty()],
        ]

        #expect(SupersetGrouping.restSeconds(afterLogging: "Curl", setIndex: 0, in: block, sets: sets) == nil)
    }

    @Test func timerAfterSecondMemberCompletesRound() {
        let block = curlPressdown()
        let sets: [String: [LoggedSet]] = [
            "Curl": [logged(12), empty()],
            "Pressdown": [logged(14), empty()],
        ]

        #expect(SupersetGrouping.restSeconds(afterLogging: "Pressdown", setIndex: 0, in: block, sets: sets) == 60)
    }

    @Test func noTimerAfterSecondMemberWhenFirstNotLogged() {
        let block = curlPressdown()
        let sets: [String: [LoggedSet]] = [
            "Curl": [empty(), empty()],
            "Pressdown": [logged(14), empty()],
        ]

        #expect(SupersetGrouping.restSeconds(afterLogging: "Pressdown", setIndex: 0, in: block, sets: sets) == nil)
    }

    @Test func timerAfterFirstMemberWhenSecondAlreadyLogged() {
        let block = curlPressdown()
        let sets: [String: [LoggedSet]] = [
            "Curl": [logged(12), logged(12)],
            "Pressdown": [logged(14), logged(13)],
        ]

        #expect(SupersetGrouping.restSeconds(afterLogging: "Curl", setIndex: 1, in: block, sets: sets) == 60)
    }

    @Test func supersetRestFallsBackToLargestThenSixty() {
        let largest = ExerciseBlock(exercises: [exercise("A", rest: 75), exercise("B", rest: 0)])
        #expect(SupersetGrouping.supersetRestSeconds(for: largest) == 75)

        let none = ExerciseBlock(exercises: [exercise("A", rest: 0), exercise("B", rest: 0)])
        #expect(SupersetGrouping.supersetRestSeconds(for: none) == 60)
    }

    @Test func singleExerciseUsesItsRest() {
        let block = ExerciseBlock(exercises: [exercise("Leg press", rest: 90, upper: 120)])
        let sets: [String: [LoggedSet]] = ["Leg press": [logged(12)]]

        #expect(SupersetGrouping.restSeconds(afterLogging: "Leg press", setIndex: 0, in: block, sets: sets) == 90)
    }

    @Test func restZeroSingleExerciseHasNoTimer() {
        let block = ExerciseBlock(exercises: [exercise("Finisher", rest: 0)])
        let sets: [String: [LoggedSet]] = ["Finisher": [logged(12)]]

        #expect(SupersetGrouping.restSeconds(afterLogging: "Finisher", setIndex: 0, in: block, sets: sets) == nil)
    }

    @Test func nextUpAlternatesMembers() {
        let block = curlPressdown()
        var sets: [String: [LoggedSet]] = [:]

        #expect(SupersetGrouping.nextUp(in: block, sets: sets) == ExerciseStep(exerciseName: "Curl", setIndex: 0))

        sets["Curl"] = [logged(12)]
        #expect(SupersetGrouping.nextUp(in: block, sets: sets) == ExerciseStep(exerciseName: "Pressdown", setIndex: 0))

        sets["Pressdown"] = [logged(14)]
        #expect(SupersetGrouping.nextUp(in: block, sets: sets) == ExerciseStep(exerciseName: "Curl", setIndex: 1))

        sets["Curl"] = [logged(12), logged(11)]
        #expect(SupersetGrouping.nextUp(in: block, sets: sets) == ExerciseStep(exerciseName: "Pressdown", setIndex: 1))

        sets["Pressdown"] = [logged(14), logged(13)]
        #expect(SupersetGrouping.nextUp(in: block, sets: sets) == nil)
        #expect(block.memberLabel(for: "Pressdown") == "B")
    }

    @Test func nextUpSkipsEmptyRowsAlreadyAdded() {
        let block = curlPressdown()
        let sets: [String: [LoggedSet]] = [
            "Curl": [logged(12), empty()],
            "Pressdown": [logged(14), empty()],
        ]

        #expect(SupersetGrouping.nextUp(in: block, sets: sets) == ExerciseStep(exerciseName: "Curl", setIndex: 1))
    }

    // MARK: - Progression

    @Test func topOfRangeWithFourRIRAddsFive() {
        #expect(suggest(load: 110, reps: 15, rir: 4, range: "10-15") == 115)
    }

    @Test func aboveTopOfRangeWithFiveRIRAddsFive() {
        #expect(suggest(load: 110, reps: 17, rir: 5, range: "10-15") == 115)
    }

    @Test func topOfRangeWithThreeRIRHolds() {
        #expect(suggest(load: 110, reps: 15, rir: 3, range: "10-15") == 110)
    }

    @Test func inRangeHolds() {
        #expect(suggest(load: 110, reps: 12, rir: 2, range: "10-15") == 110)
    }

    @Test func belowRangeDropsFive() {
        #expect(suggest(load: 110, reps: 8, rir: 2, range: "10-15") == 105)
    }

    @Test func zeroRIRInRangeDropsFive() {
        #expect(suggest(load: 110, reps: 12, rir: 0, range: "10-15") == 105)
    }

    @Test func dropNeverGoesBelowZero() {
        #expect(suggest(load: 3, reps: 5, rir: 2, range: "10-15") == 0)
    }

    @Test func bodyweightStaysZero() {
        #expect(suggest(load: 0, reps: 20, rir: 5, range: "8-15") == 0)
    }

    @Test func nilRIRInRangeHolds() {
        #expect(suggest(load: 110, reps: 15, rir: nil, range: "10-15") == 110)
    }

    @Test func noHistoryUsesStartLoad() {
        #expect(ProgressionRule.suggestedLoad(last: nil, reps: "10-15", startLoadLb: 145) == 145)
    }

    @Test func noHistoryAndSelectOnFirstSessionIsNil() throws {
        #expect(ProgressionRule.suggestedLoad(last: nil, reps: "12-15", startLoadLb: nil) == nil)

        let curl = try #require(ProgramV2Templates.day3PullHinge.exercises.first { $0.name == "Cable or DB curl" })
        #expect(curl.startLoadLb == nil)
        #expect(ProgressionRule.suggestedLoad(last: nil, reps: curl.reps, startLoadLb: curl.startLoadLb) == nil)
    }

    @Test func parsesRepRanges() {
        #expect(ProgressionRule.repRange("10-15") == RepRange(low: 10, high: 15))
        #expect(ProgressionRule.repRange("10–15") == RepRange(low: 10, high: 15))
        #expect(ProgressionRule.repRange("12 - 15") == RepRange(low: 12, high: 15))
        #expect(ProgressionRule.repRange("8") == RepRange(low: 8, high: 8))
        #expect(ProgressionRule.repRange("8-12/leg") == RepRange(low: 8, high: 12))
        #expect(ProgressionRule.repRange("AMRAP") == nil)
    }

    @Test func singleRepTargetProgresses() {
        #expect(suggest(load: 100, reps: 8, rir: 4, range: "8") == 105)
        #expect(suggest(load: 100, reps: 7, rir: 2, range: "8") == 95)
    }

    // MARK: - Last performance

    @Test func lastPerformancePicksMostRecentSessionAcrossDays() {
        let newest = detail(id: "w3", day: "3-wed", date: "2026-09-30T00:00:00.000Z", sets: [
            remoteSet("Cable or DB curl ", order: 2, load: 30, reps: 12, rir: 2),
            remoteSet("cable or db curl", order: 1, load: 25, reps: 15, rir: 3),
            remoteSet("Chest-supported row", order: 3, load: 110, reps: 0, rir: nil),
        ])
        let older = detail(id: "w4", day: "4-thu", date: "2026-09-25", sets: [
            remoteSet("Cable or DB curl", order: 1, load: 20, reps: 12, rir: 2),
            remoteSet("Triceps pressdown", order: 2, load: 125, reps: 14, rir: 1),
            remoteSet("Chest-supported row", order: 3, load: 105, reps: 10, rir: 2),
        ])

        let map = LastPerformanceBuilder.build(from: [newest, older])

        let curl = map["cable or db curl"]
        #expect(curl?.sessionDate == "2026-09-30")
        #expect(curl?.sets == [
            WorkingSetSummary(load: 25, reps: 15, rir: 3),
            WorkingSetSummary(load: 30, reps: 12, rir: 2),
        ])
        #expect(curl?.heaviestLoad == 30)
        #expect(map["triceps pressdown"]?.sessionDate == "2026-09-25")
        // A session whose only sets have 0 reps does not count.
        #expect(map["chest-supported row"]?.firstSet == WorkingSetSummary(load: 105, reps: 10, rir: 2))
        #expect(map[LastPerformanceBuilder.key(for: "  Triceps Pressdown ")] != nil)
    }

    @Test func historyCandidatesDropSyntheticAndSortByDay() {
        let workouts = [
            remoteWorkout("a", date: "2026-09-28"),
            remoteWorkout("b", date: "2026-09-30T00:00:00.000Z", synthetic: true),
            remoteWorkout("c", date: "2026-09-29"),
            remoteWorkout("d", date: "2026-09-29T00:00:00.000Z"),
        ]

        #expect(ExerciseHistoryLoader.orderedCandidates(workouts).map(\.id) == ["c", "d", "a"])
    }

    @Test func formatsLastLine() {
        let performance = LastPerformance(sessionDate: "2026-09-29", sets: [WorkingSetSummary(load: 110, reps: 12, rir: 2)])
        #expect(LoggerFormatting.lastLine(performance) == "Last: 110 × 12 @ RIR 2")

        let noRIR = LastPerformance(sessionDate: "2026-09-29", sets: [WorkingSetSummary(load: 112.5, reps: 10, rir: nil)])
        #expect(LoggerFormatting.lastLine(noRIR) == "Last: 112.5 × 10")
    }

    // MARK: - Program model

    @Test func exerciseDecodesSupersetGroupAndOmitsNilOnEncode() throws {
        let grouped = try JSONDecoder().decode(TrainingProgramExercise.self, from: Data("""
        {"order": 4, "name": "Cable or DB curl", "sets": 2, "reps": "12-15", "rest_sec": 0, "superset_group": "curl-pressdown"}
        """.utf8))
        #expect(grouped.supersetGroup == "curl-pressdown")
        #expect(grouped.restSec == 0)

        let groupedObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(grouped)) as? [String: Any]
        #expect(groupedObject?["superset_group"] as? String == "curl-pressdown")

        let plain = TrainingProgramExercise(order: 0, name: "Leg press", sets: 3, reps: "10-15", restSec: 90)
        let plainObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any]
        #expect(plainObject?.keys.contains("superset_group") == false)
    }

    @Test func templatesMatchProgramV3() throws {
        let pull = ProgramV2Templates.day3PullHinge.exercises
        #expect(pull.last?.name == "Cable or DB curl")
        #expect(pull.last?.restSeconds == 60...60)
        #expect(pull.last?.sets == 2)
        #expect(pull.last?.supersetGroup == nil)

        let physique = ProgramV2Templates.day4UpperPhysique.exercises
        let curlIndex = try #require(physique.firstIndex { $0.name == "Cable or DB curl" })
        #expect(physique[curlIndex - 1].name == "Cable lateral raise")
        #expect(physique[curlIndex].restSeconds == 0...0)
        #expect(physique[curlIndex + 1].name == "Triceps pressdown")
        #expect(physique[curlIndex + 1].startLoadLb == 125)
        #expect(physique.last?.name == "CC bridge ladder - step 1 Short bridge")

        #expect(ProgramV2Templates.restLowerBound(matching: "Triceps pressdown") == 60)
        #expect(ProgramV2Templates.restLowerBound(matching: "Cable or DB curl") == 60)
    }

    // MARK: - Helpers

    private func exercise(_ name: String, rest: Int, upper: Int? = nil, group: String? = nil) -> ProgramV2Exercise {
        ProgramV2Exercise(
            key: name.lowercased(),
            name: name,
            sets: 2,
            reps: "12-15",
            restSeconds: rest...(upper ?? rest),
            rirTarget: "2-3 RIR",
            startLoadLb: nil,
            notes: "",
            supersetGroup: group
        )
    }

    private func curlPressdown() -> ExerciseBlock {
        ExerciseBlock(exercises: [
            exercise("Curl", rest: 0, group: "arms"),
            exercise("Pressdown", rest: 60, group: "arms"),
        ])
    }

    private func logged(_ reps: Int) -> LoggedSet {
        LoggedSet(weight: 30, reps: reps, rir: 2, rpeText: "")
    }

    private func empty() -> LoggedSet {
        LoggedSet(weight: 30, reps: 0, rir: 2, rpeText: "")
    }

    private func suggest(load: Double, reps: Int, rir: Int?, range: String) -> Double? {
        let last = LastPerformance(sessionDate: "2026-09-29", sets: [
            WorkingSetSummary(load: load, reps: reps, rir: rir),
            WorkingSetSummary(load: load, reps: 1, rir: 0),
        ])
        return ProgressionRule.suggestedLoad(last: last, reps: range, startLoadLb: 999)
    }

    private func remoteWorkout(_ id: String, day: String = "1-mon", date: String, synthetic: Bool? = nil) -> RemoteWorkout {
        RemoteWorkout(
            id: id,
            kind: "COMPLETED",
            programVersion: "program-v2",
            programDay: day,
            title: day,
            units: "lb",
            sessionDate: date,
            conditioning: nil,
            notes: [],
            contentHash: nil,
            synthetic: synthetic,
            recordedAt: nil
        )
    }

    private func detail(id: String, day: String, date: String, sets: [RemoteWorkoutSet]) -> WorkoutDetailResponse {
        WorkoutDetailResponse(workout: remoteWorkout(id, day: day, date: date), sets: sets)
    }

    private func remoteSet(_ exercise: String, order: Int, load: Double, reps: Int, rir: Int?) -> RemoteWorkoutSet {
        RemoteWorkoutSet(
            id: "\(exercise)-\(order)",
            workoutId: nil,
            setOrder: order,
            exercise: exercise,
            loadLb: load,
            reps: reps,
            rir: rir,
            rpe: nil
        )
    }
}
