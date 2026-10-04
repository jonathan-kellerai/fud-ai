import Foundation
import Testing
@testable import calorietracker

extension WorkoutLoggerLogicTests {
    @Test func rirTargetsCoverTemplatesAndBridgeNotes() {
        // Every distinct template and bridge-fixture target, plus legacy numeric targets.
        let cases: [(String, [Int?])] = [
            ("2-3 RIR", [2, 2, 2]),
            ("sets 1-2: 2-3 RIR; last set 1-2 RIR", [2, 2, 1]),
            ("set 1 ~3 RIR, set 2 ~2 RIR", [3, 2]),
            ("stop every set at 1-2 RIR; NO set to 0 RIR", [1, 1, 1]),
            ("set 1 ~4 RIR, sets 2-3 2-3 RIR", [4, 2, 2]),
            ("2-3 RIR; last set 1-2", [2, 2, 1]),
            ("2 RIR", [2, 2]), ("1-2 RIR", [1, 1]), ("3-4 RIR", [3, 3]),
            ("2", [2, 2]), ("", [nil]), ("unknown", [nil]),
            ("0 RIR", [1]), ("~3 RIR", [3]), ("2–3 RIR", [2])
        ]
        let covered = Set(cases.map { $0.0 })
        #expect(Set(ProgramV2Templates.allDays.flatMap(\.exercises).map(\.rirTarget)).isSubset(of: covered))
        for (target, expected) in cases {
            let bridgeExercise = ProgramV2Exercise(key: "test", name: "Test", sets: expected.count,
                reps: "10-15", restSeconds: 60...60, rirTarget: "", startLoadLb: 100,
                notes: "Rest: 60 s. RIR target: \(target). Baseline: 100x12 @ RIR 0.")
            #expect(RIRTargetParser.target(for: bridgeExercise) == target)
            for (index, value) in expected.enumerated() {
                #expect(RIRTargetParser.defaultRIR(for: target, setIndex: index, setCount: expected.count) == value)
                #expect(RIRTargetParser.defaultRIR(for: RIRTargetParser.target(for: bridgeExercise),
                    setIndex: index, setCount: expected.count) == value)
            }
        }
        let explicit = ProgramV2Exercise(key: "test", name: "Test", sets: 1, reps: "10-15",
            restSeconds: 60...60, rirTarget: "2", startLoadLb: nil, notes: "RIR target: 4 RIR.")
        #expect(RIRTargetParser.target(for: explicit) == "2")
    }

    @Test func defaultRIRDoesNotManufactureProgressionFailure() {
        let rir = RIRTargetParser.defaultRIR(for: "2-3 RIR", setIndex: 0, setCount: 3)
        let last = LastPerformance(sessionDate: "2026-10-02", sets: [WorkingSetSummary(load: 145, reps: 12, rir: rir)])
        #expect(ProgressionRule.suggestedLoad(last: last, reps: "10-15", startLoadLb: nil) == 145)
    }
}

