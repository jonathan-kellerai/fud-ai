import Foundation

/// The words and numbers Challenges screens show. Views only place these strings.
nonisolated enum ChallengePresentation {
    static func amount(_ value: Double, metric: ChallengeMetric, locale: Locale = .current) -> String {
        switch metric {
        case .waterAppLog:
            let liters = value / 1_000
            return "\(number(liters, fractionDigits: 1, locale: locale)) L"
        default:
            return number(value, fractionDigits: 0, locale: locale)
        }
    }

    /// The unit as shown after an amount ("reps", "L", "steps").
    static func unit(_ metric: ChallengeMetric) -> String {
        metric == .waterAppLog ? "L" : metric.unit
    }

    static func signedAmount(_ value: Double, metric: ChallengeMetric, locale: Locale = .current) -> String {
        let magnitude = amount(abs(value), metric: metric, locale: locale)
        if value > 0.5 { return "+\(magnitude)" }
        if value < -0.5 { return "\u{2212}\(magnitude)" }
        return magnitude
    }

    static func statusLabel(_ status: ChallengeStatus, metric: ChallengeMetric) -> String {
        switch status {
        case .notStarted: "Not started"
        case .onTrack: "On track"
        case .behind: "Behind"
        case .complete: "Done"
        case .failed: "Missed"
        case .ended: "Ended"
        case .noData: metric == .steps ? "No step data" : "No data"
        case .invalid: "Can't evaluate"
        }
    }

    /// "DAY 12 / 30", "STARTS IN 3 DAYS", "30 DAYS".
    static func dayLabel(_ progress: ChallengeProgress, challenge: Challenge, now: Date, calendar: Calendar) -> String {
        if progress.status == .notStarted {
            let days = ChallengeDay.days(from: ChallengeDay(now, calendar: calendar), to: challenge.startDay)
            return days == 1 ? "Starts tomorrow" : "Starts in \(days) days"
        }
        if progress.status.isFinal {
            return "\(progress.dayIndex) of \(progress.durationDays) days"
        }
        return "Day \(progress.dayIndex) / \(progress.durationDays)"
    }

    /// "10,000 reps in 30 days", "3.0 L a day, 28 of 30 days", "Check in daily, 28 of 30 days".
    static func goalSummary(_ challenge: Challenge, locale: Locale = .current) -> String {
        let metric = challenge.metric
        let days = challenge.durationDays
        switch challenge.kind {
        case .total(let target):
            return "\(amount(target, metric: metric, locale: locale)) \(unit(metric)) in \(days) days"
        case .dailyAverage(let target):
            return "Average \(amount(target, metric: metric, locale: locale)) \(unit(metric)) a day for \(days) days"
        case .dailyHabit(let rule):
            let needed = days - challenge.graceDays
            let rulePart: String
            switch rule {
            case .atLeast(let threshold):
                rulePart = "At least \(amount(threshold, metric: metric, locale: locale)) \(unit(metric)) a day"
            case .atMost(let threshold):
                rulePart = "At most \(amount(threshold, metric: metric, locale: locale)) \(unit(metric)) a day"
            case .checkIn:
                rulePart = "Check in daily"
            }
            return "\(rulePart), \(needed) of \(days) days"
        }
    }

    /// The stat tiles for the detail screen, in display order.
    static func tiles(_ challenge: Challenge, _ progress: ChallengeProgress, locale: Locale = .current) -> [ChallengeTile] {
        let metric = challenge.metric
        let none = "\u{2014}"
        if progress.status == .noData || progress.status == .invalid || progress.status == .notStarted {
            return []
        }
        switch challenge.kind {
        case .total, .dailyAverage:
            let isAverage: Bool = {
                if case .dailyAverage = challenge.kind { return true }
                return false
            }()
            var tiles = [
                ChallengeTile(
                    label: "Total",
                    value: amount(progress.total, metric: metric, locale: locale),
                    detail: "of \(amount(progress.goalTotal, metric: metric, locale: locale))"
                ),
                ChallengeTile(
                    label: "Expected",
                    value: amount(progress.expectedToDate, metric: metric, locale: locale),
                    detail: "by day \(progress.dayIndex)"
                ),
                ChallengeTile(
                    label: "Pace",
                    value: signedAmount(progress.delta, metric: metric, locale: locale),
                    detail: progress.delta < -0.5 ? "behind" : "ahead"
                ),
            ]
            if isAverage {
                tiles.append(ChallengeTile(
                    label: "Average",
                    value: amount(progress.average, metric: metric, locale: locale),
                    detail: "a day so far"
                ))
            } else {
                tiles.append(ChallengeTile(
                    label: "Projected",
                    value: progress.projected.map { amount($0, metric: metric, locale: locale) } ?? none,
                    detail: progress.projected == nil ? "from day 3" : "at this rate"
                ))
            }
            tiles.append(ChallengeTile(
                label: "Need / day",
                value: progress.requiredPerDay.map { amount($0, metric: metric, locale: locale) } ?? none,
                detail: progress.requiredPerDay == nil ? nil : "\(max(1, progress.durationDays - progress.dayIndex)) days left"
            ))
            return tiles
        case .dailyHabit:
            let needed = progress.durationDays - progress.graceDays
            let today: String
            switch progress.todayHit {
            case .some(true): today = "Done"
            case .some(false): today = "Not yet"
            case .none: today = none
            }
            return [
                ChallengeTile(label: "Hit days", value: "\(progress.hitDays) / \(needed)", detail: nil),
                ChallengeTile(label: "Grace left", value: "\(progress.graceLeft)", detail: "of \(progress.graceDays)"),
                ChallengeTile(label: "Streak", value: "\(progress.streak)", detail: progress.streak == 1 ? "day" : "days"),
                ChallengeTile(label: "Today", value: today, detail: nil),
            ]
        }
    }

    /// Cumulative share of the goal per day, 0...1, for the pace chart.
    static func paceSeries(_ progress: ChallengeProgress) -> [Double] {
        guard progress.goalTotal > 0 else { return [] }
        return progress.cumulative.map { min(1, max(0, $0 / progress.goalTotal)) }
    }

    /// Spoken summary of the habit grid.
    static func gridSummary(_ progress: ChallengeProgress) -> String {
        let hits = progress.hitDays
        let misses = progress.missedDays
        return "\(hits) \(hits == 1 ? "day" : "days") hit, \(misses) missed, \(progress.graceLeft) grace left."
    }

    /// Hand logging (custom amounts, check-ins) is open from the start through the last day,
    /// even after a total is met, and closes on failure or an early end.
    static func acceptsLogs(_ challenge: Challenge, status: ChallengeStatus?, today: ChallengeDay) -> Bool {
        guard !challenge.metric.isAutomatic || challenge.isCheckIn,
              challenge.endedEarlyAt == nil,
              challenge.contains(today) else {
            return false
        }
        switch status {
        case .failed, .ended, .invalid, .noData: return false
        case .notStarted, .onTrack, .behind, .complete, .none: return true
        }
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded(.down)))%"
    }

    private static func number(_ value: Double, fractionDigits: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value.rounded()))
    }
}

