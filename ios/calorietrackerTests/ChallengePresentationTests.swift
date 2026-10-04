import Foundation
import Testing
@testable import calorietracker

struct ChallengePresentationTests {
    private typealias F = ChallengeEngineTests
    private let us = Locale(identifier: "en_US")

    private func golden() -> (Challenge, ChallengeProgress) {
        let challenge = F.challenge(.total(10_000))
        let progress = ChallengeEngine.progress(
            challenge, daily: F.daily(F.swings), availability: .available,
            now: F.at(2026, 10, 23, hour: 20), calendar: F.newYork()
        )
        return (challenge, progress)
    }

    @Test func amountsGroupAndWaterShowsLitres() {
        #expect(ChallengePresentation.amount(10_000, metric: .steps, locale: us) == "10,000")
        #expect(ChallengePresentation.amount(3_000, metric: .waterAppLog, locale: us) == "3.0 L")
        #expect(ChallengePresentation.signedAmount(-100, metric: .steps, locale: us) == "\u{2212}100")
        #expect(ChallengePresentation.signedAmount(250, metric: .steps, locale: us) == "+250")
        #expect(ChallengePresentation.percent(0.39) == "39%")
        #expect(ChallengePresentation.percent(1.4) == "100%")
    }

    @Test func goldenTilesMatchTheEngine() {
        let (challenge, progress) = golden()
        let tiles = ChallengePresentation.tiles(challenge, progress, locale: us)
        #expect(tiles.map(\.label) == ["Total", "Expected", "Pace", "Projected", "Need / day"])
        #expect(tiles.map(\.value) == ["3,900", "4,000", "\u{2212}100", "9,750", "339"])
        #expect(tiles.last?.detail == "18 days left")
    }

    @Test func noTilesWithoutData() {
        let challenge = F.challenge(.total(300_000), metric: .steps)
        let progress = ChallengeEngine.progress(
            challenge, daily: [:], availability: .unavailable, now: F.at(2026, 10, 20), calendar: F.newYork()
        )
        #expect(ChallengePresentation.tiles(challenge, progress).isEmpty)
        #expect(ChallengePresentation.statusLabel(progress.status, metric: .steps) == "No step data")
    }

    @Test func habitTilesAndGridSummary() {
        let challenge = F.challenge(.dailyHabit(.atLeast(3_000)), metric: .waterAppLog)
        let progress = ChallengeEngine.progress(
            challenge, daily: F.daily([3_000, 0, 3_100]), availability: .available,
            now: F.at(2026, 10, 15), calendar: F.newYork()
        )
        let tiles = ChallengePresentation.tiles(challenge, progress, locale: us)
        #expect(tiles.map(\.value) == ["2 / 28", "1", "2", "Not yet"])
        #expect(ChallengePresentation.gridSummary(progress) == "2 days hit, 1 missed, 1 grace left.")
    }

    @Test func goalSummaryAndDayLabel() {
        let (challenge, progress) = golden()
        #expect(ChallengePresentation.goalSummary(challenge, locale: us) == "10,000 reps in 30 days")
        let habit = F.challenge(.dailyHabit(.checkIn))
        #expect(ChallengePresentation.goalSummary(habit, locale: us) == "Check in daily, 28 of 30 days")
        #expect(ChallengePresentation.dayLabel(progress, challenge: challenge, now: F.at(2026, 10, 23), calendar: F.newYork())
            == "Day 12 / 30")
        let early = ChallengeEngine.progress(challenge, daily: [:], availability: .available, now: F.at(2026, 10, 9), calendar: F.newYork())
        #expect(ChallengePresentation.dayLabel(early, challenge: challenge, now: F.at(2026, 10, 9), calendar: F.newYork())
            == "Starts in 3 days")
    }

    @Test func paceSeriesIsTheShareOfTheGoal() {
        let (_, progress) = golden()
        let series = ChallengePresentation.paceSeries(progress)
        #expect(series.count == 12)
        #expect(series.first == 0.03)
        #expect(abs((series.last ?? 0) - 0.39) < 1e-9)
    }

    @Test func draftBuildsAValidChallengeOrNothing() {
        let now = F.at(2026, 10, 12, hour: 8)
        var draft = ChallengeDraft()
        #expect(draft.build(now: now, calendar: F.newYork()) == nil)
        draft.title = "10k kb swings"
        draft.customName = "KB swings"
        draft.targetText = "10,000"
        let built = draft.build(now: now, calendar: F.newYork())
        #expect(built?.title == "10K KB SWINGS")
        #expect(built?.kind == .total(10_000))
        #expect(built?.startDay == F.start)
        #expect(built?.graceDays == 0)
        #expect(built?.quickAddChips == [75, 150, 300])
        draft.targetText = "nan"
        #expect(draft.build(now: now, calendar: F.newYork()) == nil)
        draft.targetText = "0"
        #expect(draft.build(now: now, calendar: F.newYork()) == nil)
    }

    @Test func draftWaterIsTypedInLitresAndHabitsKeepGrace() {
        var draft = ChallengeDraft()
        draft.title = "Water 3 L"
        draft.kind = .dailyHabit
        draft.metric = .water
        draft.targetText = "3"
        let built = draft.build(now: F.at(2026, 10, 12), calendar: F.newYork())
        #expect(built?.kind == .dailyHabit(.atLeast(3_000)))
        #expect(built?.metric == .waterAppLog)
        #expect(built?.graceDays == 2)
        #expect(built?.quickAddChips == [])
        draft.setDuration(7)
        #expect(draft.graceDays == 0)
        draft.setDuration(500)
        #expect(draft.durationDays == 100)
        #expect(draft.graceDays == 7)
    }

    @Test func logsAreAcceptedInsideTheOpenWindowOnly() {
        let challenge = F.challenge(.total(10_000))
        #expect(ChallengePresentation.acceptsLogs(challenge, status: .complete, today: F.start.adding(days: 20)))
        #expect(ChallengePresentation.acceptsLogs(challenge, status: .behind, today: F.start))
        #expect(!ChallengePresentation.acceptsLogs(challenge, status: .behind, today: F.start.adding(days: 30)))
        #expect(!ChallengePresentation.acceptsLogs(challenge, status: .notStarted, today: F.start.adding(days: -1)))
        #expect(!ChallengePresentation.acceptsLogs(challenge, status: .failed, today: F.start.adding(days: 5)))
        let steps = F.challenge(.total(300_000), metric: .steps)
        #expect(!ChallengePresentation.acceptsLogs(steps, status: .behind, today: F.start))
        let checkIn = F.challenge(.dailyHabit(.checkIn), metric: .steps)
        #expect(ChallengePresentation.acceptsLogs(checkIn, status: .onTrack, today: F.start))
        let ended = F.challenge(.total(10_000), endedEarlyAt: F.at(2026, 10, 14))
        #expect(!ChallengePresentation.acceptsLogs(ended, status: .ended, today: F.start.adding(days: 2)))
    }

    @Test func checkInDraftNeedsNoTarget() {
        var draft = ChallengeDraft()
        draft.title = "No alcohol"
        draft.kind = .dailyHabit
        draft.habit = .checkIn
        #expect(draft.needsTarget == false)
        #expect(draft.build(now: F.at(2026, 10, 12), calendar: F.newYork())?.kind == .dailyHabit(.checkIn))
    }
}
