import Foundation

// MARK: - Workouts

/// One completed-session row the weekly math reads (from the on-device workout log).
nonisolated struct ProgressBridgeWorkout: Equatable, Sendable {
    let id: String
    /// "COMPLETED" for real saved sessions.
    let kind: String?
    let programDay: String?
    let title: String?
    let sessionDate: String?
    let recordedAt: String?
    let synthetic: Bool?

    init(
        id: String,
        kind: String? = "COMPLETED",
        programDay: String? = nil,
        title: String? = nil,
        sessionDate: String?,
        recordedAt: String? = nil,
        synthetic: Bool? = nil
    ) {
        self.id = id
        self.kind = kind
        self.programDay = programDay
        self.title = title
        self.sessionDate = sessionDate
        self.recordedAt = recordedAt
        self.synthetic = synthetic
    }
}

/// Sets and volume of one completed workout.
nonisolated struct ProgressWorkoutTotals: Equatable, Sendable {
    let sets: Int
    /// Σ load_lb × reps.
    let volumeLb: Double
}

// MARK: - Weekly summary

/// A completed workout with its day key and the Monday of its week.
nonisolated struct ProgressCompletedSession: Equatable, Sendable {
    let workout: ProgressBridgeWorkout
    let day: String
    let week: String
}

nonisolated struct ProgressTrainingWeek: Equatable, Sendable, Identifiable {
    /// Monday of the week, YYYY-MM-DD.
    let weekStart: String
    /// First and last day of this week inside the selected range. A partial
    /// first week starts after Monday; the current week ends today.
    let firstDay: String
    let lastDay: String
    /// Days of this week inside the range (1–7).
    let days: Int
    let sessions: Int
    /// Nil when the week has sessions but none of their sets were loaded.
    let sets: Int?
    /// Pounds lifted (load_lb × reps). Nil like `sets`.
    let volumeLb: Double?
    /// The workout list ends inside this week, so older sessions of the same
    /// week may be missing.
    let isIncomplete: Bool

    var id: String { weekStart }
    var isPartial: Bool { days < 7 }
}

nonisolated struct ProgressTrainingSummary: Equatable, Sendable {
    /// Weeks with loaded sessions, oldest first. Weeks before the workout list
    /// cutoff are unknown and left out (see `unloadedWeeks`).
    let weeks: [ProgressTrainingWeek]
    /// First and last day counted (YYYY-MM-DD, Eastern).
    let rangeStartDay: String
    let rangeEndDay: String
    /// Weeks overlapping the selected range, before the week cap.
    let weeksInRange: Int
    let weekLimit: Int
    /// The workout list reached `listLimit`, so older sessions may be missing.
    let listTruncated: Bool
    /// Oldest day in a truncated list, when that is on or after the first
    /// counted day: sessions before it are unknown, not zero, and its own
    /// week may be missing sessions.
    let sessionListCutoff: String?
    /// Shown weeks that end before `sessionListCutoff`; not drawn or averaged.
    let unloadedWeeks: Int
    /// Completed sessions in the shown weeks.
    let sessionsInRange: Int
    /// Most recent sessions whose sets were requested (at most the detail limit).
    let detailSessions: Int
    let detailLimit: Int
    /// Requested sessions whose sets could not be loaded.
    let failedDetails: Int

    /// Weeks shown after the week cap (loaded or not).
    var shownWeeks: Int { min(weeksInRange, weekLimit) }
    var isTruncated: Bool { weeksInRange > weekLimit }
    /// Sets and volume only cover the most recent `detailLimit` sessions.
    var isDetailLimited: Bool { sessionsInRange > detailSessions }
    var totalSessions: Int { weeks.reduce(0) { $0 + $1.sessions } }
    /// Sum over weeks with sessions whose sets loaded. Zero only when the
    /// shown weeks have no sessions; nil when sessions exist but no sets
    /// loaded (empty weeks' zeros don't count as a known total).
    var totalSets: Int? {
        Self.total(weeks, \ProgressTrainingWeek.sets)
    }
    var totalVolumeLb: Double? {
        Self.total(weeks, \ProgressTrainingWeek.volumeLb)
    }
    /// Some requested sets failed to load, so the totals undercount; the card
    /// shows the "didn't load" note with them.
    var hasPartialDetails: Bool { failedDetails > 0 && totalSets != nil }

    private static func total<Value: AdditiveArithmetic>(
        _ weeks: [ProgressTrainingWeek],
        _ value: KeyPath<ProgressTrainingWeek, Value?>
    ) -> Value? {
        let active = weeks.filter { $0.sessions > 0 }
        guard !active.isEmpty else { return weeks.isEmpty ? nil : Value.zero }
        let loaded: [Value] = active.compactMap { $0[keyPath: value] }
        return loaded.isEmpty ? nil : loaded.reduce(Value.zero, +)
    }
    /// Sessions per 7 days over the fully loaded days in range, so a partial
    /// first or current week counts only its days. The cutoff week is left
    /// out because it may be missing sessions.
    var averageSessionsPerWeek: Double? {
        let complete = weeks.filter { !$0.isIncomplete }
        let days = complete.reduce(0) { $0 + $1.days }
        guard days > 0 else { return nil }
        let sessions = complete.reduce(0) { $0 + $1.sessions }
        return Double(sessions) / (Double(days) / 7)
    }
    /// The oldest shown week starts after its Monday because the range does.
    var firstWeekIsPartial: Bool {
        guard unloadedWeeks == 0, let first = weeks.first else { return false }
        return first.firstDay != first.weekStart
    }
    var isEmpty: Bool {
        weeks.allSatisfy { $0.sessions == 0 }
    }
}

