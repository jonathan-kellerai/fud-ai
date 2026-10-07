import Foundation
import Testing
@testable import calorietracker

/// Program V2 history as Neon has it on 10/6: Day 1–4 on Mon 9/28 – Thu 10/1, Day 5 skipped.
func programCycleRealHistory() -> [CompletedProgramSession] {
    [
        CompletedProgramSession(dayIndex: 1, sessionDate: "2026-09-28"),
        CompletedProgramSession(dayIndex: 2, sessionDate: "2026-09-29"),
        CompletedProgramSession(dayIndex: 3, sessionDate: "2026-09-30"),
        CompletedProgramSession(dayIndex: 4, sessionDate: "2026-10-01"),
    ]
}

/// History that makes the cycle land on `dayIndex` on `civilDay`: Day 1 … Day
/// (dayIndex − 1) on the consecutive days before it, all in the same week.
func programCycleContext(reaching dayIndex: Int, on civilDay: String) -> TrainingDayContext {
    let calendar = ProgramWeekRules.easternCalendar
    let anchor = SessionDateFormatting.date(from: civilDay, calendar: calendar)!
    let history = (1..<max(dayIndex, 1)).map { earlier -> CompletedProgramSession in
        let date = calendar.date(byAdding: .day, value: earlier - dayIndex, to: anchor)!
        return CompletedProgramSession(
            dayIndex: earlier,
            sessionDate: SessionDateFormatting.calendarDateString(from: date, calendar: calendar)
        )
    }
    return TrainingDayContext(history: history)
}

@MainActor
struct ProgramCycleTests {
    private let body = TrainingProgramBody.bundledV2()

    private func session(_ dayIndex: Int, _ date: String, recordedAt: String? = nil) -> CompletedProgramSession {
        CompletedProgramSession(dayIndex: dayIndex, sessionDate: date, recordedAt: recordedAt)
    }

    private func remote(
        kind: String = "COMPLETED",
        programDay: String,
        title: String = "",
        sessionDate: String = "2026-10-01",
        synthetic: Bool? = nil
    ) -> RemoteWorkout {
        RemoteWorkout(
            id: UUID().uuidString,
            kind: kind,
            programVersion: "program-v2",
            programDay: programDay,
            title: title,
            units: "lb",
            sessionDate: sessionDate,
            conditioning: nil,
            notes: [],
            contentHash: nil,
            synthetic: synthetic,
            recordedAt: nil
        )
    }

    // MARK: Cycle suggestion

