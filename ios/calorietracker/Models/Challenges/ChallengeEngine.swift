import Foundation

/// Whether the metric's source could be read. Unavailable data is never scored as 0.
nonisolated enum ChallengeAvailability: Hashable, Sendable {
    case available
    case unavailable
}

nonisolated enum ChallengeStatus: Hashable, Sendable {
    case notStarted
    case onTrack
    case behind
    case complete
    case failed
    /// Ended early without reaching the goal.
    case ended
    /// The source couldn't be read ("No step data"); nothing is scored.
    case noData
    /// Stored values the engine can't evaluate ("Can't evaluate").
    case invalid

    var isActive: Bool { self == .onTrack || self == .behind }
    var isFinal: Bool { self == .complete || self == .failed || self == .ended }
}

/// One cell of the habit grid.
nonisolated enum ChallengeDayState: Hashable, Sendable {
    case hit
    case miss
    /// A miss covered by a grace day.
    case grace
    /// Today, not hit yet (provisional, never a miss).
    case pending
    case future
}

/// Everything a Challenges screen shows. Views only display these values.
nonisolated struct ChallengeProgress: Hashable, Sendable {
    var status: ChallengeStatus
    /// 1-based day of the window; 0 before the start; clamped to the last evaluated day after the end.
    var dayIndex: Int
    var durationDays: Int

    // Total and daily average.
    /// Sum of the window's values through the last evaluated day.
    var total: Double = 0
    /// Goal for the whole window (target, or target x duration for an average).
    var goalTotal: Double = 0
    var expectedToDate: Double = 0
    var delta: Double = 0
    /// Calendar average so far (missing days count as 0).
    var average: Double = 0
    /// Run-rate projection for the window, shown from day 3.
    var projected: Double?
    /// Rounded up; nil once the goal is met or the challenge is over.
    var requiredPerDay: Double?
    /// Cumulative total at the end of each evaluated day (for the pace chart).
    var cumulative: [Double] = []

    // Habit.
    var hitDays: Int = 0
    var missedDays: Int = 0
    var graceDays: Int = 0
    var graceLeft: Int = 0
    var streak: Int = 0
    var todayHit: Bool?
    var dayStates: [ChallengeDayState] = []

    /// Today's value (or the last evaluated day's), nil when that day has no data.
    var todayValue: Double?
    /// 0...1 share of the goal (habit: hit days / days needed).
    var fraction: Double = 0
}

