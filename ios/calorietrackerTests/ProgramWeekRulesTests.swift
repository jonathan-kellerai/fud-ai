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

    @Test func bundledProgramReducesWeekFourOnly() {
        let body = TrainingProgramBody.bundledV2()
        #expect(body.reductionWeek == 4)
        for day in body.days {
            let baseSets = day.exercises.sorted { $0.order < $1.order }.map(\.sets)
            for date in ["2026-10-19", "2026-10-22", "2026-10-25"] {
                let reduced = body.programV2Day(for: day, on: weekRulesDate(date))
                #expect(reduced.holdLoads)
                #expect(reduced.weekNote?.hasPrefix("Reduction week:") == true)
                for (base, exercise) in zip(baseSets, reduced.exercises.map(\.sets)) {
                    #expect(exercise <= min(base, 2))
                }
                #expect(reduced.exercises.map(\.sets).reduce(0, +) < baseSets.reduce(0, +))
            }
            let after = body.programV2Day(for: day, on: weekRulesDate("2026-10-26"))
            #expect(!after.holdLoads)
            #expect(after.weekNote == nil)
            #expect(after.exercises.map(\.sets) == baseSets)
            // Week 3 may add an approved arm set, but never reduces or holds loads.
            let before = body.programV2Day(for: day, on: weekRulesDate("2026-10-16"))
            #expect(!before.holdLoads)
            #expect(before.weekNote?.hasPrefix("Reduction week:") != true)
            for (base, exercise) in zip(baseSets, before.exercises.map(\.sets)) {
                #expect(exercise >= base)
            }
        }
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
    @Test func matchingStartAndCoachResumeKeepTheOriginalWeekSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var body = weekRulesV4Body()
        body.reductionWeek = 4
        let selected = body.days[1]
        let startedAt = weekRulesDate("2026-10-13")
        let resumedAt = weekRulesDate("2026-10-20")
        let originalDay = body.programV2Day(for: selected, on: startedAt)
        let currentDay = body.programV2Day(for: selected, on: resumedAt)
        #expect(currentDay.holdLoads)
        let store = WorkoutDraftStore(directory: directory)
        store.update(originalDay, startedAt: startedAt) { draft in
            draft.sets["Chest press machine"] = [LoggedSet(weight: 125, reps: 12, rir: nil, rpeText: "")]
        }
        let reopened = WorkoutDraftStore(directory: directory)
        let before = try #require(reopened.draft)
        // Home Start and Train Start share this resolver; Coach also resolves through it.
        let startDay = reopened.dayToOpen(selected, in: body, on: resumedAt)
        #expect(WorkoutDraft(day: startDay, now: startedAt) == WorkoutDraft(day: originalDay, now: startedAt))
        #expect(!startDay.holdLoads)
        #expect(startDay.exercises.first { $0.name == "Overhead triceps extension (cable or DB)" }?.sets == 3)
        guard case .openToday(let coachDay) = WorkoutHandoffDecision.decide(draft: before, today: currentDay)
        else { Issue.record("Matching Coach handoff must open the saved draft"); return }
        #expect(WorkoutDraft(day: coachDay, now: startedAt) == WorkoutDraft(day: originalDay, now: startedAt))
        reopened.update(startDay, startedAt: resumedAt) { $0.conditioningCompleted = true }
        let after = try #require(WorkoutDraftStore(directory: directory).draft)
        #expect(after.sessionDate == before.sessionDate)
        #expect(after.startedAt == startedAt)
        #expect(after.exercises == before.exercises)
        #expect(after.weekNote == before.weekNote)
        #expect(after.holdLoads == before.holdLoads)
        #expect(after.sets == before.sets)
        #expect(after.payload().sets == before.payload().sets)
        // A different day and an empty store still use today's dated prescription.
        let newDay = reopened.dayToOpen(body.days[2], in: body, on: resumedAt)
        #expect(newDay.holdLoads)
        guard case .offerResume(let offered, let today) = WorkoutHandoffDecision.decide(draft: before, today: newDay)
        else { Issue.record("A different-day draft must still be offered for resume"); return }
        #expect(offered == before)
        #expect(today.holdLoads)
        let empty = WorkoutDraftStore(directory: directory.appendingPathComponent("empty"))
        #expect(empty.dayToOpen(selected, in: body, on: resumedAt).holdLoads)
    }

    @Test func reductionDayThreeDisplaysAndSavesTwelveMinutesSteady() throws {
        var body = weekRulesV4Body()
        body.reductionWeek = 4
        let date = weekRulesDate("2026-10-21")
        let schedule = TrainingProgramSchedule.resolve(body, on: date, calendar: ProgramWeekRules.easternCalendar)
        let selected = try #require(TrainingProgramSchedule.programDay(in: body, matching: schedule))
        #expect(selected.dayIndex == 3)
        let day = body.programV2Day(for: selected, on: date)
        #expect(day.conditioning == "12 min bike steady, RPE 5-6/10")
        #expect(day.conditioningMinimum == "12 min steady")
        #expect(!day.conditioning.lowercased().contains("interval"))
        #expect(!day.conditioningMinimum.lowercased().contains("round"))
        // The template's separate minimum must also lose its interval prescription.
        let template = ProgramWeekRules.apply(to: ProgramV2Templates.day3PullHinge,
            dayIndex: 3, on: date, body: body)
        #expect(template.conditioningMinimum == day.conditioningMinimum)
        var draft = WorkoutDraft(day: day, now: date)
        #expect(draft.payload().conditioning == nil)
        draft.conditioningCompleted = true
        let restored = try JSONDecoder().decode(WorkoutDraft.self, from: JSONEncoder().encode(draft))
        #expect(restored.programV2Day.conditioning == day.conditioning)
        #expect(restored.payload().conditioning == day.conditioning)
        for normalDate in ["2026-10-14", "2026-10-28"] {
            #expect(body.programV2Day(for: selected, on: weekRulesDate(normalDate)).conditioning
                    == selected.conditioningSummary)
        }
    }

    @Test func datedArmGhostsLogAndResumeWithAdjustedCounts() throws {
        var body = weekRulesV4Body()
        body.reductionWeek = 4
        for (dayIndex, date, name, count) in [
            (2, "2026-10-13", "Overhead triceps extension (cable or DB)", 3),
            (3, "2026-10-14", "Cable or DB curl", 4),
        ] {
            let startedAt = weekRulesDate(date)
            let day = body.programV2Day(for: body.days[dayIndex - 1], on: startedAt)
            let exercise = try #require(day.exercises.first { $0.name == name })
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("dated-arm-entry-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = WorkoutDraftStore(directory: directory)
            let entry = WorkoutSetEntry(day: day)
            // Real bridge history supplies a load even for Select-load curls.
            entry.lastPerformances[LastPerformanceBuilder.key(for: name)] =
                LastPerformance(sessionDate: "2026-10-07", sets: [WorkingSetSummary(load: 25, reps: 12, rir: 2)])
            #expect(SetEntryLogic.plannedRowCount(exercise: exercise, sets: []) == count)
            #expect(store.draft == nil)
            for index in 0..<count {
                #expect(entry.log(exercise, at: index, in: store, startedAt: startedAt) == index)
            }
            let restored = try #require(WorkoutDraftStore(directory: directory).draft)
            #expect(restored.sets[name]?.count == count)
            #expect(restored.programV2Day.exercises.first { $0.name == name }?.sets == count)
            #expect(restored.programV2Day.weekNote == day.weekNote)
            #expect(SetEntryLogic.plannedRowCount(exercise: exercise, sets: restored.sets[name] ?? []) == count)
        }
    }

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

extension WorkoutLoggerLogicTests {
    @Test func calendarSelectedDaysApplyWeekRulesOnTheirActualSessionDates() throws {
        var body = weekRulesV4Body()
        body.reductionWeek = 4
        let cases: [(String, Int, String, Int)] = [
            ("2026-10-13", 2, "Overhead triceps extension (cable or DB)", 3),
            ("2026-10-14", 3, "Cable or DB curl", 4),
            ("2026-10-20", 2, "Overhead triceps extension (cable or DB)", 2),
            ("2026-10-21", 3, "Cable or DB curl", 2),
            ("2026-10-27", 2, "Overhead triceps extension (cable or DB)", 2),
            ("2026-10-28", 3, "Cable or DB curl", 3),
        ]
        for (civilDate, dayIndex, name, count) in cases {
            let date = weekRulesDate(civilDate)
            let resolved = TrainingProgramSchedule.resolve(body, on: date,
                calendar: ProgramWeekRules.easternCalendar)
            let selected = try #require(TrainingProgramSchedule.programDay(in: body, matching: resolved))
            #expect(selected.dayIndex == dayIndex)
            let loggerDay = body.programV2Day(for: selected, on: date)
            let exercise = try #require(loggerDay.exercises.first { $0.name == name })
            #expect(exercise.sets == count)
            #expect(SetEntryLogic.plannedRowCount(exercise: exercise, sets: []) == count)
            let isReduction = civilDate == "2026-10-20" || civilDate == "2026-10-21"
            #expect(loggerDay.holdLoads == isReduction)
            if civilDate == "2026-10-13" || civilDate == "2026-10-14" {
                #expect(loggerDay.weekNote?.hasPrefix("Week 3:") == true)
            } else if civilDate == "2026-10-27" || civilDate == "2026-10-28" {
                #expect(loggerDay.weekNote == nil)
            }
        }
    }
}
