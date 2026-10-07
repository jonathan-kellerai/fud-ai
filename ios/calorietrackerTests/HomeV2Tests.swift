import Foundation
import Testing
@testable import calorietracker

struct HomeV2Tests {
    @Test func noonPaceIsAboutOneThousandPerHourWhenNoneAreDone() {
        let calendar = newYorkCalendar()
        let noon = civil(2026, 9, 27, hour: 12, calendar: calendar)
        let pace = HomeV2Logic.stepsPace(steps: 0, target: 10_000, now: noon, calendar: calendar)
        #expect(pace.met == false)
        #expect(pace.windowClosed == false)
        #expect(pace.remaining == 10_000)
        #expect(pace.perHour == 1_000)
    }

    @Test func paceStopsAtTenPM() {
        let calendar = newYorkCalendar()
        let late = civil(2026, 9, 27, hour: 22, minute: 15, calendar: calendar)
        let pace = HomeV2Logic.stepsPace(steps: 4_000, target: 10_000, now: late, calendar: calendar)
        #expect(pace.windowClosed == true)
        #expect(pace.perHour == nil)
        #expect(pace.remaining == 6_000)
        let done = HomeV2Logic.stepsPace(steps: 10_000, target: 10_000, now: late, calendar: calendar)
        #expect(done.met == true)
        #expect(done.remaining == 0)
    }

    @Test func zeroEatenRemainingIsTheTarget() {
        let remainder = HomeV2Logic.CalorieRemainder.resolve(eaten: 0, target: 2_200)
        #expect(remainder.kind == .remaining)
        #expect(remainder.amount == 2_200)
        let over = HomeV2Logic.CalorieRemainder.resolve(eaten: 2_400, target: 2_200)
        #expect(over.kind == .over)
        #expect(over.amount == 200)
    }