nonisolated struct ChallengeTile: Hashable, Sendable {
    var label: String
    var value: String
    var detail: String?
}

/// The create form's values. Builds a valid `Challenge` or nothing.
nonisolated struct ChallengeDraft: Hashable, Sendable {
    enum Kind: String, CaseIterable, Hashable, Sendable {
        case total
        case dailyAverage
        case dailyHabit

        var title: String {
            switch self {
            case .total: "Total"
            case .dailyAverage: "Daily average"
            case .dailyHabit: "Daily habit"
            }
        }
    }

    enum MetricChoice: String, CaseIterable, Hashable, Sendable {
        case custom
        case steps
        case water
        case protein
        case calories

        var title: String {
            switch self {
            case .custom: "Custom"
            case .steps: "Steps"
            case .water: "Water (app log)"
            case .protein: "Protein"
            case .calories: "Calories"
            }
        }
    }

    enum HabitChoice: String, CaseIterable, Hashable, Sendable {
        case atLeast
        case atMost
        case checkIn

        var title: String {
            switch self {
            case .atLeast: "At least"
            case .atMost: "At most"
            case .checkIn: "Check-in"
            }
        }
    }

    var title = ""
    var kind: Kind = .total
    var metric: MetricChoice = .custom
    var customName = ""
    var customUnit = "reps"
    var habit: HabitChoice = .atLeast
    /// Typed target (water in litres, as shown).
    var targetText = ""
    var durationDays = ChallengeRules.defaultDuration
    var graceDays = ChallengeRules.defaultGrace(duration: ChallengeRules.defaultDuration)
    var stakeText = ""
    var remindersOn = true

    var needsTarget: Bool { !(kind == .dailyHabit && habit == .checkIn) }

    /// The duration changed: keep grace in range and follow the default.
    mutating func setDuration(_ days: Int) {
        durationDays = min(max(days, ChallengeRules.durationRange.lowerBound), ChallengeRules.durationRange.upperBound)
        graceDays = ChallengeRules.defaultGrace(duration: durationDays)
    }

    var parsedTarget: Double? {
        let cleaned = targetText
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(cleaned) else { return nil }
        // Water is typed in litres and stored in ml.
        return metric == .water ? value * 1_000 : value
    }

    func build(id: UUID = UUID(), now: Date, calendar: Calendar) -> Challenge? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let challengeMetric: ChallengeMetric
        switch metric {
        case .custom:
            let label = customName.trimmingCharacters(in: .whitespacesAndNewlines)
            let unit = customUnit.trimmingCharacters(in: .whitespacesAndNewlines)
            challengeMetric = .custom(name: label.isEmpty ? name : label, unit: unit.isEmpty ? "times" : unit)
        case .steps: challengeMetric = .steps
        case .water: challengeMetric = .waterAppLog
        case .protein: challengeMetric = .protein
        case .calories: challengeMetric = .calories
        }
        let challengeKind: ChallengeKind
        if kind == .dailyHabit && habit == .checkIn {
            challengeKind = .dailyHabit(.checkIn)
        } else {
            guard let target = parsedTarget, ChallengeRules.isValidTarget(target) else { return nil }
            switch kind {
            case .total: challengeKind = .total(target)
            case .dailyAverage: challengeKind = .dailyAverage(target)
            case .dailyHabit:
                challengeKind = .dailyHabit(habit == .atMost ? .atMost(target) : .atLeast(target))
            }
        }
        let stake = stakeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let challenge = Challenge(
            id: id,
            title: name.uppercased(),
            kind: challengeKind,
            metric: challengeMetric,
            startDay: ChallengeDay(now, calendar: calendar),
            durationDays: durationDays,
            graceDays: kind == .dailyHabit ? graceDays : 0,
            rewards: ChallengeRules.defaultRewards(for: challengeKind),
            stake: stake.isEmpty ? nil : ChallengeStake(text: stake),
            reminder: ChallengeReminder(enabled: remindersOn, hour: 19, minute: 0),
            quickAddChips: Self.chips(for: challengeKind, metric: challengeMetric),
            createdAt: now,
            endedEarlyAt: nil
        )
        return ChallengeRules.isValid(challenge) ? challenge : nil
    }

    /// Quick-add amounts: about 1/40, 1/20 and 1/10 of a total's daily pace, rounded to friendly steps.
    static func chips(for kind: ChallengeKind, metric: ChallengeMetric) -> [Double] {
        guard !metric.isAutomatic else { return [] }
        switch kind {
        case .total(let target):
            let perDay = target / Double(ChallengeRules.defaultDuration)
            let rounded = [0.25, 0.5, 1].map { friendly(perDay * $0) }
            return Array(Set(rounded)).sorted()
        case .dailyAverage(let target):
            return Array(Set([0.25, 0.5, 1].map { friendly(target * $0) })).sorted()
        case .dailyHabit(.atLeast(let threshold)), .dailyHabit(.atMost(let threshold)):
            return Array(Set([0.5, 1].map { friendly(threshold * $0) })).sorted()
        case .dailyHabit(.checkIn):
            return []
        }
    }

    private static func friendly(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 1 }
        let steps: [Double] = [1, 5, 10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000]
        let step = steps.last(where: { $0 * 2 <= value }) ?? 1
        return max(1, (value / step).rounded() * step)
    }
}