nonisolated enum ProgressTrainingMath {
    static let workoutListLimit = 200
    /// Most recent completed sessions per range whose sets are fetched.
    static let maxDetailSessions = 60
    /// Weeks drawn; a year of bars. Older weeks in All are summarized in a note.
    static let maxWeeks = 53

    static var eastern: TimeZone { TimeZone(identifier: "America/New_York") ?? .gmt }

    /// Gregorian in America/New_York: the calendar every training day key uses.
    static var easternCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eastern
        return calendar
    }

    /// First and last day key (Eastern) for a range, both from one calendar.
    /// Bounded ranges count back `range.days` days including today. All starts
    /// at the oldest completed workout, or today without one.
    static func rangeDayKeys(
        for range: TimeRange,
        now: Date,
        oldestWorkoutDay: String?,
        calendar: Calendar = ProgressTrainingMath.easternCalendar
    ) -> (start: String, today: String) {
        let startOfToday = calendar.startOfDay(for: now)
        let todayKey = dayKey(forLocalDay: startOfToday, calendar: calendar)
        guard range != .allTime else {
            let oldest = oldestWorkoutDay.flatMap { $0 <= todayKey ? $0 : nil }
            return (oldest ?? todayKey, todayKey)
        }
        let start = calendar.date(byAdding: .day, value: -(range.days - 1), to: startOfToday) ?? startOfToday
        return (dayKey(forLocalDay: start, calendar: calendar), todayKey)
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// Real saved sessions: kind "COMPLETED" (any case) and not synthetic.
    static func isCompleted(_ workout: ProgressBridgeWorkout) -> Bool {
        guard workout.synthetic != true else { return false }
        return workout.kind?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "COMPLETED"
    }

    /// session_date's YYYY-MM-DD (it may be "2026-09-28" or
    /// "2026-09-28T00:00:00.000Z"), else recorded_at as an Eastern day.
    static func dayKey(for workout: ProgressBridgeWorkout, timeZone: TimeZone = ProgressTrainingMath.eastern) -> String? {
        if let raw = workout.sessionDate?.trimmingCharacters(in: .whitespacesAndNewlines), raw.count >= 10 {
            let key = String(raw.prefix(10))
            if parseDayKey(key) != nil { return key }
        }
        if let raw = workout.recordedAt, let date = parseTimestamp(raw) {
            return dayKey(for: date, timeZone: timeZone)
        }
        return nil
    }

    static func parseTimestamp(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: trimmed)
    }

    /// Strict YYYY-MM-DD, as midnight UTC.
    static func parseDayKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        let calendar = utcCalendar
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }

    static func dayKey(for date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// Local calendar day (the user's day) as YYYY-MM-DD.
    static func dayKey(forLocalDay date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// Monday on or before the given day.
    static func mondayKey(for dayKey: String) -> String? {
        guard let date = parseDayKey(dayKey) else { return nil }
        let calendar = utcCalendar
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
        let back = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -back, to: date) else { return nil }
        return Self.dayKey(for: monday, timeZone: .gmt)
    }

    /// Monday keys of every week overlapping `startDayKey...endDayKey`, oldest first.
    static func weekKeys(from startDayKey: String, through endDayKey: String) -> [String] {
        guard let firstMonday = mondayKey(for: startDayKey).flatMap(parseDayKey),
              let lastMonday = mondayKey(for: endDayKey).flatMap(parseDayKey),
              firstMonday <= lastMonday else { return [] }
        let calendar = utcCalendar
        var keys: [String] = []
        var cursor = firstMonday
        while cursor <= lastMonday {
            keys.append(dayKey(for: cursor, timeZone: .gmt))
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return keys
    }

    /// The most recent `limit` week keys in range; these are the only weeks
    /// the card counts and draws.
    static func displayedWeekKeys(from startDayKey: String, through endDayKey: String, limit: Int = ProgressTrainingMath.maxWeeks) -> (shown: [String], total: Int) {
        let all = weekKeys(from: startDayKey, through: endDayKey)
        return (Array(all.suffix(max(0, limit))), all.count)
    }

    /// `key` moved by `days` calendar days.
    static func shiftDayKey(_ key: String, days: Int) -> String? {
        guard let date = parseDayKey(key),
              let shifted = utcCalendar.date(byAdding: .day, value: days, to: date) else { return nil }
        return dayKey(for: shifted, timeZone: .gmt)
    }

    /// Whole days from `start` to `end` (0 for the same day).
    static func daysBetween(_ start: String, _ end: String) -> Int? {
        guard let from = parseDayKey(start), let to = parseDayKey(end) else { return nil }
        return utcCalendar.dateComponents([.day], from: from, to: to).day
    }

    /// First day counted: the range start, or the Monday of the oldest shown
    /// week when the week cap drops older weeks.
    static func countedStartDay(
        startDayKey: String,
        todayKey: String,
        weekLimit: Int = ProgressTrainingMath.maxWeeks
    ) -> String {
        let shown = displayedWeekKeys(from: startDayKey, through: todayKey, limit: weekLimit).shown
        guard let firstMonday = shown.first else { return startDayKey }
        return max(startDayKey, firstMonday)
    }

    /// Completed sessions dated `startDayKey...todayKey`, most recent first.
    /// A session earlier in the first overlapping week is outside the range.
    static func completedSessions(
        _ workouts: [ProgressBridgeWorkout],
        startDayKey: String,
        todayKey: String,
        timeZone: TimeZone = ProgressTrainingMath.eastern
    ) -> [ProgressCompletedSession] {
        var seen: Set<String> = []
        var rows: [ProgressCompletedSession] = []
        for workout in workouts where isCompleted(workout) {
            guard !seen.contains(workout.id),
                  let day = dayKey(for: workout, timeZone: timeZone),
                  day >= startDayKey,
                  day <= todayKey,
                  let monday = mondayKey(for: day) else { continue }
            seen.insert(workout.id)
            rows.append(ProgressCompletedSession(workout: workout, day: day, week: monday))
        }
        rows.sort { lhs, rhs in
            if lhs.day != rhs.day { return lhs.day > rhs.day }
            let lhsRecorded = lhs.workout.recordedAt ?? ""
            let rhsRecorded = rhs.workout.recordedAt ?? ""
            if lhsRecorded != rhsRecorded { return lhsRecorded > rhsRecorded }
            return lhs.workout.id > rhs.workout.id
        }
        return rows
    }

    /// Ids of the workouts whose sets should be loaded: the most recent
    /// `detailLimit` completed sessions inside the counted days.
    static func detailWorkoutIDs(
        workouts: [ProgressBridgeWorkout],
        startDayKey: String,
        todayKey: String,
        weekLimit: Int = ProgressTrainingMath.maxWeeks,
        detailLimit: Int = ProgressTrainingMath.maxDetailSessions,
        timeZone: TimeZone = ProgressTrainingMath.eastern
    ) -> [String] {
        let firstDay = countedStartDay(startDayKey: startDayKey, todayKey: todayKey, weekLimit: weekLimit)
        return completedSessions(workouts, startDayKey: firstDay, todayKey: todayKey, timeZone: timeZone)
            .prefix(max(0, detailLimit))
            .map { $0.workout.id }
    }

    /// Sessions, sets and volume per Monday–Sunday week. `details` holds the
    /// loaded sets per workout id; ids requested but missing from it count as
    /// `failedDetails` (passed by the loader).
    static func summary(
        workouts: [ProgressBridgeWorkout],
        details: [String: ProgressWorkoutTotals],
        startDayKey: String,
        todayKey: String,
        failedDetails: Int = 0,
        listLimit: Int = ProgressTrainingMath.workoutListLimit,
        weekLimit: Int = ProgressTrainingMath.maxWeeks,
        detailLimit: Int = ProgressTrainingMath.maxDetailSessions,
        timeZone: TimeZone = ProgressTrainingMath.eastern
    ) -> ProgressTrainingSummary {
        let (shown, total) = displayedWeekKeys(from: startDayKey, through: todayKey, limit: weekLimit)
        let firstDay = countedStartDay(startDayKey: startDayKey, todayKey: todayKey, weekLimit: weekLimit)
        let sessions = completedSessions(workouts, startDayKey: firstDay, todayKey: todayKey, timeZone: timeZone)
        let requested = Set(sessions.prefix(max(0, detailLimit)).map { $0.workout.id })

        var sessionsByWeek: [String: Int] = [:]
        var setsByWeek: [String: Int] = [:]
        var volumeByWeek: [String: Double] = [:]
        for row in sessions {
            sessionsByWeek[row.week, default: 0] += 1
            guard requested.contains(row.workout.id), let totals = details[row.workout.id] else { continue }
            setsByWeek[row.week, default: 0] += totals.sets
            volumeByWeek[row.week, default: 0] += totals.volumeLb
        }
        // A full list may have dropped older sessions: every day before its
        // oldest row is unknown, and the week holding that row may be short.
        // That includes the oldest day itself, even when it is the first
        // counted day (the range or All start): more rows may share it.
        let listTruncated = workouts.count >= listLimit
        var cutoff: String?
        if listTruncated,
           let oldest = workouts.compactMap({ dayKey(for: $0, timeZone: timeZone) }).min(),
           oldest >= firstDay {
            cutoff = oldest
        }
        let cutoffMonday = cutoff.flatMap { mondayKey(for: $0) }

        var weeks: [ProgressTrainingWeek] = []
        var unloadedWeeks = 0
        for key in shown {
            if let cutoffMonday, key < cutoffMonday {
                unloadedWeeks += 1
                continue
            }
            let weekFirst = max(key, firstDay)
            let weekLast = min(shiftDayKey(key, days: 6) ?? key, todayKey)
            let days = max(1, min(7, (daysBetween(weekFirst, weekLast) ?? 6) + 1))
            let count = sessionsByWeek[key] ?? 0
            // A week without sessions truly has zero sets; a week whose
            // sessions have no loaded sets is unknown.
            let known = count == 0 || setsByWeek[key] != nil
            weeks.append(ProgressTrainingWeek(
                weekStart: key,
                firstDay: weekFirst,
                lastDay: weekLast,
                days: days,
                sessions: count,
                sets: known ? (setsByWeek[key] ?? 0) : nil,
                volumeLb: known ? (volumeByWeek[key] ?? 0) : nil,
                isIncomplete: key == cutoffMonday
            ))
        }

        return ProgressTrainingSummary(
            weeks: weeks,
            rangeStartDay: firstDay,
            rangeEndDay: todayKey,
            weeksInRange: total,
            weekLimit: weekLimit,
            listTruncated: listTruncated,
            sessionListCutoff: cutoff,
            unloadedWeeks: unloadedWeeks,
            sessionsInRange: sessions.count,
            detailSessions: requested.count,
            detailLimit: detailLimit,
            failedDetails: failedDetails
        )
    }
}
