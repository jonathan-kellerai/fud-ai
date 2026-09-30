import Foundation

enum ProgressCompositionMetric: String, CaseIterable, Identifiable, Hashable {
    case weight
    case bodyFat
    case leanMass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: String(localized: "Weight")
        case .bodyFat: String(localized: "Body Fat")
        case .leanMass: String(localized: "Lean Mass")
        }
    }
}

/// Everything the composition card and summary card draw for one range.
/// Mass values are in the display unit; body fat is in percent (0–100).
struct ProgressCompositionSnapshot {
    let range: TimeRange
    let window: ProgressWindow
    let useMetric: Bool
    let weight: ProgressMetricSeries
    let bodyFat: ProgressMetricSeries
    let leanMass: ProgressMetricSeries
    let hasAnyWeight: Bool
    let hasAnyBodyFat: Bool
    let hasAnyLeanMass: Bool
    let latestWeight: ProgressSample?
    let latestBodyFat: ProgressSample?
    let latestLeanMass: ProgressSample?
    let latestLeanMassSource: String?
    /// Kilograms and a fraction; converted for display by the card.
    let derivedFatMass: ProgressDerivedFatMass?

    func series(for metric: ProgressCompositionMetric) -> ProgressMetricSeries {
        switch metric {
        case .weight: weight
        case .bodyFat: bodyFat
        case .leanMass: leanMass
        }
    }

    func hasAny(_ metric: ProgressCompositionMetric) -> Bool {
        switch metric {
        case .weight: hasAnyWeight
        case .bodyFat: hasAnyBodyFat
        case .leanMass: hasAnyLeanMass
        }
    }
}

enum ProgressCompositionBuilder {
    /// Earliest reading across weight, lean mass and body fat, for the All range.
    static func earliestDate(weightRows: [WeightEntry], bodyFatRows: [BodyFatEntry]) -> Date? {
        let weightEarliest = weightRows.map(\.date).min()
        let fatEarliest = bodyFatRows.map(\.date).min()
        switch (weightEarliest, fatEarliest) {
        case let (weight?, fat?): return min(weight, fat)
        case let (weight?, nil): return weight
        case let (nil, fat?): return fat
        case (nil, nil): return nil
        }
    }

    /// Hash over every weight and body-fat row (id, date, value, lean-mass
    /// flag, Health source), so an edit anywhere in history changes it. The
    /// source feeds the lean mass caption. One O(n) pass.
    static func fingerprint(weightRows: [WeightEntry], bodyFatRows: [BodyFatEntry]) -> Int {
        var hasher = Hasher()
        hasher.combine(weightRows.count)
        for row in weightRows {
            hasher.combine(row.id)
            hasher.combine(row.date.timeIntervalSinceReferenceDate)
            hasher.combine(row.weightKg)
            hasher.combine(row.isLeanBodyMass)
            hasher.combine(row.healthSourceName)
        }
        hasher.combine(bodyFatRows.count)
        for row in bodyFatRows {
            hasher.combine(row.id)
            hasher.combine(row.date.timeIntervalSinceReferenceDate)
            hasher.combine(row.bodyFatFraction)
        }
        return hasher.finalize()
    }

    static func build(
        weightRows: [WeightEntry],
        bodyFatRows: [BodyFatEntry],
        range: TimeRange,
        useMetric: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ProgressCompositionSnapshot {
        let window = ProgressV2Math.window(
            for: range,
            now: now,
            calendar: calendar,
            earliestData: earliestDate(weightRows: weightRows, bodyFatRows: bodyFatRows)
        )
        let bodyRows = ProgressBodyRows.bodyWeight(weightRows)
        let leanRows = ProgressBodyRows.leanMass(weightRows)
        let fatRows = bodyFatRows.sorted { $0.date < $1.date }

        let weightSamples = bodyRows.map {
            ProgressSample(date: $0.date, value: ProgressV2Math.displayMass(kg: $0.weightKg, useMetric: useMetric))
        }
        let leanSamples = leanRows.map {
            ProgressSample(date: $0.date, value: ProgressV2Math.displayMass(kg: $0.weightKg, useMetric: useMetric))
        }
        let fatPercentSamples = fatRows.map { ProgressSample(date: $0.date, value: $0.bodyFatFraction * 100) }

        let derived = ProgressV2Math.derivedFatMass(
            weightsKg: bodyRows.map { ProgressSample(date: $0.date, value: $0.weightKg) },
            bodyFatFractions: fatRows.map { ProgressSample(date: $0.date, value: $0.bodyFatFraction) },
            calendar: calendar
        )

        return ProgressCompositionSnapshot(
            range: range,
            window: window,
            useMetric: useMetric,
            weight: ProgressV2Math.series(samples: weightSamples, window: window, calendar: calendar),
            bodyFat: ProgressV2Math.series(samples: fatPercentSamples, window: window, calendar: calendar),
            leanMass: ProgressV2Math.series(samples: leanSamples, window: window, calendar: calendar),
            hasAnyWeight: !bodyRows.isEmpty,
            hasAnyBodyFat: !fatRows.isEmpty,
            hasAnyLeanMass: !leanRows.isEmpty,
            latestWeight: weightSamples.last,
            latestBodyFat: fatPercentSamples.last,
            latestLeanMass: leanSamples.last,
            latestLeanMassSource: leanRows.last?.healthSourceName,
            derivedFatMass: derived
        )
    }
}

/// Fixed data for snapshot tests. Nothing here touches HealthKit or the network.
/// `now`, `calendar` and `locale` pin every window and label the tab computes,
/// so the fixture builders and the view agree on "today".
struct ProgressV2Fixture {
    var timeRange: TimeRange = .month
    var metric: ProgressCompositionMetric = .weight
    var weightEntries: [WeightEntry]
    var bodyFatEntries: [BodyFatEntry]
    /// Nil renders the "Health unavailable" state.
    var stepsByDay: [Date: Int]?
    var training: ProgressTrainingLoadState
    var now: Date = .now
    var calendar: Calendar = .current
    var locale: Locale = .current
}