/// Pure challenge maths. The calendar is passed in; production passes `Calendar.current`.
nonisolated enum ChallengeEngine {
    static func progress(
        _ challenge: Challenge,
        daily: [ChallengeDay: Double],
        availability: ChallengeAvailability,
        now: Date,
        calendar: Calendar
    ) -> ChallengeProgress {
        let duration = challenge.durationDays
        guard ChallengeRules.isValid(challenge) else {
            return ChallengeProgress(status: .invalid, dayIndex: 0, durationDays: duration)
        }
        let today = ChallengeDay(now, calendar: calendar)
        if today < challenge.startDay {
            return ChallengeProgress(status: .notStarted, dayIndex: 0, durationDays: duration, graceDays: challenge.graceDays)
        }

        var lastDay = challenge.endDay
        var endedEarly = false
        if let endedAt = challenge.endedEarlyAt {
            let endedDay = max(challenge.startDay, ChallengeDay(endedAt, calendar: calendar))
            if endedDay < lastDay {
                lastDay = endedDay
            }
            endedEarly = true
        }
        let over = endedEarly || today > lastDay
        let evaluatedThrough = over ? lastDay : today
        let dayIndex = ChallengeDay.days(from: challenge.startDay, to: evaluatedThrough) + 1

        guard availability == .available else {
            return ChallengeProgress(status: .noData, dayIndex: dayIndex, durationDays: duration, graceDays: challenge.graceDays)
        }

        switch challenge.kind {
        case .total(let target):
            return amountProgress(challenge, goal: target, daily: daily, dayIndex: dayIndex, over: over, endedEarly: endedEarly)
        case .dailyAverage(let target):
            return amountProgress(
                challenge, goal: target * Double(duration), daily: daily,
                dayIndex: dayIndex, over: over, endedEarly: endedEarly
            )
        case .dailyHabit(let rule):
            return habitProgress(challenge, rule: rule, daily: daily, dayIndex: dayIndex, over: over, endedEarly: endedEarly)
        }
    }

    /// Whether one day's value satisfies the habit rule. No data never satisfies `.atMost`.
    static func isHit(_ value: Double?, rule: HabitRule) -> Bool {
        guard let value, value.isFinite else { return false }
        switch rule {
        case .atLeast(let threshold): return value >= threshold
        case .atMost(let threshold): return value <= threshold
        case .checkIn: return value >= 1
        }
    }

    // MARK: - Total / average

    private static func amountProgress(
        _ challenge: Challenge,
        goal: Double,
        daily: [ChallengeDay: Double],
        dayIndex: Int,
        over: Bool,
        endedEarly: Bool
    ) -> ChallengeProgress {
        let duration = challenge.durationDays
        var cumulative: [Double] = []
        var running = 0.0
        for offset in 0..<dayIndex {
            let value = daily[challenge.startDay.adding(days: offset)] ?? 0
            running += value.isFinite ? value : 0
            cumulative.append(running)
        }
        let total = running
        let expected = goal * Double(dayIndex) / Double(duration)
        var progress = ChallengeProgress(status: .onTrack, dayIndex: dayIndex, durationDays: duration)
        progress.total = total
        progress.goalTotal = goal
        progress.expectedToDate = expected
        progress.delta = total - expected
        progress.average = total / Double(max(1, dayIndex))
        progress.cumulative = cumulative
        progress.todayValue = daily[challenge.startDay.adding(days: dayIndex - 1)]
        progress.fraction = min(1, max(0, total / goal))
        if dayIndex >= 3 {
            progress.projected = total / Double(dayIndex) * Double(duration)
        }

        let met = total >= goal
        if met {
            progress.status = .complete
        } else if over {
            progress.status = endedEarly ? .ended : .failed
        } else {
            progress.status = total >= expected ? .onTrack : .behind
            // Today counts as elapsed; on the final day the remainder is due today.
            let daysLeft = max(1, duration - dayIndex)
            progress.requiredPerDay = ((goal - total) / Double(daysLeft)).rounded(.up)
        }
        return progress
    }

    // MARK: - Habit

    private static func habitProgress(
        _ challenge: Challenge,
        rule: HabitRule,
        daily: [ChallengeDay: Double],
        dayIndex: Int,
        over: Bool,
        endedEarly: Bool
    ) -> ChallengeProgress {
        let duration = challenge.durationDays
        let grace = challenge.graceDays
        let needed = duration - grace
        var hits = 0
        var misses = 0
        var streak = 0
        var states: [ChallengeDayState] = []
        var todayHit: Bool?

        for offset in 0..<dayIndex {
            let day = challenge.startDay.adding(days: offset)
            let hit = isHit(daily[day], rule: rule)
            let isToday = !over && offset == dayIndex - 1
            if hit {
                hits += 1
                streak += 1
                states.append(.hit)
            } else if isToday {
                states.append(.pending)
            } else {
                misses += 1
                if misses <= grace {
                    // Grace keeps the streak alive.
                    states.append(.grace)
                } else {
                    streak = 0
                    states.append(.miss)
                }
            }
            if isToday { todayHit = hit }
        }
        // Days after an early end or the window are never scored.
        let remaining = duration - dayIndex
        states.append(contentsOf: Array(repeating: .future, count: max(0, remaining)))

        var progress = ChallengeProgress(status: .onTrack, dayIndex: dayIndex, durationDays: duration)
        progress.hitDays = hits
        progress.missedDays = misses
        progress.graceDays = grace
        progress.graceLeft = max(0, grace - misses)
        progress.streak = streak
        progress.todayHit = todayHit
        progress.dayStates = states
        progress.todayValue = daily[challenge.startDay.adding(days: dayIndex - 1)]
        progress.fraction = min(1, Double(hits) / Double(max(1, needed)))
        progress.total = Double(hits)
        progress.goalTotal = Double(needed)

        if hits >= needed {
            progress.status = .complete
        } else if misses > grace {
            // Completion is now impossible.
            progress.status = .failed
        } else if over {
            progress.status = endedEarly ? .ended : .failed
        } else {
            progress.status = .onTrack
        }
        return progress
    }
}
