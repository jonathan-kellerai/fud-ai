import Foundation
import Testing
@testable import calorietracker

/// Challenge maths with a fixed New York calendar. Values match plan C1a.
struct ChallengeEngineTests {
    // MARK: - Fixtures

    static func newYork() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    static func at(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, calendar: Calendar = newYork()) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    static let start = ChallengeDay(year: 2026, month: 10, day: 12)

    static func challenge(
        _ kind: ChallengeKind,
        metric: ChallengeMetric = .custom(name: "KB swings", unit: "reps"),
        duration: Int = 30,
        grace: Int? = nil,
        endedEarlyAt: Date? = nil
    ) -> Challenge {
        Challenge(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "10K KB SWINGS",
            kind: kind,
            metric: metric,
            startDay: start,
            durationDays: duration,
            graceDays: grace ?? ChallengeRules.defaultGrace(duration: duration),
            rewards: ChallengeRules.defaultRewards(for: kind),
            stake: nil,
            reminder: .standard,
            quickAddChips: [25, 50, 100],
            createdAt: at(2026, 10, 12, hour: 8),
            endedEarlyAt: endedEarlyAt
        )
    }

    /// Values for days 1...n starting at `start`.
    static func daily(_ values: [Double]) -> [ChallengeDay: Double] {
        var result: [ChallengeDay: Double] = [:]
        for (offset, value) in values.enumerated() {
            result[start.adding(days: offset)] = value
        }
        return result
    }

    static let swings: [Double] = [300, 320, 340, 330, 335, 440, 300, 330, 310, 345, 340, 210]

    private func run(
        _ challenge: Challenge,
        _ daily: [ChallengeDay: Double],
        now: Date,
        availability: ChallengeAvailability = .available,
        calendar: Calendar = ChallengeEngineTests.newYork()
    ) -> ChallengeProgress {
        ChallengeEngine.progress(challenge, daily: daily, availability: availability, now: now, calendar: calendar)
    }

    // MARK: - ChallengeDay

    @Test func dayStringRoundTripsAndParsesStrictly() {
        let day = ChallengeDay(year: 2026, month: 3, day: 7)
        #expect(day.string == "2026-03-07")
        #expect(ChallengeDay(string: "2026-03-07") == day)
        #expect(ChallengeDay(string: "2026-3-7") == nil)
        #expect(ChallengeDay(string: "2026-02-30") == nil)
        #expect(ChallengeDay(string: "2026-13-01") == nil)
        #expect(ChallengeDay(string: "abcd-ef-gh") == nil)
        #expect(ChallengeDay(string: "2026-03-07T00") == nil)
        #expect(ChallengeDay(string: "2028-02-29") != nil)
    }

    @Test func dayArithmeticCrossesMonthsYearsAndLeapDays() {
        let day = ChallengeDay(year: 2028, month: 2, day: 28)
        #expect(day.adding(days: 1) == ChallengeDay(year: 2028, month: 2, day: 29))
        #expect(day.adding(days: 2) == ChallengeDay(year: 2028, month: 3, day: 1))
        #expect(ChallengeDay(year: 2026, month: 12, day: 31).adding(days: 1) == ChallengeDay(year: 2027, month: 1, day: 1))
        #expect(ChallengeDay.days(from: ChallengeDay(year: 2026, month: 1, day: 1), to: ChallengeDay(year: 2027, month: 1, day: 1)) == 365)
        #expect(ChallengeDay.days(from: Self.start, to: Self.start.adding(days: -3)) == -3)
    }

    @Test func dayDictionaryEncodesAsAnObjectKeyedByDay() throws {
        let checkIns: [ChallengeDay: Bool] = [Self.start: true]
        let data = try JSONEncoder().encode(checkIns)
        #expect(String(decoding: data, as: UTF8.self) == #"{"2026-10-12":true}"#)
        let decoded = try JSONDecoder().decode([ChallengeDay: Bool].self, from: data)
        #expect(decoded == checkIns)
    }

    @Test func dayBucketsInTheCalendarTimeZone() {
        // 2026-10-13 02:00 UTC is still 10/12 in New York.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let instant = utc.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 2))!
        #expect(ChallengeDay(instant, calendar: Self.newYork()) == Self.start)
        #expect(ChallengeDay(instant, calendar: utc) == Self.start.adding(days: 1))
    }

    // MARK: - Total

    @Test func goldenTotalAtDayTwelve() {
        let progress = run(Self.challenge(.total(10_000)), Self.daily(Self.swings), now: Self.at(2026, 10, 23, hour: 20))
        #expect(progress.dayIndex == 12)
        #expect(progress.total == 3_900)
        #expect(progress.expectedToDate == 4_000)
        #expect(progress.delta == -100)
        #expect(progress.projected == 9_750)
        #expect(progress.requiredPerDay == 339)
        #expect(progress.status == .behind)
        #expect(progress.cumulative.count == 12)
        #expect(progress.cumulative.last == 3_900)
        #expect(progress.todayValue == 210)
    }

