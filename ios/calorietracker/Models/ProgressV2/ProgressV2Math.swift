import Foundation

/// One raw reading in display units (lb/kg, or percent for body fat).
nonisolated struct ProgressSample: Equatable, Sendable {
    let date: Date
    let value: Double
}

/// One plotted or aggregated point. Daily means sit at the start of their day;
/// downsampled buckets sit at the mean date of the days they average.
nonisolated struct ProgressPoint: Equatable, Sendable, Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Local-day window for a Progress range. `endExclusive` is the start of
/// tomorrow, so everything logged today is inside the window.
nonisolated struct ProgressWindow: Equatable, Sendable {
    let start: Date
    let endExclusive: Date

    func contains(_ date: Date) -> Bool {
        date >= start && date < endExclusive
    }

    /// Same shape as `TimeRange.dateRange()` for APIs that take a closed range.
    var closedRange: ClosedRange<Date> {
        start...max(start, endExclusive.addingTimeInterval(-1))
    }

    func dayCount(calendar: Calendar) -> Int {
        max(1, calendar.dateComponents([.day], from: start, to: endExclusive).day ?? 1)
    }
}

/// Current / Net Change / Average / Rate for one metric in one window.
nonisolated struct ProgressMetricStats: Equatable, Sendable {
    /// Latest raw reading in the window.
    let current: Double?
    /// Last daily mean minus first daily mean. Nil with fewer than two days.
    let netChange: Double?
    /// Mean of the daily means, so a day with five readings counts once.
    let average: Double?
    /// Units per week from the trend slope. Nil when the data is too thin.
    let weeklyRate: Double?

    static let empty = ProgressMetricStats(current: nil, netChange: nil, average: nil, weeklyRate: nil)
}

/// Full-resolution daily data for stats plus downsampled copies for the chart.
nonisolated struct ProgressMetricSeries: Equatable, Sendable {
    let daily: [ProgressPoint]
    let trend: [ProgressPoint]
    let plottedDaily: [ProgressPoint]
    let plottedTrend: [ProgressPoint]
    let stats: ProgressMetricStats
    let readingCount: Int

    var isEmpty: Bool { daily.isEmpty }

    static let empty = ProgressMetricSeries(
        daily: [],
        trend: [],
        plottedDaily: [],
        plottedTrend: [],
        stats: .empty,
        readingCount: 0
    )
}

/// Weight × body fat from a weight and a body-fat reading taken on the same
/// local day. Never built from readings on different days.
nonisolated struct ProgressDerivedFatMass: Equatable, Sendable {
    let day: Date
    let weightKg: Double
    let bodyFatFraction: Double

    var fatMassKg: Double { weightKg * bodyFatFraction }
}

nonisolated struct ProgressStepsBar: Equatable, Sendable, Identifiable {
    let date: Date
    let steps: Int
    var id: Date { date }
}

nonisolated struct ProgressStepsSummary: Equatable, Sendable {
    /// Daily totals, or weekly averages of tracked days when `isWeekly`.
    let bars: [ProgressStepsBar]
    let daysMet: Int
    /// Days in the window with a step count above zero.
    let trackedDays: Int
    let dailyAverage: Int?
    let isWeekly: Bool

    var isEmpty: Bool { trackedDays == 0 }
}

