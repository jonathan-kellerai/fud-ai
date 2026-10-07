import Foundation

nonisolated struct PlannedNotification: Hashable, Sendable {
    var id: String
    var title: String
    var body: String
    var fireDate: Date
}

/// Plans today's one-shot challenge reminders (plan default 9): only for an
/// active challenge that is behind or hasn't hit today, never once the fire
/// time has passed, at most 2 per challenge and 20 in total, most behind first.
nonisolated enum ChallengeReminderPlanner {
    static let idPrefix = "challenge."
    static let maxPerChallenge = 2
    static let maxTotal = 20

    static func plan(
        _ items: [(challenge: Challenge, progress: ChallengeProgress)],
        now: Date,
        calendar: Calendar
    ) -> [PlannedNotification] {
        var candidates: [(urgency: Double, key: String, notes: [PlannedNotification])] = []
        for item in items {
            let challenge = item.challenge
            let progress = item.progress
            guard challenge.reminder.enabled, progress.status.isActive,
                  let fireDate = calendar.date(
                    bySettingHour: challenge.reminder.hour,
                    minute: challenge.reminder.minute,
                    second: 0,
                    of: now
                  ),
                  fireDate > now else {
                continue
            }
            let notes = notifications(for: challenge, progress: progress, fireDate: fireDate)
            guard !notes.isEmpty else { continue }
            candidates.append((urgency(challenge.kind, progress), challenge.id.uuidString, Array(notes.prefix(maxPerChallenge))))
        }
        let ordered = candidates.sorted {
            $0.urgency != $1.urgency ? $0.urgency > $1.urgency : $0.key < $1.key
        }
        return Array(ordered.flatMap(\.notes).prefix(maxTotal))
    }

    static func id(for challengeID: UUID, _ kind: String) -> String {
        "\(idPrefix)\(challengeID.uuidString).\(kind)"
    }

    private static func notifications(
        for challenge: Challenge,
        progress: ChallengeProgress,
        fireDate: Date
    ) -> [PlannedNotification] {
        switch challenge.kind {
        case .total, .dailyAverage:
            guard progress.status == .behind else { return [] }
            let body: String
            if let required = progress.requiredPerDay {
                body = "Behind pace. \(Int(required)) \(challenge.metric.unit) a day gets you back on track."
            } else {
                body = "Behind pace."
            }
            return [PlannedNotification(id: id(for: challenge.id, "nudge"), title: challenge.title, body: body, fireDate: fireDate)]
        case .dailyHabit(let rule):
            guard progress.todayHit != true else { return [] }
            if case .checkIn = rule {
                return [PlannedNotification(
                    id: id(for: challenge.id, "checkin"),
                    title: challenge.title,
                    body: "Check in for today.",
                    fireDate: fireDate
                )]
            }
            return [PlannedNotification(
                id: id(for: challenge.id, "nudge"),
                title: challenge.title,
                body: "Today isn't done yet.",
                fireDate: fireDate
            )]
        }
    }

    /// Share of the goal the challenge is behind (habits: share of grace used).
    private static func urgency(_ kind: ChallengeKind, _ progress: ChallengeProgress) -> Double {
        if !kind.isHabit {
            guard progress.goalTotal > 0 else { return 0 }
            return max(0, -progress.delta) / progress.goalTotal
        }
        guard progress.graceDays > 0 else { return 1 }
        return Double(progress.graceDays - progress.graceLeft) / Double(progress.graceDays)
    }
}