    @Test func averageOverNineDays() {
        let values = [9_000, 10_200, 9_800, 8_900, 10_500, 9_400, 9_900, 9_700, 10_000.0]
        #expect(values.reduce(0, +) == 87_400)
        let progress = run(Self.challenge(.dailyAverage(10_000)), Self.daily(values), now: Self.at(2026, 10, 20))
        #expect(progress.dayIndex == 9)
        #expect(Int(progress.average) == 9_711)
        #expect(progress.requiredPerDay == 10_124)
        #expect(progress.status == .behind)
    }

    @Test func dayOneAndTwoHaveNoProjectionDayThreeDoes() {
        let challenge = Self.challenge(.total(10_000))
        let one = run(challenge, Self.daily([500]), now: Self.at(2026, 10, 12))
        #expect(one.dayIndex == 1)
        #expect(one.projected == nil)
        #expect(one.status == .onTrack)
        let two = run(challenge, Self.daily([500, 100]), now: Self.at(2026, 10, 13))
        #expect(two.dayIndex == 2)
        #expect(two.projected == nil)
        let three = run(challenge, Self.daily([500, 100, 300]), now: Self.at(2026, 10, 14))
        #expect(three.projected == 9_000)
    }

    @Test func preStartIsNotStartedWithNoPace() {
        let progress = run(Self.challenge(.total(10_000)), [:], now: Self.at(2026, 10, 11, hour: 23))
        #expect(progress.status == .notStarted)
        #expect(progress.dayIndex == 0)
        #expect(progress.requiredPerDay == nil)
        #expect(progress.projected == nil)
    }

    @Test func postEndClampsAndIsFinal() {
        let progress = run(Self.challenge(.total(10_000)), Self.daily(Self.swings), now: Self.at(2026, 11, 20))
        #expect(progress.dayIndex == 30)
        #expect(progress.status == .failed)
        #expect(progress.requiredPerDay == nil)
        #expect(progress.status.isFinal)
    }

    @Test func finalDayRemainderIsDueToday() {
        var values = Array(repeating: 300.0, count: 29)
        values.append(0)
        let progress = run(Self.challenge(.total(10_000)), Self.daily(values), now: Self.at(2026, 11, 10))
        #expect(progress.dayIndex == 30)
        #expect(progress.total == 8_700)
        #expect(progress.requiredPerDay == 1_300)
    }

    @Test func overTargetCompletesEarlyAndCapsTheFraction() {
        let progress = run(Self.challenge(.total(1_000)), Self.daily([600, 700]), now: Self.at(2026, 10, 13))
        #expect(progress.status == .complete)
        #expect(progress.fraction == 1)
        #expect(progress.requiredPerDay == nil)
    }

    @Test func zeroEntriesAreBehindWithTheFullPace() {
        let progress = run(Self.challenge(.total(10_000)), [:], now: Self.at(2026, 10, 16))
        #expect(progress.dayIndex == 5)
        #expect(progress.total == 0)
        #expect(progress.status == .behind)
        #expect(progress.requiredPerDay == 400)
        #expect(progress.todayValue == nil)
    }

    @Test func endingEarlyBelowTheGoalIsEnded() {
        let ended = Self.at(2026, 10, 21, hour: 9)
        let progress = run(Self.challenge(.total(10_000), endedEarlyAt: ended), Self.daily(Self.swings), now: Self.at(2026, 10, 25))
        #expect(progress.status == .ended)
        #expect(progress.dayIndex == 10)
        #expect(progress.requiredPerDay == nil)
    }

    // MARK: - Invalid and unavailable

    @Test func invalidStoredValuesCantBeEvaluated() {
        let now = Self.at(2026, 10, 20)
        #expect(run(Self.challenge(.total(0)), [:], now: now).status == .invalid)
        #expect(run(Self.challenge(.total(-5)), [:], now: now).status == .invalid)
        #expect(run(Self.challenge(.total(.nan)), [:], now: now).status == .invalid)
        #expect(run(Self.challenge(.dailyAverage(.infinity)), [:], now: now).status == .invalid)
        #expect(run(Self.challenge(.total(10_000), duration: 6), [:], now: now).status == .invalid)
        #expect(run(Self.challenge(.total(10_000), duration: 101), [:], now: now).status == .invalid)
        #expect(run(Self.challenge(.total(10_000), grace: 30), [:], now: now).status == .invalid)
        #expect(run(Self.challenge(.dailyHabit(.atLeast(.nan))), [:], now: now).status == .invalid)
    }

    @Test func unavailableDataIsNoDataNotZero() {
        let progress = run(
            Self.challenge(.total(300_000), metric: .steps), [:],
            now: Self.at(2026, 10, 20), availability: .unavailable
        )
        #expect(progress.status == .noData)
        #expect(progress.requiredPerDay == nil)
        #expect(progress.total == 0)
        #expect(progress.dayIndex == 9)
    }

    // MARK: - Habit

