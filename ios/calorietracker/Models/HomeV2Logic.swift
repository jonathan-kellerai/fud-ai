//
//  HomeV2Logic.swift
//  calorietracker
//
//  Pure Home v2 math. Views and HealthKit stay out of this file so the
//  rules can be tested without a device.
//

import Foundation

enum HomeV2Logic {
    static let stepsCutoffHour = 22
    static let shortSleepSeconds: TimeInterval = 6 * 60 * 60
    static let volumeUnavailableText = "volume can't be calculated"
    private static let trendNoisePounds = 0.1

    struct StepsPace: Equatable {
        var remaining: Int
        var perHour: Int?
        var met: Bool
        var windowClosed: Bool
    }

    /// Ring color for the steps target. Olive at 10,000 or when the pace is met,
    /// rust when the day is late and steps are still short, blood otherwise.
    enum StepsRingTone: Equatable {
        case blood
        case rust
        case olive
    }

    struct CalorieRemainder: Equatable {
        enum Kind: Equatable {
            case remaining
            case over
            case met
        }

        var eaten: Int
        var target: Int
        var amount: Int
        var kind: Kind

        /// Remaining is target minus eaten. Burned calories are not an input.
        static func resolve(eaten: Int, target: Int) -> CalorieRemainder {
            let eaten = max(eaten, 0)
            let target = max(target, 0)
            let delta = target - eaten
            if delta > 0 {
                return CalorieRemainder(eaten: eaten, target: target, amount: delta, kind: .remaining)
            }
            if delta < 0 {
                return CalorieRemainder(eaten: eaten, target: target, amount: -delta, kind: .over)
            }
            return CalorieRemainder(eaten: eaten, target: target, amount: 0, kind: .met)
        }
    }

    struct DatedValue: Equatable {
        var date: Date
        var value: Double
    }

    struct WindowTrend: Equatable {
        var current: Double?
        var prior: Double?
        var change: Double?
        var sparkline: [DatedValue]
    }

    struct WeekDayStatus: Equatable {
        var lifted: Bool?
        var stepsHit: Bool?
        var foodLogged: Bool?
    }

    struct SessionExerciseSummary: Equatable {
        var exercise: String
        var sets: Int
        var topLoadLb: Double
        var topReps: Int
    }

    struct SessionSummary: Equatable {
        var exercises: [SessionExerciseSummary]
        var totalSets: Int
    }

    struct WeekSoFar: Equatable {
        var sessionsDone: Int
        var sessionsScheduled: Int
        var stepDaysHit: Int
        var daysElapsed: Int
        var averageProtein: Double?
        var milestone: String?
    }

    enum PeptideVolumeState: Equatable {
        case shown(amount: String, units: String)
        case unavailable
    }

    static func stepsPace(
        steps: Int,
        target: Int,
        now: Date,
        calendar: Calendar,
        cutoffHour: Int = stepsCutoffHour
    ) -> StepsPace {
        let steps = max(steps, 0)
        let target = max(target, 0)
        let remaining = max(target - steps, 0)
        if target == 0 || remaining == 0 {
            return StepsPace(remaining: 0, perHour: nil, met: true, windowClosed: false)
        }
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = cutoffHour
        parts.minute = 0
        parts.second = 0
        guard let cutoff = calendar.date(from: parts) else {
            return StepsPace(remaining: remaining, perHour: nil, met: false, windowClosed: false)
        }
        let seconds = cutoff.timeIntervalSince(now)
        if seconds < 60 {
            return StepsPace(remaining: remaining, perHour: nil, met: false, windowClosed: true)
        }
        let perHour = Int((Double(remaining) / (seconds / 3600)).rounded())
        return StepsPace(remaining: remaining, perHour: perHour, met: false, windowClosed: false)
    }

    static func stepsRingTone(steps: Int, pace: StepsPace, hour: Int, lateHour: Int = 18, goal: Int = StepsGoal.fallback) -> StepsRingTone {
        if pace.met || steps >= goal {
            return .olive
        }
        if pace.windowClosed || hour >= lateHour {
            return .rust
        }
        return .blood
    }

    static func windowTrend(
        samples: [DatedValue],
        ending: Date,
        calendar: Calendar,
        windowDays: Int = 7
    ) -> WindowTrend {
        let daily = dailyLatest(samples, calendar: calendar)
        let end = calendar.startOfDay(for: ending)
        let current = mean(daily: daily, ending: end, days: windowDays, calendar: calendar)
        let priorEnd = calendar.date(byAdding: .day, value: -windowDays, to: end) ?? end
        let prior = mean(daily: daily, ending: priorEnd, days: windowDays, calendar: calendar)
        let change: Double?
        if let current, let prior {
            change = current - prior
        } else {
            change = nil
        }
        return WindowTrend(
            current: current,
            prior: prior,
            change: change,
            sparkline: sparkline(daily: daily, ending: end, days: windowDays * 2, calendar: calendar)
        )
    }

