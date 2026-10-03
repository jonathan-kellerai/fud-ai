import Foundation
import Testing
@testable import calorietracker

private func orderTestExercise(_ name: String, group: String? = nil) -> ProgramV2Exercise {
    ProgramV2Exercise(key: name.lowercased(), name: name, sets: 3, reps: "10-15",
        restSeconds: 60...60, rirTarget: "2-3 RIR", startLoadLb: 145, notes: "", supersetGroup: group)
}

private func orderTestDay() -> ProgramV2Day {
    ProgramV2Day(id: "Day", title: "Day", conditioning: "Walk", conditioningMinimum: "", exercises: [
        orderTestExercise("Press"), orderTestExercise("Curl", group: "arms"),
        orderTestExercise("Pressdown", group: "arms"), orderTestExercise("Row")
    ])
}

extension WorkoutLoggerLogicTests {
    @Test func sessionOrderMovesSupersetsAsOneBlock() {
        let planned = SupersetGrouping.blocks(for: orderTestDay().exercises)
        var order = SessionOrder(plannedBlocks: planned)
        order.move(blockAt: 1, direction: .up)
        #expect(order.exerciseOrder == ["Curl", "Pressdown", "Press", "Row"])
        #expect(order.position(for: "Press") == SessionOrder.Position(performed: 3, planned: 1))
        #expect(order.isDoneLaterThanPlanned("Press"))
        #expect(!order.isDoneLaterThanPlanned("Curl"))
        #expect(!order.isDoneLaterThanPlanned("Unknown"))
        order.move(blockAt: 0, direction: .up)
        #expect(order.exerciseOrder == ["Curl", "Pressdown", "Press", "Row"])
        order.move(blockAt: 0, direction: .down)
        #expect(order.exerciseOrder == ["Press", "Curl", "Pressdown", "Row"])
        order.move(blockAt: 1, direction: .down)
        #expect(order.exerciseOrder == ["Press", "Row", "Curl", "Pressdown"])
        order.move(blockAt: 2, direction: .down)
        order.move(blockAt: -1, direction: .up)
        order.move(blockAt: Int.min, direction: .up)
        order.move(blockAt: Int.max, direction: .down)
        #expect(order.exerciseOrder == ["Press", "Row", "Curl", "Pressdown"])
    }

    @Test func sessionOrderHandlesUnknownMissingAndNewExercises() {
        let planned = SupersetGrouping.blocks(for: orderTestDay().exercises)
        #expect(SessionOrder(plannedBlocks: planned, exerciseOrder: ["Unknown"]).exerciseOrder == ["Press", "Curl", "Pressdown", "Row"])
        let restored = SessionOrder(plannedBlocks: planned, exerciseOrder: ["Pressdown", "Unknown", "Pressdown", "Press"])
        #expect(restored.exerciseOrder == ["Curl", "Pressdown", "Press", "Row"])
        let extended = planned + [ExerciseBlock(exercises: [orderTestExercise("New")])]
        #expect(SessionOrder(plannedBlocks: extended, exerciseOrder: restored.exerciseOrder).exerciseOrder == ["Curl", "Pressdown", "Press", "Row", "New"])
        #expect(SessionOrder(plannedBlocks: [], exerciseOrder: ["Unknown"]).exerciseOrder.isEmpty)
    }