    @Test func sevenDayAverageAndWeeklyChange() {
        let calendar = newYorkCalendar()
        let ending = civil(2026, 9, 27, calendar: calendar)
        var samples: [HomeV2Logic.DatedValue] = []
        for offset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: -offset, to: ending)!
            samples.append(HomeV2Logic.DatedValue(date: day, value: 180))
        }
        for offset in 7..<14 {
            let day = calendar.date(byAdding: .day, value: -offset, to: ending)!
            samples.append(HomeV2Logic.DatedValue(date: day, value: 181))
        }
        let trend = HomeV2Logic.windowTrend(samples: samples, ending: ending, calendar: calendar)
        #expect(trend.current == 180)
        #expect(trend.prior == 181)
        #expect(trend.change == -1)
        #expect(HomeV2Logic.recompCaption(weightChangeLb: trend.change, leanChangeLb: 0.2) == "Lean mass is up while weight is down.")
        #expect(HomeV2Logic.recompCaption(weightChangeLb: -0.4, leanChangeLb: 0) == "Lean mass is holding while weight is down.")
        #expect(HomeV2Logic.recompCaption(weightChangeLb: nil, leanChangeLb: 1) == nil)
    }

    /// Visible iff there is local activity: an active schedule or vial, or a dose today.
    @MainActor @Test func peptideCardShowsOnlyWithLocalActivity() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        let today = "2026-09-27"
        #expect(!store.hasLocalActivity(today: today))
        var draft = PeptideLogDraft.new(compound: "BPC-157", now: try #require(PeptideMath.date(civil: today)))
        draft.drawText = "50"
        draft.drawUnit = .units
        _ = try #require(store.log(draft))
        #expect(store.hasLocalActivity(today: today))
        #expect(!store.hasLocalActivity(today: "2026-09-28"))
        store.saveSchedule(PeptideUserSchedule(id: "s", compound: "MT2", frequency: ReconMath.Frequency(type: "daily"), startDate: today, active: false))
        #expect(!store.hasLocalActivity(today: "2026-09-28"))
        store.setScheduleActive(id: "s", active: true)
        #expect(store.hasLocalActivity(today: "2026-09-28"))
    }

    @Test func storedNumbersDropTrailingZeros() {
        #expect(HomeV2Logic.storedNumber(250) == "250")
        #expect(HomeV2Logic.storedNumber(0.25) == "0.25")
    }

    @Test func weekStripStatusUsesWorkoutStepsAndFood() {
        let unknown = HomeV2Logic.weekDayStatus(workoutLogged: nil, steps: nil, stepsTarget: 10_000, foodEntries: 0)
        #expect(unknown.lifted == nil)
        #expect(unknown.stepsHit == nil)
        #expect(unknown.foodLogged == false)
        let hit = HomeV2Logic.weekDayStatus(workoutLogged: true, steps: 10_000, stepsTarget: 10_000, foodEntries: 2)
        #expect(hit.lifted == true)
        #expect(hit.stepsHit == true)
        #expect(hit.foodLogged == true)
        let short = HomeV2Logic.weekDayStatus(workoutLogged: false, steps: 9_999, stepsTarget: 10_000, foodEntries: 0)
        #expect(short.stepsHit == false)
    }

    @Test func poorSleepRuleIsShownVerbatimOnlyWhenSleepIsShort() {
        let notes = """
        Effort: 1-3 RIR.
        Poor-sleep rule: Self-reported poor night: roughly under 6 h or clearly broken sleep. Still train; Cap every set at >=3 RIR; Skip the last accessory set(s) and the CC finisher; Conditioning stays at full minutes but steady (Day3 intervals become 12 min steady); 10k steps still required (easy walking); Log sleep_bad = true (app already has this flag). Two bad nights + rising soreness: Run that day as a reduction-week day (2 sets anchors, 1-2 accessories, 3-4 RIR). Safety: If you feel unwell or unsafe to lift, skip lifting and walk. Sharp, acute, worsening or neurologic symptoms: stop and get professionally assessed (no diagnosis here).
        """
        let rule = HomeV2Logic.poorSleepRule(from: notes)
        #expect(rule?.hasPrefix("Poor-sleep rule: Self-reported poor night:") == true)
        #expect(rule?.contains("Cap every set at >=3 RIR") == true)
        #expect(HomeV2Logic.poorSleepRuleIfShort(asleepSeconds: 5 * 3600, notes: notes) == rule)
        #expect(HomeV2Logic.poorSleepRuleIfShort(asleepSeconds: 7 * 3600, notes: notes) == nil)
        #expect(HomeV2Logic.poorSleepRuleIfShort(asleepSeconds: nil, notes: notes) == nil)
    }

    @Test func reductionWeekStartsOctoberNineteenth() {
        let calendar = newYorkCalendar()
        let sunday = civil(2026, 9, 27, calendar: calendar)
        #expect(
            HomeV2Logic.reductionMilestone(
                today: sunday,
                calendar: calendar,
                programStartDate: "2026-09-28",
                reductionWeek: 4
            ) == "Deload Week Oct 19"
        )
    }

    @Test func weekSoFarCountsSessionsStepDaysAndProtein() {
        let calendar = newYorkCalendar()
        let monday = civil(2026, 9, 28, calendar: calendar)
        let snapshot = HomeV2Logic.weekSoFar(
            today: monday,
            calendar: calendar,
            trainingDaysPerWeek: 5,
            workoutCivilDates: ["2026-09-28T00:00:00.000Z"],
            stepsByCivilDate: ["2026-09-28": 10_000],
            stepsTarget: 10_000,
            proteinByCivilDate: ["2026-09-28": 150],
            programStartDate: "2026-09-28",
            reductionWeek: 4
        )
        #expect(snapshot.sessionsDone == 1)
        #expect(snapshot.sessionsScheduled == 5)
        #expect(snapshot.stepDaysHit == 1)
        #expect(snapshot.daysElapsed == 1)
        #expect(snapshot.averageProtein == 150)
        #expect(snapshot.milestone == "Deload Week Oct 19")
    }

    @Test func sessionSummaryKeepsTheHeaviestSet() {
        let summary = HomeV2Logic.sessionSummary(sets: [
            ("Leg press", 145, 12),
            ("Leg press", 155, 10),
            ("Leg curl", 70, 12),
        ])
        #expect(summary.totalSets == 3)
        #expect(summary.exercises.count == 2)
        #expect(summary.exercises[0].sets == 2)
        #expect(summary.exercises[0].topLoadLb == 155)
        #expect(summary.exercises[0].topReps == 10)
    }

    @Test func utcTimestampsDisplayInNewYork() {
        #expect(HomeV2Logic.displayNewYork(iso8601: "2026-09-27T16:45:00Z") == "Sun 12:45 PM")
        #expect(HomeV2Logic.newYorkDateString(from: civil(2026, 9, 27, hour: 21, calendar: newYorkCalendar())) == "2026-09-27")
    }

    @Test func stepsRingIsOliveAtTenThousandRustWhenLateAndBloodOtherwise() {
        let short = HomeV2Logic.StepsPace(remaining: 8_000, perHour: 1_000, met: false, windowClosed: false)
        #expect(HomeV2Logic.stepsRingTone(steps: 2_000, pace: short, hour: 12) == .blood)
        #expect(HomeV2Logic.stepsRingTone(steps: 2_000, pace: short, hour: 18) == .rust)
        let closed = HomeV2Logic.StepsPace(remaining: 6_000, perHour: nil, met: false, windowClosed: true)
        #expect(HomeV2Logic.stepsRingTone(steps: 4_000, pace: closed, hour: 12) == .rust)
        let met = HomeV2Logic.StepsPace(remaining: 0, perHour: nil, met: true, windowClosed: false)
        #expect(HomeV2Logic.stepsRingTone(steps: 10_000, pace: met, hour: 9) == .olive)
        #expect(HomeV2Logic.stepsRingTone(steps: 10_000, pace: short, hour: 12) == .olive)
    }

    @MainActor
    @Test func legacySavedLayoutGetsChallengesAppendedAtTheEnd() throws {
        let suite = "home-layout-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // A build-63 layout: no "challenges" key, peptides moved first, recovery hidden.
        let legacy = #"{"order":["peptides","weekStrip","today","dailyTargets","bodyTrend","recovery","weekSoFar"],"hidden":["recovery"]}"#
        defaults.set(Data(legacy.utf8), forKey: HomeCardLayout.storageKey)
        let layout = HomeCardLayout.load(from: defaults)
        #expect(layout.order == [.peptides, .weekStrip, .today, .dailyTargets, .bodyTrend, .recovery, .weekSoFar, .challenges])
        #expect(layout.hidden == [.recovery])
    }

    @MainActor
    @Test func challengesCardIsFilteredWhileTheFlagIsOff() {
        let order = HomeCardID.allCases
        #expect(HomeCardLayout.available(order, challengesEnabled: true).contains(.challenges))
        #expect(!HomeCardLayout.available(order, challengesEnabled: false).contains(.challenges))
        #expect(HomeCardLayout.available(order, challengesEnabled: false).count == order.count - 1)
    }

    private func newYorkCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        return calendar
    }

    private func civil(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0, calendar: Calendar) -> Date {
        var parts = DateComponents()
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts)!
    }
}
