import Foundation

/// What a challenge measures. Automatic metrics come from their owners
/// (HealthKit steps, WaterStore, FoodStore); `.custom` is logged by hand.
nonisolated enum ChallengeMetric: Codable, Hashable, Sendable {
    case steps
    case waterAppLog
    case protein
    case calories
    case custom(name: String, unit: String)

    var isAutomatic: Bool {
        if case .custom = self { return false }
        return true
    }

    var unit: String {
        switch self {
        case .steps: "steps"
        case .waterAppLog: "ml"
        case .protein: "g protein"
        case .calories: "kcal"
        case .custom(_, let unit): unit
        }
    }

    var displayName: String {
        switch self {
        case .steps: "Steps"
        case .waterAppLog: "Water"
        case .protein: "Protein"
        case .calories: "Calories"
        case .custom(let name, _): name
        }
    }
}

/// How a habit day counts as hit.
nonisolated enum HabitRule: Codable, Hashable, Sendable {
    /// The day's value is at least the threshold.
    case atLeast(Double)
    /// The day has data and its value is at most the threshold. No data is not a hit.
    case atMost(Double)
    /// The day was checked YES.
    case checkIn
}

nonisolated enum ChallengeKind: Codable, Hashable, Sendable {
    /// Reach `target` in the window.
    case total(Double)
    /// Average `target` a day over the window (missing days count as 0).
    case dailyAverage(Double)
    /// Hit the rule on `duration - grace` days.
    case dailyHabit(HabitRule)

    var isHabit: Bool {
        if case .dailyHabit = self { return true }
        return false
    }
}

nonisolated enum RewardTrigger: Codable, Hashable, Sendable {
    /// Progress reaches this percent of the goal (25, 50, 100).
    case percent(Int)
    /// The habit streak reaches this many days.
    case streak(Int)

    /// Stable key for unlock records.
    var key: String {
        switch self {
        case .percent(let value): "percent.\(value)"
        case .streak(let days): "streak.\(days)"
        }
    }

    /// Unlock order when one change crosses several thresholds.
    var sortRank: (Int, Int) {
        switch self {
        case .percent(let value): (0, value)
        case .streak(let days): (1, days)
        }
    }
}

nonisolated struct ChallengeReward: Codable, Hashable, Sendable {
    var trigger: RewardTrigger
    var title: String
}

/// What the user puts on the line, e.g. "$20 to a friend". Tracked locally only.
nonisolated struct ChallengeStake: Codable, Hashable, Sendable {
    var text: String
}

nonisolated struct ChallengeReminder: Codable, Hashable, Sendable {
    var enabled: Bool
    var hour: Int
    var minute: Int

    static let standard = ChallengeReminder(enabled: true, hour: 19, minute: 0)
}

nonisolated struct Challenge: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var kind: ChallengeKind
    var metric: ChallengeMetric
    var startDay: ChallengeDay
    var durationDays: Int
    var graceDays: Int
    var rewards: [ChallengeReward]
    var stake: ChallengeStake?
    var reminder: ChallengeReminder
    var quickAddChips: [Double]
    var createdAt: Date
    var endedEarlyAt: Date?

    /// Inclusive last day of the window.
    var endDay: ChallengeDay { startDay.adding(days: durationDays - 1) }

    func contains(_ day: ChallengeDay) -> Bool {
        day >= startDay && day <= endDay
    }
}

/// One hand-logged amount for a `.custom` metric. Amounts on the same day add up.
nonisolated struct ChallengeEntry: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var challengeID: UUID
    var day: ChallengeDay
    var value: Double
    var note: String?
    var createdAt: Date
}

/// Defaults and limits (plan defaults D64-4, -6, -8).
nonisolated enum ChallengeRules {
    static let durationRange = 7...100
    static let defaultDuration = 30
    static let maxTarget = 10_000_000.0
    static let defaultRewardPercents = [25, 50, 100]

    /// round(duration / 15), clamped to 0...duration-1 (30 days -> 2).
    static func defaultGrace(duration: Int) -> Int {
        let grace = Int((Double(duration) / 15).rounded())
        return min(max(0, grace), max(0, duration - 1))
    }

    static func isValidTarget(_ value: Double) -> Bool {
        value.isFinite && value > 0 && value <= maxTarget
    }

    static func isValid(_ challenge: Challenge) -> Bool {
        guard durationRange.contains(challenge.durationDays),
              (0..<challenge.durationDays).contains(challenge.graceDays) else {
            return false
        }
        switch challenge.kind {
        case .total(let target), .dailyAverage(let target):
            return isValidTarget(target)
        case .dailyHabit(.atLeast(let threshold)):
            return isValidTarget(threshold)
        case .dailyHabit(.atMost(let threshold)):
            return threshold.isFinite && threshold >= 0 && threshold <= maxTarget
        case .dailyHabit(.checkIn):
            return true
        }
    }

    static func defaultRewards(for kind: ChallengeKind) -> [ChallengeReward] {
        var rewards = defaultRewardPercents.map { percent in
            ChallengeReward(trigger: .percent(percent), title: percent == 100 ? "Finished" : "\(percent)% done")
        }
        if kind.isHabit {
            rewards.append(ChallengeReward(trigger: .streak(7), title: "7-day streak"))
        }
        return rewards
    }
}