    @Test func preExhaustedChestPressHoldsWithinAndAfterSession() throws {
        let rows = [
            LoggedSet(weight: 87.5, reps: 12, rir: 2, rpeText: ""),
            LoggedSet(weight: 87.5, reps: 12, rir: 1, rpeText: ""),
            LoggedSet(weight: 87.5, reps: 9, rir: 0, rpeText: "")
        ]
        let press = orderTestExercise("Chest press machine")
        let next = SetEntryLogic.nextSetPrefill(exercise: press, setIndex: 3, sets: rows, last: nil, doneLaterThanPlanned: true)
        #expect(next.decision == ProgressionDecision(load: 87.5, reason: .holdPreFatigued))
        let normal = SetEntryLogic.nextSetPrefill(exercise: press, setIndex: 3, sets: rows, last: nil)
        #expect(normal.decision == ProgressionDecision(load: 82.5, reason: .decrease))
        let workout = RemoteWorkout(id: "9-29", kind: "COMPLETED", programVersion: "program-v2",
            programDay: "Day2", title: "Push", units: "lb", sessionDate: "2026-09-29",
            conditioning: nil, notes: [], contentHash: nil, synthetic: nil, recordedAt: nil)
        let remoteRows = rows.enumerated().map { index, row in
            RemoteWorkoutSet(id: "\(index)", workoutId: workout.id, setOrder: index,
                exercise: press.name, loadLb: row.weight, reps: row.reps, rir: row.rir, rpe: nil,
                exercisePosition: 6, plannedPosition: 1)
        }
        let detail = WorkoutDetailResponse(workout: workout, sets: remoteRows.reversed())
        let last = try #require(LastPerformanceBuilder.build(from: [detail])[LastPerformanceBuilder.key(for: press.name)])
        #expect(last.doneLaterThanPlanned)
        #expect(last.sets.map(\.reps) == [12, 12, 9])
        #expect(ProgressionRule.suggestedDecision(last: last, reps: press.reps, startLoadLb: nil) == ProgressionDecision(load: 87.5, reason: .holdPreFatigued))
        let firstNextSession = SetEntryLogic.nextSetPrefill(exercise: press, setIndex: 0, sets: [], last: last)
        #expect(firstNextSession.decision == ProgressionDecision(load: 87.5, reason: .holdPreFatigued))
        let asPlanned = remoteRows.map { row -> RemoteWorkoutSet in
            var row = row
            row.exercisePosition = 1
            return row
        }
        let normalLast = try #require(LastPerformanceBuilder.build(from: [WorkoutDetailResponse(workout: workout, sets: asPlanned)])[LastPerformanceBuilder.key(for: press.name)])
        #expect(!normalLast.doneLaterThanPlanned)
    }

    @Test func preFatigueAllowsIncreasesAndReductionAlwaysHolds() {
        let hit = WorkingSetSummary(load: 145, reps: 15, rir: 4)
        #expect(ProgressionRule.adjustedDecision(after: hit, range: RepRange(low: 10, high: 15), doneLaterThanPlanned: true) == ProgressionDecision(load: 150, reason: .increase))
        let last = LastPerformance(sessionDate: "2026-09-29", sets: [hit, WorkingSetSummary(load: 145, reps: 9, rir: 0)], doneLaterThanPlanned: true)
        #expect(ProgressionRule.suggestedDecision(last: last, reps: "10-15", startLoadLb: nil).reason == .increase)
        #expect(ProgressionRule.suggestedDecision(last: last, reps: "10-15", startLoadLb: nil, holdLoads: true) == ProgressionDecision(load: 145, reason: .holdReductionWeek))
        #expect(ProgressionRule.adjustedDecision(after: hit, range: RepRange(low: 10, high: 15), doneLaterThanPlanned: true, holdLoads: true) == ProgressionDecision(load: 145, reason: .holdReductionWeek))
        #expect(ProgressionRule.adjustedDecision(after: WorkingSetSummary(load: 145, reps: 9, rir: nil), range: RepRange(low: 10, high: 15)).reason == .decrease)
    }

    @Test func preFatigueHoldsEachFailureAndOnlyUsesCurrentSessionOrderForNextSet() {
        let exercise = orderTestExercise("Press")
        for (reps, rir) in [(9, nil as Int?), (12, 0), (9, 0)] {
            let row = LoggedSet(weight: 145, reps: reps, rir: rir, rpeText: "")
            let later = SetEntryLogic.nextSetPrefill(exercise: exercise, setIndex: 1,
                sets: [row], last: nil, doneLaterThanPlanned: true)
            #expect(later.decision == ProgressionDecision(load: 145, reason: .holdPreFatigued))
            let last = LastPerformance(sessionDate: "2026-09-29",
                sets: [WorkingSetSummary(load: 145, reps: reps, rir: rir)], doneLaterThanPlanned: true)
            #expect(ProgressionRule.suggestedLoad(last: last, reps: exercise.reps, startLoadLb: nil) == 145)
            // Yesterday's order protects yesterday's result, not a miss logged
            // in today's session when the exercise is back in planned order.
            let today = SetEntryLogic.nextSetPrefill(exercise: exercise, setIndex: 1,
                sets: [row], last: last)
            #expect(today.decision == ProgressionDecision(load: 140, reason: .decrease))
        }
    }
}