    @Test func defaultGraceIsDurationOverFifteen() {
        #expect(ChallengeRules.defaultGrace(duration: 30) == 2)
        #expect(ChallengeRules.defaultGrace(duration: 7) == 0)
        #expect(ChallengeRules.defaultGrace(duration: 100) == 7)
        #expect(ChallengeRules.defaultGrace(duration: 22) == 1)
    }

    @Test func graceIsSpentThenAMissFails() {
        let habit = Self.challenge(.dailyHabit(.atLeast(3_000)), metric: .waterAppLog)
        // Days 1-2 missed (grace), days 3-5 hit, today (6) pending.
        let spent = run(habit, Self.daily([0, 1_000, 3_000, 3_200, 3_100]), now: Self.at(2026, 10, 17))
        #expect(spent.missedDays == 2)
        #expect(spent.graceLeft == 0)
        #expect(spent.status == .onTrack)
        #expect(spent.todayHit == false)
        #expect(Array(spent.dayStates.prefix(6)) == [.grace, .grace, .hit, .hit, .hit, .pending])
        #expect(spent.dayStates.count == 30)
        // Day 6 ends without a hit: the third miss makes completion impossible.
        let failed = run(habit, Self.daily([0, 1_000, 3_000, 3_200, 3_100, 0]), now: Self.at(2026, 10, 18))
        #expect(failed.missedDays == 3)
        #expect(failed.status == .failed)
    }

    @Test func habitCompletesAtDurationMinusGrace() {
        let habit = Self.challenge(.dailyHabit(.atLeast(1)))
        let values = Array(repeating: 1.0, count: 28)
        let progress = run(habit, Self.daily(values), now: Self.at(2026, 11, 8))
        #expect(progress.dayIndex == 28)
        #expect(progress.hitDays == 28)
        #expect(progress.status == .complete)
        #expect(progress.fraction == 1)
    }

    @Test func graceKeepsTheStreakAliveThenAMissResetsIt() {
        let habit = Self.challenge(.dailyHabit(.checkIn), duration: 30, grace: 1)
        // hit x3, miss (grace), hit x2 -> streak 5.
        let alive = run(habit, Self.daily([1, 1, 1, 0, 1, 1]), now: Self.at(2026, 10, 17))
        #expect(alive.streak == 5)
        // A second miss after grace is gone resets the streak.
        let reset = run(habit, Self.daily([1, 1, 1, 0, 1, 1, 0, 1]), now: Self.at(2026, 10, 19))
        #expect(reset.streak == 1)
        #expect(reset.status == .failed)
    }

    @Test func checkInNoReplacesYes() {
        let habit = Self.challenge(.dailyHabit(.checkIn))
        let yes = run(habit, Self.daily([1]), now: Self.at(2026, 10, 12))
        #expect(yes.todayHit == true)
        let corrected = run(habit, Self.daily([0]), now: Self.at(2026, 10, 12))
        #expect(corrected.todayHit == false)
        #expect(corrected.hitDays == 0)
    }

    @Test func atMostWithNoDataIsNotAHit() {
        #expect(ChallengeEngine.isHit(nil, rule: .atMost(2_000)) == false)
        #expect(ChallengeEngine.isHit(1_800, rule: .atMost(2_000)) == true)
        #expect(ChallengeEngine.isHit(2_100, rule: .atMost(2_000)) == false)
        let habit = Self.challenge(.dailyHabit(.atMost(2_000)), metric: .calories)
        let progress = run(habit, [Self.start: 1_900], now: Self.at(2026, 10, 14))
        #expect(progress.hitDays == 1)
        #expect(progress.missedDays == 1)
        #expect(progress.dayStates.prefix(3) == [.hit, .grace, .pending])
    }

    @Test func dstFallBackNeitherMergesNorSplitsDays() {
        // DST ends in New York on 2026-11-01. 10/12 -> 11/02 is day 22.
        let habit = Self.challenge(.dailyHabit(.atLeast(1)))
        let values = Array(repeating: 1.0, count: 22)
        let progress = run(habit, Self.daily(values), now: Self.at(2026, 11, 2, hour: 0))
        #expect(progress.dayIndex == 22)
        #expect(progress.hitDays == 22)
        #expect(progress.streak == 22)
        #expect(progress.dayStates.filter { $0 == .hit }.count == 22)
        #expect(progress.dayStates.count == 30)
    }

    @Test func utcCalendarIsSelfConsistent() {
        // Documented limitation: days are bucketed in the evaluating calendar's zone.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let now = Self.at(2026, 10, 23, hour: 22) // 10/24 02:00 UTC
        let progress = run(Self.challenge(.total(10_000)), Self.daily(Self.swings), now: now, calendar: utc)
        #expect(ChallengeDay(now, calendar: utc) == Self.start.adding(days: 12))
        #expect(progress.dayIndex == 13)
        #expect(progress.total == 3_900)
        #expect(progress.todayValue == nil)
    }
}
