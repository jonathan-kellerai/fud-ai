import Foundation
import Testing
@testable import calorietracker

struct ChallengeRewardEvaluatorTests {
    private typealias F = ChallengeEngineTests

    private func progress(_ values: [Double], kind: ChallengeKind = .total(10_000), now: Date = F.at(2026, 10, 23)) -> ChallengeProgress {
        ChallengeEngine.progress(F.challenge(kind), daily: F.daily(values), availability: .available, now: now, calendar: F.newYork())
    }

    private func unlocks(_ progress: ChallengeProgress, kind: ChallengeKind = .total(10_000), already: Set<String> = []) -> [String] {
        let challenge = F.challenge(kind)
        return ChallengeRewardEvaluator.newUnlocks(
            challengeID: challenge.id,
            rewards: challenge.rewards,
            progress: progress,
            alreadyUnlocked: already
        ).map(\.rewardKey)
    }

    @Test func unlocksOnceAtTheCrossing() {
        #expect(unlocks(progress([2_499])).isEmpty)
        #expect(unlocks(progress([2_500])) == ["percent.25"])
        #expect(unlocks(progress([2_600]), already: ["percent.25"]).isEmpty)
    }

    @Test func aDownwardEditDoesNotRelock() {
        // The evaluator never returns removals; the caller keeps what it stored.
        #expect(unlocks(progress([1_000]), already: ["percent.25"]).isEmpty)
    }

    @Test func oneEntryCrossingTwoThresholdsUnlocksInOrder() {
        #expect(unlocks(progress([5_200])) == ["percent.25", "percent.50"])
        #expect(unlocks(progress([10_000])) == ["percent.25", "percent.50", "percent.100"])
    }

    @Test func streakRewardUnlocksAtItsLength() {
        let habit = ChallengeKind.dailyHabit(.atLeast(1))
        let six = progress(Array(repeating: 1, count: 6), kind: habit, now: F.at(2026, 10, 17))
        #expect(!unlocks(six, kind: habit).contains("streak.7"))
        let seven = progress(Array(repeating: 1, count: 7), kind: habit, now: F.at(2026, 10, 18))
        #expect(unlocks(seven, kind: habit, already: ["percent.25"]) == ["streak.7"])
    }

    @Test func nothingUnlocksWithoutData() {
        let challenge = F.challenge(.total(10_000))
        let noData = ChallengeEngine.progress(
            challenge, daily: F.daily([9_000]), availability: .unavailable, now: F.at(2026, 10, 20), calendar: F.newYork()
        )
        #expect(unlocks(noData).isEmpty)
        let early = ChallengeEngine.progress(
            challenge, daily: [:], availability: .available, now: F.at(2026, 10, 1), calendar: F.newYork()
        )
        #expect(unlocks(early).isEmpty)
    }
}