    @Test func lastWeekEndingOnDayFourStartsWeekTwoAtDayOne() {
        // The 10/6 case: Day 5 was skipped and does not roll over.
        #expect(ProgramCycle.suggestion(body: body, history: programCycleRealHistory(), on: "2026-10-06")
                == .day(dayIndex: 1, week: 2))
        #expect(ProgramCycle.suggestion(body: body, history: programCycleRealHistory(), on: "2026-10-05")
                == .day(dayIndex: 1, week: 2))
    }

    @Test func noHistoryStartsAtDayOne() {
        #expect(ProgramCycle.suggestion(body: body, history: [], on: "2026-09-28") == .day(dayIndex: 1, week: 1))
        #expect(ProgramCycle.suggestion(body: body, history: [], on: "2026-10-07") == .day(dayIndex: 1, week: 2))
    }

    @Test func withinAWeekTheDayAfterTheLastCompletedIsNext() {
        #expect(ProgramCycle.suggestion(body: body, history: [session(1, "2026-10-05")], on: "2026-10-06")
                == .day(dayIndex: 2, week: 2))
        // Wednesday missed: Thursday is still Day 3, not Day 4.
        let history = [session(1, "2026-10-05"), session(2, "2026-10-06")]
        #expect(ProgramCycle.suggestion(body: body, history: history, on: "2026-10-08") == .day(dayIndex: 3, week: 2))
    }

    @Test func aNewWeekAlwaysStartsAtDayOne() {
        #expect(ProgramCycle.suggestion(body: body, history: [session(2, "2026-10-02")], on: "2026-10-05")
                == .day(dayIndex: 1, week: 2))
    }

    @Test func lastDayDoneCompletesTheWeek() {
        let history = [session(4, "2026-10-01"), session(5, "2026-10-01", recordedAt: "2026-10-01T20:00:00.000Z")]
        #expect(ProgramCycle.suggestion(body: body, history: history, on: "2026-10-02") == .weekComplete(week: 1))
        #expect(ProgramCycle.suggestion(body: body, history: history, on: "2026-10-05") == .day(dayIndex: 1, week: 2))
    }

    @Test func theCycleContinuesFromTheDayActuallyDone() {
        // Day 1, then Day 3 picked from the Change sheet: next is Day 4.
        let skipAhead = [session(1, "2026-10-05"), session(3, "2026-10-06")]
        #expect(ProgramCycle.suggestion(body: body, history: skipAhead, on: "2026-10-07") == .day(dayIndex: 4, week: 2))
        // Day 3 first, then Day 1: next is Day 2.
        let backward = [session(3, "2026-10-05"), session(1, "2026-10-06")]
        #expect(ProgramCycle.suggestion(body: body, history: backward, on: "2026-10-07") == .day(dayIndex: 2, week: 2))
    }

    @Test func sameDateSessionsOrderByRecordedAtThenListPosition() {
        let byRecorded = [
            session(1, "2026-10-05", recordedAt: "2026-10-05T18:00:00.000Z"),
            session(2, "2026-10-05", recordedAt: "2026-10-05T12:00:00.000Z"),
        ]
        #expect(ProgramCycle.suggestion(body: body, history: byRecorded, on: "2026-10-06") == .day(dayIndex: 2, week: 2))
        let byPosition = [session(2, "2026-10-05"), session(1, "2026-10-05")]
        #expect(ProgramCycle.suggestion(body: body, history: byPosition, on: "2026-10-06") == .day(dayIndex: 2, week: 2))
    }

    @Test func todayAndFutureSessionsDoNotMoveTheSuggestion() {
        let history = [session(1, "2026-10-05"), session(2, "2026-10-06"), session(4, "2026-10-08")]
        #expect(ProgramCycle.suggestion(body: body, history: history, on: "2026-10-06") == .day(dayIndex: 2, week: 2))
    }

    @Test func beforeTheStartThereIsNoSuggestion() {
        #expect(ProgramCycle.suggestion(body: body, history: [], on: "2026-09-27") == nil)
    }

    @Test func reductionWeekBoundariesFollowMondayToSundayWeeks() {
        // Sun 10/18 is week 3; Mon 10/19 starts reduction week 4 at Day 1.
        #expect(ProgramCycle.suggestion(body: body, history: [session(1, "2026-10-18")], on: "2026-10-19")
                == .day(dayIndex: 1, week: 4))
        #expect(ProgramCycle.suggestion(body: body, history: [session(1, "2026-10-19")], on: "2026-10-20")
                == .day(dayIndex: 2, week: 4))
        // Sun 10/25 is still week 4; Mon 10/26 is week 5.
        #expect(ProgramCycle.suggestion(body: body, history: [session(2, "2026-10-25")], on: "2026-10-26")
                == .day(dayIndex: 1, week: 5))
    }

    @Test func historyForDaysTheProgramDoesNotHaveIsIgnored() {
        #expect(ProgramCycle.suggestion(body: body, history: [session(9, "2026-10-05")], on: "2026-10-06")
                == .day(dayIndex: 1, week: 2))
    }

    @Test func noStartDateStillCyclesWithoutAWeekNumber() {
        var undated = body
        undated.startDate = ""
        #expect(ProgramCycle.suggestion(body: undated, history: [session(1, "2026-10-05")], on: "2026-10-06")
                == .day(dayIndex: 2, week: nil))
    }

    @Test func completedOnPicksTheLatestSessionThatDay() {
        let history = [
            session(1, "2026-10-06", recordedAt: "2026-10-06T13:00:00.000Z"),
            session(3, "2026-10-06", recordedAt: "2026-10-06T14:00:00.000Z"),
            session(2, "2026-10-05"),
        ]
        #expect(ProgramCycle.completed(on: "2026-10-06", in: history)?.dayIndex == 3)
        #expect(ProgramCycle.completed(on: "2026-10-07", in: history) == nil)
    }

    // MARK: Today's resolution

    private var eastern: Calendar { ProgramWeekRules.easternCalendar }

    private func day(_ civil: String) -> Date {
        SessionDateFormatting.date(from: civil, calendar: eastern)!
    }

    private func resolution(_ civil: String, _ context: TrainingDayContext) -> TrainingDayResolution {
        TrainingProgramSchedule.resolution(body, on: day(civil), context: context, calendar: eastern)
    }

    @Test func todayIsDayOneLowerAOfWeekTwo() {
        let context = TrainingDayContext(history: programCycleRealHistory())
        let tuesday = resolution("2026-10-06", context)
        #expect(tuesday.plan == .session(dayIndex: 1, name: "Lower A", stepsTarget: 10_000))
        #expect(tuesday.reason == .cycle)
        #expect(tuesday.subtitle == "Week 2 · Day 1 · Next in cycle")
        #expect(tuesday.canChange)
        #expect(!tuesday.isChanged)
        #expect(tuesday.dayIndex == 1)
        #expect(resolution("2026-10-05", context).plan == .session(dayIndex: 1, name: "Lower A", stepsTarget: 10_000))
    }

    @Test func loggedLowerATodayNamesUpperPushWednesdayNext() throws {
        // The user logged Day 1 (bridge "1-mon") on Tue 10/6 at 07:40 ET.
        let history = programCycleRealHistory() + [session(1, "2026-10-06", recordedAt: "2026-10-06T11:40:00.000Z")]
        let context = TrainingDayContext(history: history)
        let tuesday = resolution("2026-10-06", context)
        #expect(tuesday.plan == .session(dayIndex: 1, name: "Lower A", stepsTarget: 10_000))
        #expect(tuesday.reason == .loggedToday)
        #expect(tuesday.subtitle == "Week 2 · Day 1 · Logged today")
        let next = try #require(tuesday.next)
        #expect(next.name == "Upper Push")
        #expect(next.weekday == "Wednesday")
        #expect(tuesday.nextLabel == "Next: Upper Push Wednesday")
        // Change does not re-offer Day 1 once it is logged today.
        #expect(!tuesday.canChange)

        let wednesday = resolution("2026-10-07", context)
        #expect(wednesday.plan == .session(dayIndex: 2, name: "Upper Push", stepsTarget: 10_000))
        #expect(wednesday.reason == .cycle)
        #expect(wednesday.week == 2)
        #expect(wednesday.next == nil)
        #expect(wednesday.nextLabel == nil)
    }

    @Test func startIsOfferedOnlyForASessionNotYetLoggedToday() {
        let real = programCycleRealHistory()
        let cycle = resolution("2026-10-06", TrainingDayContext(history: real))
        #expect(cycle.reason == .cycle)
        #expect(cycle.canStart)

        let changed = resolution("2026-10-06", TrainingDayContext(
            history: real, override: TodayWorkoutOverride(date: "2026-10-06", dayIndex: 3)))
        #expect(changed.reason == .changed)
        #expect(changed.canStart)

        let inProgress = resolution("2026-10-06", TrainingDayContext(
            history: real, inProgress: TrainingDayContext.Draft(dayIndex: 2, sessionDate: "2026-10-06")))
        #expect(inProgress.reason == .inProgress)
        #expect(inProgress.canStart)

        // Logged today beats the override and the draft: nothing left to start.
        let logged = resolution("2026-10-06", TrainingDayContext(
            history: real + [session(1, "2026-10-06")],
            override: TodayWorkoutOverride(date: "2026-10-06", dayIndex: 3),
            inProgress: TrainingDayContext.Draft(dayIndex: 2, sessionDate: "2026-10-06")))
        #expect(logged.reason == .loggedToday)
        #expect(logged.dayIndex == 1)
        #expect(!logged.canStart)

        let rest = resolution("2026-10-10", TrainingDayContext(history: [session(1, "2026-10-05")]))
        #expect(rest.reason == .rest)
        #expect(!rest.canStart)

        let weekComplete = resolution("2026-10-02", TrainingDayContext(
            history: [session(4, "2026-10-01"), session(5, "2026-10-01")]))
        #expect(weekComplete.reason == .weekComplete)
        #expect(!weekComplete.canStart)

        let upcoming = resolution("2026-09-27", .empty)
        #expect(upcoming.reason == .upcoming)
        #expect(!upcoming.canStart)
    }

    @Test func onlyALoggedTodayCardCarriesTheNextSession() {
        #expect(resolution("2026-10-06", TrainingDayContext(history: programCycleRealHistory())).next == nil)
        let saturday = resolution("2026-10-10", TrainingDayContext(history: [session(1, "2026-10-05")]))
        #expect(saturday.next == nil)
        #expect(saturday.plan.nextLabel == "Next: Lower A Monday")
        #expect(resolution("2026-09-27", .empty).next == nil)
    }

    @Test func aCompletedWeekRestsUntilDayOneNextMonday() {
        let context = TrainingDayContext(history: [session(4, "2026-10-01"), session(5, "2026-10-01")])
        let friday = resolution("2026-10-02", context)
        #expect(friday.plan == .rest(stepsTarget: 10_000, nextName: "Lower A", nextWeekday: "Monday"))
        #expect(friday.reason == .weekComplete)
        #expect(friday.subtitle == "Week 1 complete")
        #expect(friday.canChange)
    }

    @Test func saturdayRestNamesTheCyclesNextSession() {
        let context = TrainingDayContext(history: [session(1, "2026-10-05"), session(2, "2026-10-06")])
        let saturday = resolution("2026-10-10", context)
        #expect(saturday.plan == .rest(stepsTarget: 10_000, nextName: "Lower A", nextWeekday: "Monday"))
        #expect(saturday.reason == .rest)
        #expect(saturday.subtitle == nil)
        #expect(saturday.canChange)
        #expect(saturday.dayIndex == nil)
        // Mid-week the rest label names the cycle's day, not the weekday's.
        var wednesdayOff = body
        wednesdayOff.restWeekdays = ["wed", "sat", "sun"]
        let wednesday = TrainingProgramSchedule.resolve(wednesdayOff, on: day("2026-10-07"),
            context: TrainingDayContext(history: [session(1, "2026-10-05"), session(2, "2026-10-06")]), calendar: eastern)
        #expect(wednesday == .rest(stepsTarget: 10_000, nextName: "Pull / Hinge", nextWeekday: "Thursday"))
    }

    @Test func todaysOverrideWinsAndAStaleOneIsIgnored() {
        let changed = TrainingDayContext(
            history: programCycleRealHistory(), override: TodayWorkoutOverride(date: "2026-10-06", dayIndex: 3))
        let today = resolution("2026-10-06", changed)
        #expect(today.plan == .session(dayIndex: 3, name: "Pull / Hinge", stepsTarget: 10_000))
        #expect(today.subtitle == "Week 2 · Day 3 · Changed for today")
        #expect(today.isChanged)
        #expect(today.canChange)
        #expect(resolution("2026-10-07", changed).plan == .session(dayIndex: 1, name: "Lower A", stepsTarget: 10_000))
    }

    @Test func aSaturdayOverrideIsAMakeupSession() {
        let context = TrainingDayContext(
            history: [session(1, "2026-10-05")], override: TodayWorkoutOverride(date: "2026-10-10", dayIndex: 5))
        #expect(resolution("2026-10-10", context).plan == .session(dayIndex: 5, name: "Lower B + Cond", stepsTarget: 10_000))
    }

    @Test func aSessionLoggedTodayBeatsTheOverride() {
        let override = TodayWorkoutOverride(date: "2026-10-06", dayIndex: 3)
        let sameDay = TrainingDayContext(history: programCycleRealHistory() + [session(3, "2026-10-06")], override: override)
        let logged = resolution("2026-10-06", sameDay)
        #expect(logged.plan == .session(dayIndex: 3, name: "Pull / Hinge", stepsTarget: 10_000))
        #expect(logged.reason == .loggedToday)
        #expect(logged.subtitle == "Week 2 · Day 3 · Logged today")
        #expect(!logged.canChange)
        let otherDay = TrainingDayContext(history: programCycleRealHistory() + [session(1, "2026-10-06")], override: override)
        #expect(resolution("2026-10-06", otherDay).plan == .session(dayIndex: 1, name: "Lower A", stepsTarget: 10_000))
        #expect(resolution("2026-10-06", otherDay).reason == .loggedToday)
    }

    @Test func aDraftStartedTodayResumesAndYesterdaysDoesNot() {
        let today = TrainingDayContext(
            history: programCycleRealHistory(), inProgress: TrainingDayContext.Draft(dayIndex: 2, sessionDate: "2026-10-06"))
        let resumed = resolution("2026-10-06", today)
        #expect(resumed.plan == .session(dayIndex: 2, name: "Upper Push", stepsTarget: 10_000))
        #expect(resumed.subtitle == "Week 2 · Day 2 · In progress")
        let yesterday = TrainingDayContext(
            history: programCycleRealHistory(), inProgress: TrainingDayContext.Draft(dayIndex: 2, sessionDate: "2026-10-05"))
        #expect(resolution("2026-10-06", yesterday).plan == .session(dayIndex: 1, name: "Lower A", stepsTarget: 10_000))
        var overridden = today
        overridden.override = TodayWorkoutOverride(date: "2026-10-06", dayIndex: 4)
        #expect(resolution("2026-10-06", overridden).reason == .changed)
    }

    @Test func afterAnOverriddenDayThreeTomorrowIsDayFour() {
        let context = TrainingDayContext(history: programCycleRealHistory() + [session(3, "2026-10-06")])
        #expect(resolution("2026-10-07", context).plan == .session(dayIndex: 4, name: "Upper Physique", stepsTarget: 10_000))
    }

    @Test func reductionWeekDayTwoKeepsTheReductionPrescription() throws {
        let context = TrainingDayContext(history: [session(1, "2026-10-19")])
        let tuesday = resolution("2026-10-20", context)
        #expect(tuesday.plan == .session(dayIndex: 2, name: "Upper Push", stepsTarget: 10_000))
        #expect(tuesday.subtitle == "Week 4 · Day 2 · Next in cycle")
        let selected = try #require(TrainingProgramSchedule.programDay(in: body, matching: tuesday.plan))
        let dated = body.programV2Day(for: selected, on: day("2026-10-20"))
        #expect(dated.holdLoads)
        #expect(dated.weekNote?.hasPrefix("Reduction week") == true)
    }

    @Test func beforeTheStartDayOneIsUpcoming() {
        let sunday = resolution("2026-09-27", .empty)
        #expect(sunday.plan == .upcoming(name: "Lower A", weekday: "Monday", stepsTarget: 10_000))
        #expect(!sunday.canChange)
        #expect(sunday.subtitle == nil)
    }

    @Test func workoutOptionsListEveryDayDatedForTheWeek() {
        let options = TrainingProgramSchedule.workoutOptions(body, on: day("2026-10-06"))
        #expect(options.map(\.dayIndex) == [1, 2, 3, 4, 5])
        #expect(options.map(\.name) == ["Lower A", "Upper Push", "Pull / Hinge", "Upper Physique", "Lower B + Cond"])
        #expect(options.map(\.exerciseCount) == body.days.map(\.exercises.count))
        #expect(options[0].title == "Day 1 · Lower A")
        #expect(options[0].detail == "\(body.days[0].exercises.count) exercises · \(body.days[0].conditioningSummary)")
        #expect(options[2].accessibilityLabel(suggested: true, selected: false)
                == "Day 3, Pull / Hinge, \(body.days[2].exercises.count) exercises, conditioning \(body.days[2].conditioningSummary), suggested")
        var reduction = body
        reduction.reductionWeek = 4
        let reduced = TrainingProgramSchedule.workoutOptions(reduction, on: day("2026-10-21"))
        #expect(reduced[2].conditioning == "12 min bike steady, RPE 5-6/10")
    }

    @Test func suggestedDayIgnoresTheOverride() {
        let changed = TrainingDayContext(
            history: programCycleRealHistory(), override: TodayWorkoutOverride(date: "2026-10-06", dayIndex: 3))
        #expect(TrainingProgramSchedule.suggestedDayIndex(body, on: day("2026-10-06"), context: changed, calendar: eastern) == 1)
        let saturday = TrainingDayContext(history: [session(1, "2026-10-05"), session(2, "2026-10-06")])
        #expect(TrainingProgramSchedule.suggestedDayIndex(body, on: day("2026-10-10"), context: saturday, calendar: eastern) == 1)
        #expect(TrainingProgramSchedule.suggestedDayIndex(body, on: day("2026-09-27"), context: .empty, calendar: eastern) == nil)
    }

    @Test func pickingTodaysCycleDayClearsTheOverride() {
        let context = TrainingDayContext(
            history: programCycleRealHistory(), override: TodayWorkoutOverride(date: "2026-10-06", dayIndex: 3))
        #expect(TrainingProgramSchedule.overrideAfterPicking(1, in: body, on: day("2026-10-06"),
            context: context, calendar: eastern) == nil)
        #expect(TrainingProgramSchedule.overrideAfterPicking(4, in: body, on: day("2026-10-06"),
            context: context, calendar: eastern) == TodayWorkoutOverride(date: "2026-10-06", dayIndex: 4))
        // On a rest day every pick is a makeup session, even the suggested one.
        #expect(TrainingProgramSchedule.overrideAfterPicking(1, in: body, on: day("2026-10-10"),
            context: .empty, calendar: eastern) == TodayWorkoutOverride(date: "2026-10-10", dayIndex: 1))
    }

    // MARK: History parsing

    @Test func parsesIOSAndPWAProgramDays() {
        #expect(CompletedProgramSession.dayIndex(programDay: "4-thu", title: "", days: body.days) == 4)
        #expect(CompletedProgramSession.dayIndex(programDay: "Day4_UpperPhysique", title: "", days: body.days) == 4)
        #expect(CompletedProgramSession.dayIndex(programDay: "Day 2", title: "", days: body.days) == 2)
        #expect(CompletedProgramSession.dayIndex(programDay: "custom", title: "Pull / Hinge", days: body.days) == 3)
        #expect(CompletedProgramSession.dayIndex(programDay: "garbage", title: "Nope", days: body.days) == nil)
        #expect(CompletedProgramSession.dayIndex(programDay: "9-sat", title: "", days: body.days) == nil)
        #expect(CompletedProgramSession.dayIndex(programDay: "4thu", title: "", days: body.days) == nil)
    }

    @Test func onlyRealCompletedRowsBecomeHistory() {
        let real = CompletedProgramSession(
            remote: remote(programDay: "4-thu", sessionDate: "2026-10-01T00:00:00.000Z"), days: body.days)
        #expect(real == CompletedProgramSession(dayIndex: 4, sessionDate: "2026-10-01"))
        #expect(CompletedProgramSession(remote: remote(programDay: "Day4_UpperPhysique"), days: body.days)?.dayIndex == 4)
        #expect(CompletedProgramSession(remote: remote(programDay: "x", title: "Lower A"), days: body.days)?.dayIndex == 1)
        #expect(CompletedProgramSession(remote: remote(kind: "strength", programDay: "1-mon"), days: body.days) == nil)
        #expect(CompletedProgramSession(remote: remote(programDay: "1-mon", synthetic: true), days: body.days) == nil)
        #expect(CompletedProgramSession(remote: remote(programDay: "1-mon", sessionDate: "soon"), days: body.days) == nil)
        #expect(CompletedProgramSession(remote: remote(programDay: "garbage"), days: body.days) == nil)
    }
}