extension WorkoutDraftStoreTests {
    @Test func reorderedDraftSurvivesStoreReloadAndDayAdoption() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-order-draft-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let day = orderTestDay()
        let store = WorkoutDraftStore(directory: directory)
        store.update(day) { draft in
            draft.exerciseOrder = ["Curl", "Pressdown", "Press", "Row"]
            draft.sets["Press"] = [LoggedSet(weight: 145, reps: 12, rir: 2, rpeText: "")]
        }
        let reopened = WorkoutDraftStore(directory: directory)
        #expect(reopened.draft?.exerciseOrder == store.draft?.exerciseOrder)
        var extended = day
        extended.exercises.append(orderTestExercise("New"))
        reopened.update(extended) { $0.conditioningCompleted = true }
        let saved = try #require(WorkoutDraftStore(directory: directory).existingDraft(for: extended))
        #expect(saved.exerciseOrder == ["Curl", "Pressdown", "Press", "Row"])
        let restored = SessionOrder(plannedBlocks: SupersetGrouping.blocks(for: saved.programV2Day.exercises),
                                    exerciseOrder: saved.exerciseOrder)
        #expect(restored.exerciseOrder == ["Curl", "Pressdown", "Press", "Row", "New"])
        #expect(saved.payload().sets.first?.exercisePosition == 3)
        #expect(saved.payload().sets.first?.plannedPosition == 1)
    }

    @Test func reorderedDraftRoundTripsAndPayloadCarriesPositions() throws {
        var draft = WorkoutDraft(day: orderTestDay())
        draft.exerciseOrder = ["Curl", "Pressdown", "Press", "Row"]
        let logged = LoggedSet(weight: 145, reps: 12, rir: 2, rpeText: "")
        for name in ["Press", "Curl", "Pressdown", "Row", "Z orphan", "A orphan"] {
            draft.sets[name] = [logged]
        }
        draft.sets["Curl"] = [logged, logged]
        let decoded = try JSONDecoder().decode(WorkoutDraft.self, from: JSONEncoder().encode(draft))
        #expect(decoded == draft)
        #expect(decoded.exerciseOrder == draft.exerciseOrder)
        let sets = decoded.payload().sets
        #expect(sets.map(\.exercise) == ["Curl", "Curl", "Pressdown", "Press", "Row", "A orphan", "Z orphan"])
        #expect(sets.map(\.order) == [0, 1, 2, 3, 4, 5, 6])
        #expect(sets.map(\.exercisePosition) == [1, 1, 2, 3, 4, 5, 6])
        #expect(sets.map(\.plannedPosition) == [2, 2, 3, 1, 4, 5, 6])
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(sets)) as? [[String: Any]])
        #expect(json[3]["exercise_position"] as? Int == 3)
        #expect(json[3]["planned_position"] as? Int == 1)
        #expect(json[3]["exercisePosition"] == nil)
    }

    @Test func legacyPayloadSetJSONIsByteIdentical() throws {
        var draft = WorkoutDraft(day: orderTestDay())
        draft.sets["Press"] = [LoggedSet(weight: 145, reps: 12, rir: 2, rpeText: "8")]
        draft.sets["Orphan"] = [LoggedSet(weight: 0, reps: 10, rir: 0, rpeText: "")]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(draft.payload().sets)
        let expected = #"[{"exercise":"Press","load":145,"order":0,"reps":12,"rir":2,"rpe":8},{"exercise":"Orphan","load":0,"order":1,"reps":10,"rir":0}]"#
        #expect(encoded == Data(expected.utf8))
        let object = try #require(JSONSerialization.jsonObject(with: encoder.encode(draft)) as? [String: Any])
        #expect(object["exerciseOrder"] == nil)
        draft.exerciseOrder = []
        #expect(draft.payload().sets.map(\.exercisePosition) == [1, 5])
        #expect(draft.payload().sets.map(\.plannedPosition) == [1, 5])
    }

    @Test func legacyDraftWithoutOrderKeepsEntirePayloadJSON() throws {
        let fixture = #"{"programDay":"Day1","title":"Lower A","conditioning":"Walk","conditioningMinimum":"","exercises":[{"key":"press","name":"Press","sets":3,"reps":"10-15","restLowerSeconds":60,"restUpperSeconds":60,"rirTarget":"2","startLoadLb":145,"notes":"","loadNote":""}],"sets":{"Press":[{"weight":145,"reps":12,"rir":2,"rpeText":"8"}]},"conditioningCompleted":true,"sessionDate":"2026-09-29","updatedAt":0}"#
        let draft = try JSONDecoder().decode(WorkoutDraft.self, from: Data(fixture.utf8))
        #expect(draft.exerciseOrder == nil)
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-29T12:00:00Z"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let expected = #"{"conditioning":"Walk","kind":"COMPLETED","notes":[],"opened_at_utc":"2026-09-29T12:00:00.000Z","program_day":"Day1","program_version":"program-v2","recorded_at_utc":"2026-09-29T12:00:00.000Z","session_date":"2026-09-29","sets":[{"exercise":"Press","load":145,"order":0,"reps":12,"rir":2,"rpe":8}],"source":"jl-fud-native","title":"Lower A","units":"lb"}"#
        #expect(try encoder.encode(draft.payload(now: now)) == Data(expected.utf8))
    }

    @Test func remoteSetsDecodePositionsAndLegacyAbsence() throws {
        let legacy = #"{"id":"s1","workout_id":"w1","set_order":0,"exercise":"Press","load_lb":87.5,"reps":9,"rir":0}"#
        let ordered = #"{"id":"s1","workout_id":"w1","set_order":0,"exercise":"Press","load_lb":87.5,"reps":9,"rir":0,"exercise_position":6,"planned_position":1}"#
        let decoder = JSONDecoder()
        let old = try decoder.decode(RemoteWorkoutSet.self, from: Data(legacy.utf8))
        #expect(old.exercisePosition == nil)
        #expect(old.plannedPosition == nil)
        let new = try decoder.decode(RemoteWorkoutSet.self, from: Data(ordered.utf8))
        #expect(new.exercisePosition == 6)
        #expect(new.plannedPosition == 1)
        let roundTrip = try decoder.decode(RemoteWorkoutSet.self, from: JSONEncoder().encode(new))
        #expect(roundTrip == new)
    }

    @Test func partialAndNullRemotePositionsDoNotInferPreFatigue() throws {
        let workout = RemoteWorkout(id: "w1", kind: "COMPLETED", programVersion: "program-v2",
            programDay: "Day1", title: "Push", units: "lb", sessionDate: "2026-09-29",
            conditioning: nil, notes: [], contentHash: nil, synthetic: nil, recordedAt: nil)
        for positions in ["", #",\"exercise_position\":null,\"planned_position\":null"#,
                          #",\"exercise_position\":6"#, #",\"planned_position\":1"#,
                          #",\"exercise_position\":1,\"planned_position\":6"#] {
            let json = #"{"id":"s1","set_order":0,"exercise":"Press","load_lb":145,"reps":9,"rir":0"# + positions + "}"
            let row = try JSONDecoder().decode(RemoteWorkoutSet.self, from: Data(json.utf8))
            let last = try #require(LastPerformanceBuilder.build(from: [WorkoutDetailResponse(workout: workout, sets: [row])])["press"])
            #expect(!last.doneLaterThanPlanned)
            #expect(ProgressionRule.suggestedDecision(last: last, reps: "10-15", startLoadLb: nil)
                == ProgressionDecision(load: 140, reason: .decrease))
        }
    }
}
