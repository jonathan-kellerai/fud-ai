import Foundation

nonisolated struct RewardUnlock: Hashable, Sendable {
    var challengeID: UUID
    var rewardKey: String
    var title: String
}

/// Decides which rewards a progress value newly unlocks. Unlocks are permanent:
/// the caller passes every key already unlocked and never re-locks one.
nonisolated enum ChallengeRewardEvaluator {
    static func newUnlocks(
        challengeID: UUID,
        rewards: [ChallengeReward],
        progress: ChallengeProgress,
        alreadyUnlocked: Set<String>
    ) -> [RewardUnlock] {
        switch progress.status {
        case .onTrack, .behind, .complete, .failed, .ended:
            break
        case .notStarted, .noData, .invalid:
            return []
        }
        return rewards
            .filter { !alreadyUnlocked.contains($0.trigger.key) && isReached($0.trigger, progress) }
            .sorted { $0.trigger.sortRank < $1.trigger.sortRank }
            .map { RewardUnlock(challengeID: challengeID, rewardKey: $0.trigger.key, title: $0.title) }
    }

    private static func isReached(_ trigger: RewardTrigger, _ progress: ChallengeProgress) -> Bool {
        switch trigger {
        case .percent(let percent):
            // The tolerance keeps a floating-point 24.999... from missing 25.
            return progress.fraction * 100 + 1e-9 >= Double(percent)
                || (progress.status == .complete && percent <= 100)
        case .streak(let days):
            return days > 0 && progress.streak >= days
        }
    }
}