extension WorkoutDraftStoreTests {
    @Test func unfinishedListAndRestRefreshTogetherAfterEasySetsAndMisses() throws {
        for (reps, rir, expectedLoad) in [(15, 4, 150.0), (9, 0, 140.0)] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            var day = ProgramV2Templates.day1LowerA
            let base = day.exercises[0]
            let exercise = ProgramV2Exercise(key: base.key, name: base.name, sets: base.sets,
                reps: base.reps, restSeconds: base.restSeconds, rirTarget: "", startLoadLb: base.startLoadLb,
                notes: "RIR target: sets 1-2: 2-3 RIR; last set 1-2 RIR.")
            day.exercises = [exercise]
            let store = WorkoutDraftStore(directory: directory)
            let entry = WorkoutSetEntry(day: day)
            entry.add(exercise, in: store, startedAt: Date())
            entry.add(exercise, in: store, startedAt: Date())
            // Simulate an old draft's default RIR without edit metadata.
            store.update(day) { $0.sets[exercise.name]?[1].rir = 0 }
            let first = LoggedSet(weight: 145, reps: reps, rir: rir, rpeText: "7")
            #expect(entry.log(exercise, at: 0, in: store, startedAt: Date(), value: first) == 0)
            let list = entry.row(for: exercise, at: 1, in: store)
            entry.prepareNext(after: nil, in: store)
            #expect(list.weight == expectedLoad)
            #expect(list.rir == 2)
            #expect(entry.nextValue?.weight == list.weight)
            #expect(entry.nextValue?.rir == list.rir)
            #expect(store.draft?.sets[exercise.name]?.first == first)
            entry.refreshPrefilledLoads(in: store, startedAt: Date())
            let reopened = WorkoutDraftStore(directory: directory)
            #expect(reopened.draft?.sets[exercise.name]?[1].weight == expectedLoad)
            #expect(reopened.draft?.sets[exercise.name]?[1].rir == 2)
            #expect(reopened.draft?.loggedSetCount == 1)
            // Typing the actual reps commits the refreshed values without a checkmark.
            entry.edit(exercise, at: 1, in: reopened, startedAt: Date(), field: .reps) { $0.reps = 12 }
            #expect(reopened.draft?.payload().sets.last?.load == expectedLoad)
            #expect(reopened.draft?.payload().sets.last?.rir == 2)
        }
    }

    @Test func explicitUnfinishedLoadAndUnknownRIRSurviveRefreshAndReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var day = ProgramV2Templates.day1LowerA
        day.exercises = [day.exercises[0]]
        let exercise = day.exercises[0]
        let store = WorkoutDraftStore(directory: directory)
        let entry = WorkoutSetEntry(day: day)
        entry.add(exercise, in: store, startedAt: Date())
        entry.add(exercise, in: store, startedAt: Date())
        // Explicitly choose the existing load: equality with a prefill is still an edit.
        entry.edit(exercise, at: 1, in: store, startedAt: Date(), field: .load) { $0.weight = 145 }
        entry.edit(exercise, at: 1, in: store, startedAt: Date(), field: .rir) { $0.rir = nil }
        _ = entry.log(exercise, at: 0, in: store, startedAt: Date(),
                      value: LoggedSet(weight: 145, reps: 15, rir: 4, rpeText: ""))
        let reopened = WorkoutDraftStore(directory: directory)
        let resumed = WorkoutSetEntry(day: try #require(reopened.draft).programV2Day)
        resumed.refreshPrefilledLoads(in: reopened, startedAt: Date())
        let list = resumed.row(for: exercise, at: 1, in: reopened)
        resumed.prepareNext(after: nil, in: reopened)
        #expect(list.weight == 145)
        #expect(list.rir == nil)
        #expect(resumed.nextValue?.weight == list.weight)
        #expect(resumed.nextValue?.rir == list.rir)
        #expect(reopened.draft?.loggedSetCount == 1)
        resumed.edit(exercise, at: 1, in: reopened, startedAt: Date(), field: .rir) { $0.rir = 0 }
        resumed.refreshPrefilledLoads(in: reopened, startedAt: Date())
        #expect(resumed.row(for: exercise, at: 1, in: reopened).rir == 0)
    }

    @Test func notesBasedRIRDefaultsSurviveOneTapLoggingAndReload() throws {
        let startedAt = ISO8601DateFormatter().date(from: "2026-10-05T16:00:00Z")!
        let cases: [(String, [Int?])] = [
            ("sets 1-2: 2-3 RIR; last set 1-2 RIR", [2, 2, 1]),
            ("0 RIR", [1, 1, 1]),
            ("unknown", [nil, nil, nil]),
        ]
        for (target, expected) in cases {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("rir-entry-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let exercise = ProgramV2Exercise(key: "press", name: "Press", sets: 3, reps: "10-15",
                restSeconds: 90...120, rirTarget: "", startLoadLb: 145,
                notes: "Rest: 90-120 s. RIR target: \(target).")
            let day = ProgramV2Day(id: "Day", title: "Day", conditioning: "", conditioningMinimum: "",
                exercises: [exercise])
            let store = WorkoutDraftStore(directory: directory)
            let entry = WorkoutSetEntry(day: day)
            #expect(store.draft == nil)
            for index in expected.indices {
                let ghost = entry.row(for: exercise, at: index, in: store)
                #expect(ghost.rir == expected[index])
                #expect(ghost.weight == 145)
                #expect(entry.log(exercise, at: index, in: store, startedAt: startedAt) == index)
            }
            let restored = try #require(WorkoutDraftStore(directory: directory).draft)
            #expect(restored.sets[exercise.name]?.map(\.rir) == expected)
            #expect(restored.payload().sets.map(\.rir) == expected)
            #expect(restored.sets[exercise.name]?.map(\.weight) == [145, 145, 145])
        }
    }

    @Test func build61DraftDecodesIntegerRIR() throws {
        let json = #"{"programDay":"Day1_LowerA","title":"Lower A","conditioning":"Walk","conditioningMinimum":"","exercises":[{"key":"leg press","name":"Leg press","sets":3,"reps":"10-15","restLowerSeconds":90,"restUpperSeconds":120,"rirTarget":"2","startLoadLb":145,"notes":"","loadNote":""}],"sets":{"Leg press":[{"weight":145,"reps":12,"rir":0,"rpeText":"8"}]},"conditioningCompleted":false,"sessionDate":"2026-10-02","startedAt":812678400,"updatedAt":812678400}"#
        let draft = try JSONDecoder().decode(WorkoutDraft.self, from: Data(json.utf8))
        #expect(draft.sets["Leg press"]?.first?.rir == 0)
        #expect(draft.payload().sets.first?.rir == 0)
        let roundTrip = try JSONDecoder().decode(WorkoutDraft.self, from: JSONEncoder().encode(draft))
        #expect(roundTrip == draft)
        let unknown = try JSONDecoder().decode(LoggedSet.self,
            from: Data(#"{"weight":145,"reps":12,"rpeText":""}"#.utf8))
        #expect(unknown.rir == nil)
    }
}