nonisolated enum ProgressV2Math {
    static let poundsPerKilogram = 2.20462
    static let trendWindowDays = 7
    static let maxPlottedPoints = 120
    static let minimumRatePoints = 3
    static let minimumRateSpanDays = 5

    // MARK: - Ranges

    /// Days covered by a bounded range; nil for All.
    static func boundedDays(_ range: TimeRange) -> Int? {
        range == .allTime ? nil : range.days
    }

    /// All starts at the earliest reading instead of assuming 3650 days is enough.
    /// Without any data, All is just today.
    static func window(
        for range: TimeRange,
        now: Date,
        calendar: Calendar,
        earliestData: Date?
    ) -> ProgressWindow {
        let startOfToday = calendar.startOfDay(for: now)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? startOfToday.addingTimeInterval(86_400)
        let start: Date
        if let days = boundedDays(range) {
            start = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) ?? startOfToday
        } else if let earliestData {
            start = min(calendar.startOfDay(for: earliestData), startOfToday)
        } else {
            start = startOfToday
        }
        return ProgressWindow(start: start, endExclusive: endExclusive)
    }

    static func filter(_ samples: [ProgressSample], in window: ProgressWindow) -> [ProgressSample] {
        samples
            .filter { window.contains($0.date) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Daily means and trend

    static func dailyMeans(_ samples: [ProgressSample], calendar: Calendar) -> [ProgressPoint] {
        var buckets: [Date: (sum: Double, count: Int)] = [:]
        for sample in samples where sample.value.isFinite {
            let day = calendar.startOfDay(for: sample.date)
            let bucket = buckets[day] ?? (0, 0)
            buckets[day] = (bucket.sum + sample.value, bucket.count + 1)
        }
        return buckets
            .sorted { $0.key < $1.key }
            .map { ProgressPoint(date: $0.key, value: $0.value.sum / Double($0.value.count)) }
    }

    /// Trailing moving average over calendar days, not over the last N points:
    /// the value on day D averages the daily means from D-6 through D. Days
    /// without data are skipped, never filled in.
    static func movingAverage(
        _ daily: [ProgressPoint],
        windowDays: Int = trendWindowDays,
        calendar: Calendar
    ) -> [ProgressPoint] {
        guard windowDays > 1 else { return daily }
        var result: [ProgressPoint] = []
        result.reserveCapacity(daily.count)
        var lower = 0
        for index in daily.indices {
            let day = calendar.startOfDay(for: daily[index].date)
            let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: day) ?? day
            while lower < index, daily[lower].date < windowStart {
                lower += 1
            }
            let slice = daily[lower...index]
            let mean = slice.reduce(0) { $0 + $1.value } / Double(slice.count)
            result.append(ProgressPoint(date: daily[index].date, value: mean))
        }
        return result
    }

    /// Least-squares slope of the trend in units per day, times 7. Nil with
    /// fewer than 3 daily points or when the points span fewer than 5 days.
    static func weeklyRate(_ trend: [ProgressPoint], calendar: Calendar) -> Double? {
        guard trend.count >= minimumRatePoints,
              let first = trend.first,
              let last = trend.last else { return nil }
        let firstDay = calendar.startOfDay(for: first.date)
        func dayOffset(_ date: Date) -> Double {
            Double(calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: date)).day ?? 0)
        }
        guard dayOffset(last.date) + 1 >= Double(minimumRateSpanDays) else { return nil }

        let xs = trend.map { dayOffset($0.date) }
        let ys = trend.map(\.value)
        let count = Double(trend.count)
        let meanX = xs.reduce(0, +) / count
        let meanY = ys.reduce(0, +) / count
        var numerator = 0.0
        var denominator = 0.0
        for index in xs.indices {
            let dx = xs[index] - meanX
            numerator += dx * (ys[index] - meanY)
            denominator += dx * dx
        }
        guard denominator > 0 else { return nil }
        let rate = numerator / denominator * 7
        return rate.isFinite ? rate : nil
    }

    // MARK: - Series

    /// Builds the chart + stats for one metric. The trend looks back six days
    /// before the window so the first trend point is a real 7-day average
    /// when older readings exist. Stats always use full-resolution data.
    static func series(
        samples: [ProgressSample],
        window: ProgressWindow,
        calendar: Calendar,
        maxPlotted: Int = maxPlottedPoints
    ) -> ProgressMetricSeries {
        let lookbackStart = calendar.date(byAdding: .day, value: -(trendWindowDays - 1), to: window.start) ?? window.start
        let usable = samples.filter { $0.value.isFinite && $0.date >= lookbackStart && $0.date < window.endExclusive }
        let allDaily = dailyMeans(usable, calendar: calendar)
        let allTrend = movingAverage(allDaily, calendar: calendar)

        let inWindow = filter(usable, in: window)
        let daily = allDaily.filter { window.contains($0.date) }
        let trend = allTrend.filter { window.contains($0.date) }
        guard !daily.isEmpty else { return .empty }

        let netChange: Double? = daily.count >= 2 ? (daily[daily.count - 1].value - daily[0].value) : nil
        let average = daily.reduce(0) { $0 + $1.value } / Double(daily.count)
        let stats = ProgressMetricStats(
            current: inWindow.last?.value,
            netChange: netChange,
            average: average,
            weeklyRate: weeklyRate(trend, calendar: calendar)
        )
        return ProgressMetricSeries(
            daily: daily,
            trend: trend,
            plottedDaily: downsample(daily, maxPoints: maxPlotted, calendar: calendar),
            plottedTrend: downsample(trend, maxPoints: maxPlotted, calendar: calendar),
            stats: stats,
            readingCount: inWindow.count
        )
    }

    // MARK: - Downsampling

    /// Bucket-averages a date-sorted series down to at most `maxPoints`, trying
    /// day, then week, then month, then multi-month buckets. The first and last
    /// points are always kept as-is. Small inputs pass through untouched.
    static func downsample(
        _ points: [ProgressPoint],
        maxPoints: Int = maxPlottedPoints,
        calendar: Calendar
    ) -> [ProgressPoint] {
        guard maxPoints >= 3, points.count > maxPoints,
              let first = points.first,
              let last = points.last else { return points }
        let interior = Array(points.dropFirst().dropLast())
        let budget = maxPoints - 2

        for component in [Calendar.Component.day, .weekOfYear, .month] {
            let buckets = bucketAverages(interior) { date in
                calendar.dateInterval(of: component, for: date)?.start ?? calendar.startOfDay(for: date)
            }
            if buckets.count <= budget {
                return [first] + buckets + [last]
            }
        }

        func monthIndex(_ date: Date) -> Int {
            let parts = calendar.dateComponents([.year, .month], from: date)
            return (parts.year ?? 0) * 12 + (parts.month ?? 1) - 1
        }
        guard let firstInterior = interior.first, let lastInterior = interior.last else { return [first, last] }
        let firstMonth = monthIndex(firstInterior.date)
        let months = monthIndex(lastInterior.date) - firstMonth + 1
        let monthsPerBucket = max(2, Int((Double(months) / Double(budget)).rounded(.up)))
        let buckets = bucketAverages(interior) { (monthIndex($0) - firstMonth) / monthsPerBucket }
        return [first] + buckets + [last]
    }

    /// Averages consecutive points that share a key. Input must be date-sorted
    /// and the key must not decrease with the date.
    private static func bucketAverages<Key: Equatable>(
        _ points: [ProgressPoint],
        key: (Date) -> Key
    ) -> [ProgressPoint] {
        var result: [ProgressPoint] = []
        var currentKey: Key?
        var dateSum = 0.0
        var valueSum = 0.0
        var count = 0
        for point in points {
            let pointKey = key(point.date)
            if let currentKey, currentKey != pointKey, count > 0 {
                result.append(ProgressPoint(
                    date: Date(timeIntervalSinceReferenceDate: dateSum / Double(count)),
                    value: valueSum / Double(count)
                ))
                dateSum = 0
                valueSum = 0
                count = 0
            }
            currentKey = pointKey
            dateSum += point.date.timeIntervalSinceReferenceDate
            valueSum += point.value
            count += 1
        }
        if count > 0 {
            result.append(ProgressPoint(
                date: Date(timeIntervalSinceReferenceDate: dateSum / Double(count)),
                value: valueSum / Double(count)
            ))
        }
        return result
    }

    // MARK: - Body composition

    /// Most recent local day that has both a weight and a body-fat reading.
    /// Uses the latest reading of each on that day. Returns nil when no day
    /// has both, so readings from different days are never combined.
    static func derivedFatMass(
        weightsKg: [ProgressSample],
        bodyFatFractions: [ProgressSample],
        calendar: Calendar
    ) -> ProgressDerivedFatMass? {
        func latestByDay(_ samples: [ProgressSample], valid: (Double) -> Bool) -> [Date: ProgressSample] {
            var byDay: [Date: ProgressSample] = [:]
            for sample in samples where sample.value.isFinite && valid(sample.value) {
                let day = calendar.startOfDay(for: sample.date)
                if let existing = byDay[day], existing.date >= sample.date { continue }
                byDay[day] = sample
            }
            return byDay
        }
        let weights = latestByDay(weightsKg) { $0 > 0 }
        let fats = latestByDay(bodyFatFractions) { $0 > 0 && $0 < 1 }
        let sharedDays = Set(weights.keys).intersection(fats.keys)
        guard let day = sharedDays.max(),
              let weight = weights[day],
              let fat = fats[day] else { return nil }
        return ProgressDerivedFatMass(day: day, weightKg: weight.value, bodyFatFraction: fat.value)
    }

    // MARK: - Steps

    /// Ranges longer than 3M draw weekly averages instead of one bar per day.
    static func usesWeeklyStepBars(_ range: TimeRange) -> Bool {
        switch range {
        case .week, .month, .threeMonths: false
        case .sixMonths, .year, .allTime: true
        }
    }

    /// Days met and the average always come from daily totals, even when the
    /// bars are weekly. Days at zero count as untracked (Health reports zero
    /// for days the phone recorded nothing).
    static func stepsSummary(
        byDay: [Date: Int],
        window: ProgressWindow,
        goal: Int,
        weekly: Bool,
        calendar: Calendar
    ) -> ProgressStepsSummary {
        var daily: [Date: Int] = [:]
        for (date, steps) in byDay where window.contains(date) && steps > 0 {
            daily[calendar.startOfDay(for: date), default: 0] += steps
        }
        let days = daily.keys.sorted()
        let daysMet = days.filter { (daily[$0] ?? 0) >= goal }.count
        let total = days.reduce(0) { $0 + (daily[$1] ?? 0) }
        let average: Int? = days.isEmpty ? nil : Int((Double(total) / Double(days.count)).rounded())

        let bars: [ProgressStepsBar]
        if weekly {
            var weeks: [Date: (sum: Int, count: Int)] = [:]
            for day in days {
                let week = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
                let bucket = weeks[week] ?? (0, 0)
                weeks[week] = (bucket.sum + (daily[day] ?? 0), bucket.count + 1)
            }
            bars = weeks
                .sorted { $0.key < $1.key }
                .map { ProgressStepsBar(date: $0.key, steps: Int((Double($0.value.sum) / Double($0.value.count)).rounded())) }
        } else {
            bars = days.map { ProgressStepsBar(date: $0, steps: daily[$0] ?? 0) }
        }
        return ProgressStepsSummary(
            bars: bars,
            daysMet: daysMet,
            trackedDays: days.count,
            dailyAverage: average,
            isWeekly: weekly
        )
    }

    // MARK: - Units

    static func displayMass(kg: Double, useMetric: Bool) -> Double {
        useMetric ? kg : kg * poundsPerKilogram
    }
}
