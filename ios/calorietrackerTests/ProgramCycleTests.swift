import Foundation
import Testing
@testable import calorietracker

/// Program V2 history as Neon has it on 10/6: Day 1–4 on Mon 9/28 – Thu 10/1, Day 5 skipped.
@MainActor
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
@MainActor
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
        // Jonathan's 10/6 case: Day 5 was skipped and does not roll over.
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