    static func recompCaption(weightChangeLb: Double?, leanChangeLb: Double?) -> String? {
        guard let weightChangeLb, weightChangeLb < -trendNoisePounds, let leanChangeLb else { return nil }
        if leanChangeLb > trendNoisePounds {
            return "Lean mass is up while weight is down."
        }
        if leanChangeLb >= -trendNoisePounds {
            return "Lean mass is holding while weight is down."
        }
        return nil
    }

    static func weekDayStatus(
        workoutLogged: Bool?,
        steps: Int?,
        stepsTarget: Int,
        foodEntries: Int?
    ) -> WeekDayStatus {
        let stepsHit: Bool?
        if let steps {
            stepsHit = stepsTarget > 0 && steps >= stepsTarget
        } else {
            stepsHit = nil
        }
        let foodLogged = foodEntries.map { $0 > 0 }
        return WeekDayStatus(lifted: workoutLogged, stepsHit: stepsHit, foodLogged: foodLogged)
    }

    static func sessionSummary(sets: [(exercise: String, loadLb: Double, reps: Int)]) -> SessionSummary {
        var order: [String] = []
        var grouped: [String: [(loadLb: Double, reps: Int)]] = [:]
        for set in sets {
            let name = set.exercise.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if grouped[name] == nil {
                order.append(name)
                grouped[name] = []
            }
            grouped[name, default: []].append((set.loadLb, set.reps))
        }
        let exercises = order.map { name in
            let rows = grouped[name] ?? []
            let top = rows.max { lhs, rhs in
                if lhs.loadLb != rhs.loadLb { return lhs.loadLb < rhs.loadLb }
                return lhs.reps < rhs.reps
            }
            return SessionExerciseSummary(
                exercise: name,
                sets: rows.count,
                topLoadLb: top?.loadLb ?? 0,
                topReps: top?.reps ?? 0
            )
        }
        return SessionSummary(exercises: exercises, totalSets: exercises.reduce(0) { $0 + $1.sets })
    }

    static func poorSleepRule(from notes: String?) -> String? {
        guard let notes else { return nil }
        let lines = notes.components(separatedBy: .newlines)
        if let line = lines.first(where: { $0.localizedCaseInsensitiveContains("Poor-sleep rule:") }) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let range = notes.range(of: "Poor-sleep rule:", options: .caseInsensitive) else { return nil }
        let paragraph = notes[range.lowerBound...].split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
        let trimmed = paragraph.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func poorSleepRuleIfShort(asleepSeconds: TimeInterval?, notes: String?) -> String? {
        guard let asleepSeconds, asleepSeconds < shortSleepSeconds else { return nil }
        return poorSleepRule(from: notes)
    }

    static func peptideCardVisible(
        hasActiveSchedules: Bool,
        plannedCount: Int,
        completedCount: Int
    ) -> Bool {
        hasActiveSchedules || plannedCount > 0 || completedCount > 0
    }

    static func volumeState(
        volume: Double?,
        volumeUnits: String?,
        volumeBasis: String?,
        calcGate: String?,
        concentrationBasis: String?
    ) -> PeptideVolumeState {
        let gate = calcGate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let basis = concentrationBasis?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let volumeBasis = volumeBasis?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if gate.uppercased().hasPrefix("BLOCKED")
            || basis == "NONE"
            || volumeBasis == "NOT_CALCULATED"
            || volume == nil {
            return .unavailable
        }
        return .shown(amount: storedNumber(volume ?? 0), units: volumeUnits ?? "")
    }

    static func weekSoFar(
        today: Date,
        calendar: Calendar,
        trainingDaysPerWeek: Int,
        workoutCivilDates: [String],
        stepsByCivilDate: [String: Int],
        stepsTarget: Int,
        proteinByCivilDate: [String: Double],
        programStartDate: String?,
        reductionWeek: Int?
    ) -> WeekSoFar {
        let days = elapsedCivilDates(through: today, calendar: calendar)
        let workoutDays = Set(workoutCivilDates.map { String($0.prefix(10)) })
        let sessionsDone = days.filter { workoutDays.contains($0) }.count
        var stepDays = 0
        var proteinTotal = 0.0
        var proteinDaysWithFood = 0
        for day in days {
            if let steps = stepsByCivilDate[day], stepsTarget > 0, steps >= stepsTarget {
                stepDays += 1
            }
            let protein = proteinByCivilDate[day] ?? 0
            proteinTotal += protein
            if protein > 0 { proteinDaysWithFood += 1 }
        }
        let average: Double? = proteinDaysWithFood > 0 && !days.isEmpty
            ? proteinTotal / Double(days.count)
            : nil
        return WeekSoFar(
            sessionsDone: sessionsDone,
            sessionsScheduled: max(trainingDaysPerWeek, 0),
            stepDaysHit: stepDays,
            daysElapsed: days.count,
            averageProtein: average,
            milestone: reductionMilestone(
                today: today,
                calendar: calendar,
                programStartDate: programStartDate,
                reductionWeek: reductionWeek
            )
        )
    }

    static func reductionMilestone(
        today: Date,
        calendar: Calendar,
        programStartDate: String?,
        reductionWeek: Int?
    ) -> String? {
        guard let programStartDate,
              let reductionWeek,
              reductionWeek >= 1,
              let startParts = SessionDateFormatting.yearMonthDay(from: programStartDate),
              let programStart = date(from: startParts, calendar: calendar) else {
            return nil
        }
        guard let weekStart = calendar.date(byAdding: .day, value: 7 * (reductionWeek - 1), to: programStart),
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return nil
        }
        let todayParts = SessionDateFormatting.yearMonthDay(
            from: SessionDateFormatting.calendarDateString(from: today, calendar: calendar)
        )
        let startYMD = SessionDateFormatting.yearMonthDay(
            from: SessionDateFormatting.calendarDateString(from: weekStart, calendar: calendar)
        )
        let endYMD = SessionDateFormatting.yearMonthDay(
            from: SessionDateFormatting.calendarDateString(from: weekEnd, calendar: calendar)
        )
        guard let todayParts, let startYMD, let endYMD else { return nil }
        if compare(todayParts, startYMD) == .orderedAscending {
            return "Deload Week \(monthDay(weekStart, calendar: calendar))"
        }
        if compare(todayParts, endYMD) != .orderedDescending {
            return "Deload Week this week (\(monthDay(weekStart, calendar: calendar))–\(monthDay(weekEnd, calendar: calendar)))"
        }
        return nil
    }

