import Foundation
import Testing
@testable import calorietracker

private func weekRulesDate(_ text: String) -> Date {
    SessionDateFormatting.date(from: text, calendar: ProgramWeekRules.easternCalendar)!
}

private func weekRulesV4Body() -> TrainingProgramBody {
    // The bundled fallback is V3; live bridge V4 added the overhead extension
    // and raised Day 3 curls to three sets (program-v2.bridge-body.json).
    var body = TrainingProgramBody.bundledV2()
    body.days[1].exercises[4].order = 5
    body.days[1].exercises.append(TrainingProgramExercise(order: 4,
        name: "Overhead triceps extension (cable or DB)", sets: 2, reps: "10-15",
        rir: "", restSec: 60, notes: "Rest: 60-75 s. RIR target: 1-2 RIR."))
    if let curlIndex = body.days[2].exercises.firstIndex(where: { $0.name == "Cable or DB curl" }) {
        body.days[2].exercises[curlIndex].sets = 3
    }
    return body
}

extension WorkoutLoggerLogicTests {
    @Test func weekThreeAddsOnlyApprovedArmSets() {
        var body = weekRulesV4Body()
        body.reductionWeek = 4
        for dayIndex in [2, 3] {
            let day = body.days[dayIndex - 1]
            let adjusted = body.programV2Day(for: day, on: weekRulesDate("2026-10-12"))
            let target = dayIndex == 2 ? "Overhead triceps extension (cable or DB)" : "Cable or DB curl"
            for (base, actual) in zip(day.exercises.sorted { $0.order < $1.order }, adjusted.exercises) {
                #expect(actual.sets == base.sets + (base.name == target ? 1 : 0))
            }
            #expect(adjusted.exercises.first { $0.name == target }?.sets == (dayIndex == 2 ? 3 : 4))
            #expect(adjusted.weekNote != nil)
            for date in ["2026-10-05", "2026-10-26"] {
                let unchanged = body.programV2Day(for: day, on: weekRulesDate(date))
                #expect(unchanged.exercises.map(\.sets) == day.exercises.sorted { $0.order < $1.order }.map(\.sets))
                #expect(unchanged.weekNote == nil)
                #expect(!unchanged.holdLoads)
            }
        }
        #expect(ProgramWeekRules.weekNumber(on: weekRulesDate("2026-10-18"), body: body) == 3)
        #expect(ProgramWeekRules.weekNumber(on: weekRulesDate("2026-10-19"), body: body) == 4)
        #expect(ProgramWeekRules.weekNumber(on: weekRulesDate("2026-09-27"), body: body) == nil)
        #expect(ProgramWeekRules.weekNumber(on: weekRulesDate("2026-11-02"), body: body) == 6)
        // ET Sunday even though UTC is already Monday.
        let sunday = ISO8601DateFormatter().date(from: "2026-10-19T02:00:00Z")!
        #expect(ProgramWeekRules.weekNumber(on: sunday, body: body) == 3)
    }

    @Test func reductionWeekCutsSetsAndHoldsLastUsedLoads() {
        var body = weekRulesV4Body()
        body.reductionWeek = 4
        for day in body.days {
            let adjusted = body.programV2Day(for: day, on: weekRulesDate("2026-10-20"))
            #expect(adjusted.holdLoads)
            #expect(adjusted.weekNote?.hasPrefix("Reduction week:") == true)
            for exercise in adjusted.exercises {
                #expect(exercise.rirTarget == "3-4 RIR")
                if CCLadderLogic.isLadderExerciseName(exercise.name) {
                    #expect(exercise.sets == 1)
                } else {
                    #expect(exercise.sets <= 2)
                }
            }
            let last = LastPerformance(sessionDate: "2026-10-13", sets: [
                WorkingSetSummary(load: 145, reps: 15, rir: 4),
                WorkingSetSummary(load: 150, reps: 9, rir: 0)
            ])
            #expect(ProgressionRule.suggestedLoad(last: last, reps: "10-15", startLoadLb: 100,
                holdLoads: adjusted.holdLoads) == 150)
        }
        let accessories = body.programV2Day(for: body.days[1], on: weekRulesDate("2026-10-20"))
        #expect(accessories.exercises.first { $0.name == "Overhead triceps extension (cable or DB)" }?.setsLabel == "1–2")
        body.reductionWeek = nil
        #expect(!body.programV2Day(for: body.days[1], on: weekRulesDate("2026-10-20")).holdLoads)
        body.reductionWeek = 3
        let reductionInstead = body.programV2Day(for: body.days[2], on: weekRulesDate("2026-10-12"))
        #expect(reductionInstead.exercises.first { $0.name == "Cable or DB curl" }?.sets == 2)
    }

    @Test func reductionRecognizesBareBridgeStepsAndAnchors() {
        var body = TrainingProgramBody.bundledV2()
        body.reductionWeek = 4
        let exercises = ["Knee tuck", "Short bridge", "Jackknife squat", "Shoulderstand squat", "Leg press", "Chest press machine", "Chest-supported row", "Cable pull-through", "Accessory"]
            .map { ProgramV2Exercise(key: $0, name: $0, sets: 3, reps: "10-15", restSeconds: 60...60,
                                    rirTarget: "", startLoadLb: 0, notes: "") }
        let day = ProgramV2Day(id: "bridge", title: "Bridge", conditioning: "", conditioningMinimum: "", exercises: exercises)
        let adjusted = ProgramWeekRules.apply(to: day, dayIndex: 1, on: weekRulesDate("2026-10-20"), body: body)
        #expect(adjusted.exercises.map(\.sets) == [1, 1, 1, 1, 2, 2, 2, 2, 2])
        #expect(adjusted.exercises.last?.setsLabel == "1–2")
    }
}

extension WorkoutDraftStoreTests {
    @Test func weekRulesSurviveDraftResumeWithoutAddingLegacyKeys() throws {
        var body = TrainingProgramBody.bundledV2()
        body.reductionWeek = 4
        let day = body.programV2Day(for: body.days[1], on: weekRulesDate("2026-10-20"))
        let draft = WorkoutDraft(day: day)
        let decoded = try JSONDecoder().decode(WorkoutDraft.self, from: JSONEncoder().encode(draft))
        #expect(decoded.programV2Day.holdLoads)
        #expect(decoded.programV2Day.weekNote == day.weekNote)
        #expect(decoded.programV2Day.exercises.map(\.setsLabel) == day.exercises.map(\.setsLabel))
        let legacy = WorkoutDraft(day: body.days[0].asProgramV2Day())
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        #expect(object["weekNote"] == nil)
        #expect(object["holdLoads"] == nil)
        let rows = try #require(object["exercises"] as? [[String: Any]])
        #expect(rows.allSatisfy { $0["setsLabel"] == nil })
    }
}
