import Foundation
import Testing
@testable import calorietracker

struct ChallengeReminderPlannerTests {
    private typealias F = ChallengeEngineTests

    private func item(
        _ kind: ChallengeKind,
        _ values: [Double],
        now: Date,
        id: UUID = UUID(),
        availability: ChallengeAvailability = .available
    ) -> (challenge: Challenge, progress: ChallengeProgress) {
        var challenge = F.challenge(kind)
        challenge.id = id
        let progress = ChallengeEngine.progress(
            challenge, daily: F.daily(values), availability: availability, now: now, calendar: F.newYork()
        )
        return (challenge, progress)
    }

    private func plan(_ items: [(challenge: Challenge, progress: ChallengeProgress)], now: Date) -> [PlannedNotification] {
        ChallengeReminderPlanner.plan(items, now: now, calendar: F.newYork())
    }

    @Test func behindTotalGetsOneNudgeAtSevenPM() {
        let now = F.at(2026, 10, 23, hour: 9)
        let id = UUID()
        let planned = plan([item(.total(10_000), F.swings, now: now, id: id)], now: now)
        #expect(planned.count == 1)
        #expect(planned.first?.id == "challenge.\(id.uuidString).nudge")
        #expect(planned.first?.fireDate == F.at(2026, 10, 23, hour: 19))
        #expect(planned.first?.body.contains("339") == true)
    }

    @Test func checkInHabitGetsACheckInReminder() {
        let now = F.at(2026, 10, 13, hour: 9)
        let id = UUID()
        let planned = plan([item(.dailyHabit(.checkIn), [1], now: now, id: id)], now: now)
        #expect(planned.map(\.id) == ["challenge.\(id.uuidString).checkin"])
    }

    @Test func noneOnAHitDayOrOnTrack() {
        let now = F.at(2026, 10, 13, hour: 9)
        #expect(plan([item(.dailyHabit(.checkIn), [1, 1], now: now)], now: now).isEmpty)
        #expect(plan([item(.total(10_000), [2_000, 2_000], now: now)], now: now).isEmpty)
    }

    @Test func noneBeforeTheStartAfterTheEndOrWithoutData() {
        let before = F.at(2026, 10, 10, hour: 9)
        #expect(plan([item(.total(10_000), [], now: before)], now: before).isEmpty)
        let after = F.at(2026, 11, 20, hour: 9)
        #expect(plan([item(.total(10_000), F.swings, now: after)], now: after).isEmpty)
        let now = F.at(2026, 10, 23, hour: 9)
        #expect(plan([item(.total(10_000), F.swings, now: now, availability: .unavailable)], now: now).isEmpty)
    }

    @Test func noneOnceTheFireTimeHasPassed() {
        let late = F.at(2026, 10, 23, hour: 20)
        #expect(plan([item(.total(10_000), F.swings, now: late)], now: late).isEmpty)
    }

    @Test func noneWhenTheReminderIsOff() {
        let now = F.at(2026, 10, 23, hour: 9)
        var behind = item(.total(10_000), F.swings, now: now)
        behind.challenge.reminder.enabled = false
        #expect(plan([behind], now: now).isEmpty)
    }

    @Test func capsAtTwentyMostBehindFirst() {
        let now = F.at(2026, 10, 23, hour: 9)
        var items: [(challenge: Challenge, progress: ChallengeProgress)] = []
        for index in 0..<25 {
            // Higher index = less logged = further behind.
            let values = F.swings.map { max(0, $0 - Double(index * 10)) }
            items.append(item(.total(10_000), values, now: now))
        }
        let planned = plan(items, now: now)
        #expect(planned.count == ChallengeReminderPlanner.maxTotal)
        let mostBehind = "challenge.\(items[24].challenge.id.uuidString).nudge"
        #expect(planned.first?.id == mostBehind)
        let leastBehind = "challenge.\(items[0].challenge.id.uuidString).nudge"
        #expect(!planned.map(\.id).contains(leastBehind))
        // At most two per challenge.
        let perChallenge = Dictionary(grouping: planned, by: { $0.id.split(separator: ".")[1] })
        #expect(perChallenge.values.allSatisfy { $0.count <= ChallengeReminderPlanner.maxPerChallenge })
    }

    @Test func replanningIsIdentical() {
        let now = F.at(2026, 10, 23, hour: 9)
        let items = [
            item(.total(10_000), F.swings, now: now),
            item(.dailyHabit(.checkIn), Array(repeating: 1, count: 11), now: now),
        ]
        #expect(plan(items, now: now) == plan(items, now: now))
        #expect(plan(items, now: now).count == 2)
    }
}