    static func storedNumber(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1_000_000 {
            return String(Int(value))
        }
        var text = String(format: "%.4f", value)
        while text.contains("."), text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    static func newYorkDateString(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        return SessionDateFormatting.calendarDateString(from: date, calendar: calendar)
    }

    static func iso8601NewYork(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = newYork
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func displayNewYork(iso8601 raw: String) -> String? {
        guard let date = parseISO8601(raw) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = newYork
        formatter.dateFormat = "EEE h:mm a"
        return formatter.string(from: date)
    }

    static let newYork = TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: 0)!

    private static func dailyLatest(_ samples: [DatedValue], calendar: Calendar) -> [Date: Double] {
        var latest: [Date: DatedValue] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            if let existing = latest[day], existing.date > sample.date { continue }
            latest[day] = DatedValue(date: sample.date, value: sample.value)
        }
        return latest.mapValues(\.value)
    }

    private static func mean(daily: [Date: Double], ending: Date, days: Int, calendar: Calendar) -> Double? {
        let keys = dayKeys(ending: ending, days: days, calendar: calendar)
        let values = keys.compactMap { daily[$0] }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func sparkline(daily: [Date: Double], ending: Date, days: Int, calendar: Calendar) -> [DatedValue] {
        dayKeys(ending: ending, days: days, calendar: calendar).compactMap { day in
            daily[day].map { DatedValue(date: day, value: $0) }
        }
    }

    private static func dayKeys(ending: Date, days: Int, calendar: Calendar) -> [Date] {
        let count = max(days, 1)
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: -(count - 1 - offset), to: ending)
        }
    }

    private static func elapsedCivilDates(through today: Date, calendar: Calendar) -> [String] {
        let end = calendar.startOfDay(for: today)
        let weekday = calendar.component(.weekday, from: end)
        let first = calendar.firstWeekday
        let daysBack = (weekday - first + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -daysBack, to: end) else { return [] }
        var dates: [String] = []
        var cursor = start
        while cursor <= end {
            dates.append(SessionDateFormatting.calendarDateString(from: cursor, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return dates
    }

    private static func date(
        from parts: (year: Int, month: Int, day: Int),
        calendar: Calendar
    ) -> Date? {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = parts.year
        components.month = parts.month
        components.day = parts.day
        components.hour = 12
        return calendar.date(from: components)
    }

    private static func monthDay(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private static func compare(
        _ lhs: (year: Int, month: Int, day: Int),
        _ rhs: (year: Int, month: Int, day: Int)
    ) -> ComparisonResult {
        if lhs.year != rhs.year { return lhs.year < rhs.year ? .orderedAscending : .orderedDescending }
        if lhs.month != rhs.month { return lhs.month < rhs.month ? .orderedAscending : .orderedDescending }
        if lhs.day != rhs.day { return lhs.day < rhs.day ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
