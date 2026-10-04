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
