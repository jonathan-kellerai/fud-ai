import Charts
import SwiftUI

/// Weight | Body Fat | Lean Mass. Stats and chart come from a precomputed
/// snapshot, so switching metrics never recomputes anything in `body`.
struct ProgressCompositionCard: View {
    @Binding var metric: ProgressCompositionMetric
    let snapshot: ProgressCompositionSnapshot?
    let goalWeightKg: Double?
    let goalBodyFatFraction: Double?
    let onLogWeight: () -> Void
    let onLogBodyFat: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressV2SectionTitle(title: String(localized: "Body Composition"))

            ProgressV2SegmentedControl(
                options: ProgressCompositionMetric.allCases,
                selection: $metric,
                label: { $0.title },
                accessibilityLabel: String(localized: "Body composition metric"),
                accessibilityColumns: 1
            )

            if let snapshot {
                content(snapshot)
            } else {
                ProgressV2LoadingRow(title: String(localized: "Loading body composition…"))
            }

            actions
        }
        .padding(14)
        .ironCard()
    }

    @ViewBuilder
    private func content(_ snapshot: ProgressCompositionSnapshot) -> some View {
        let series = snapshot.series(for: metric)
        if series.isEmpty {
            emptyState(snapshot)
        } else {
            ProgressV2StatGrid(stats: stats(series.stats, snapshot: snapshot))

            ProgressCompositionChart(
                series: series,
                metric: metric,
                window: snapshot.window,
                rangeDescription: snapshot.range.rangeDescription,
                unit: unit(snapshot),
                goal: goal(snapshot)
            )

            Text(footnote(series))
                .font(.footnote)
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch metric {
        case .weight:
            Button(action: onLogWeight) {
                Label(String(localized: "Log Weight"), systemImage: "plus")
            }
            .buttonStyle(IronCompactButtonStyle())
        case .bodyFat:
            Button(action: onLogBodyFat) {
                Label(String(localized: "Log Body Fat"), systemImage: "plus")
            }
            .buttonStyle(IronCompactButtonStyle())
        case .leanMass:
            Text("Lean mass is measured by your scale and read from Apple Health. It can't be entered by hand.")
                .font(.footnote)
                .foregroundStyle(IronTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Stats

    private func unit(_ snapshot: ProgressCompositionSnapshot) -> String {
        switch metric {
        case .weight, .leanMass: snapshot.useMetric ? "kg" : "lb"
        case .bodyFat: "%"
        }
    }

    private func spokenUnit(_ snapshot: ProgressCompositionSnapshot) -> String {
        switch metric {
        case .weight, .leanMass:
            snapshot.useMetric ? String(localized: "kilograms") : String(localized: "pounds")
        case .bodyFat:
            String(localized: "percentage points")
        }
    }

    private func goal(_ snapshot: ProgressCompositionSnapshot) -> Double? {
        switch metric {
        case .weight:
            goalWeightKg.map { ProgressV2Math.displayMass(kg: $0, useMetric: snapshot.useMetric) }
        case .bodyFat:
            goalBodyFatFraction.map { $0 * 100 }
        case .leanMass:
            nil
        }
    }

    private func stats(_ stats: ProgressMetricStats, snapshot: ProgressCompositionSnapshot) -> [ProgressV2Stat] {
        let unitText = unit(snapshot)
        let spoken = spokenUnit(snapshot)
        let notEnough = String(localized: "Not enough readings yet")
        let rateValue: String
        let rateSpoken: String
        if let rate = stats.weeklyRate {
            let perWeek = metric == .bodyFat ? String(localized: "pts/wk") : "\(unitText)/wk"
            rateValue = "\(ProgressV2Format.signed(rate, locale: locale)) \(perWeek)"
            rateSpoken = String(localized: "\(ProgressV2Format.signed(rate, locale: locale)) \(spoken) per week")
        } else {
            rateValue = ProgressV2Format.dash
            rateSpoken = notEnough
        }

        let current: String
        let average: String
        let net: String
        switch metric {
        case .weight, .leanMass:
            current = ProgressV2Format.mass(stats.current, unit: unitText, locale: locale)
            average = ProgressV2Format.mass(stats.average, unit: unitText, locale: locale)
            net = ProgressV2Format.signedMass(stats.netChange, unit: unitText, locale: locale)
        case .bodyFat:
            current = ProgressV2Format.percent(stats.current, locale: locale)
            average = ProgressV2Format.percent(stats.average, locale: locale)
            net = stats.netChange.map { "\(ProgressV2Format.signed($0, locale: locale)) \(String(localized: "pts"))" } ?? ProgressV2Format.dash
        }
        return [
            ProgressV2Stat(label: String(localized: "Current"), value: current),
            ProgressV2Stat(
                label: String(localized: "Net Change"),
                value: net,
                accessibilityValue: stats.netChange == nil ? notEnough : "\(net), \(spoken)"
            ),
            ProgressV2Stat(label: String(localized: "Average"), value: average),
            ProgressV2Stat(label: String(localized: "Rate"), value: rateValue, accessibilityValue: rateSpoken),
        ]
    }

    private func footnote(_ series: ProgressMetricSeries) -> String {
        let days = series.daily.count
        let readings = series.readingCount
        return String(localized: "\(readings) readings on \(days) days. Dots are daily averages; the line is a 7-day moving average. Rate is the trend's slope per week.")
    }

    // MARK: - Empty states

    @ViewBuilder
    private func emptyState(_ snapshot: ProgressCompositionSnapshot) -> some View {
        let range = snapshot.range.rangeDescription
        let hasAny = snapshot.hasAny(metric)
        switch metric {
        case .weight:
            if hasAny {
                ProgressV2EmptyState(
                    title: String(localized: "No weight readings in \(range)"),
                    message: String(localized: "Pick a longer range, or log today's weight."),
                    systemImage: "scalemass"
                )
            } else {
                ProgressV2EmptyState(
                    title: String(localized: "No weight logged yet"),
                    message: String(localized: "Log your weight to start a 7-day trend."),
                    systemImage: "scalemass"
                )
            }
        case .bodyFat:
            if hasAny {
                ProgressV2EmptyState(
                    title: String(localized: "No body fat readings in \(range)"),
                    message: String(localized: "Pick a longer range, or log a reading."),
                    systemImage: "percent"
                )
            } else {
                ProgressV2EmptyState(
                    title: String(localized: "No body fat readings yet"),
                    message: String(localized: "Log body fat % here, or let a smart scale write Body Fat Percentage to Apple Health."),
                    systemImage: "percent"
                )
            }
        case .leanMass:
            if hasAny {
                ProgressV2EmptyState(
                    title: String(localized: "No lean mass readings in \(range)"),
                    message: latestLeanMassMessage(snapshot),
                    systemImage: "figure.strengthtraining.traditional"
                )
            } else {
                ProgressV2EmptyState(
                    title: String(localized: "No lean mass data yet"),
                    message: String(localized: "Lean mass comes from the Withings scale through Apple Health (Lean Body Mass). In the Health app, allow Withings to write Lean Body Mass and allow JL Physical to read it, then weigh in on the scale."),
                    systemImage: "figure.strengthtraining.traditional"
                )
            }
        }
    }

    private func latestLeanMassMessage(_ snapshot: ProgressCompositionSnapshot) -> String {
        guard let latest = snapshot.latestLeanMass else {
            return String(localized: "Pick a longer range to see older readings.")
        }
        let value = ProgressV2Format.mass(latest.value, unit: snapshot.useMetric ? "kg" : "lb", locale: locale)
        let date = ProgressV2Format.mediumDate(latest.date, locale: locale, calendar: calendar, timeZone: timeZone)
        return String(localized: "The latest lean mass reading is \(value) on \(date). Pick a longer range to see it.")
    }
}

// MARK: - Chart

struct ProgressCompositionChart: View {
    let series: ProgressMetricSeries
    let metric: ProgressCompositionMetric
    let window: ProgressWindow
    let rangeDescription: String
    let unit: String
    let goal: Double?

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @ScaledMetric(relativeTo: .body) private var scaledHeight: CGFloat = 210

    private var chartHeight: CGFloat { min(max(scaledHeight, 200), 320) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(series.plottedDaily) { point in
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Daily average", point.value)
                    )
                    .foregroundStyle(IronTheme.textSecondary.opacity(0.8))
                    .symbolSize(series.plottedDaily.count > 60 ? 12 : 26)
                }

                ForEach(series.plottedTrend) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("7-day average", point.value)
                    )
                    .foregroundStyle(IronTheme.bloodText)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }

                if let goal {
                    RuleMark(y: .value("Goal", goal))
                        .foregroundStyle(IronTheme.olive)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
            }
            .chartXScale(domain: window.closedRange)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                        .foregroundStyle(IronTheme.hairline)
                    AxisValueLabel(format: xLabelFormat)
                        .foregroundStyle(IronTheme.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(IronTheme.hairline)
                    AxisValueLabel()
                        .foregroundStyle(IronTheme.textSecondary)
                }
            }
            .frame(height: chartHeight)
            // Axis labels in a fixed-height plot overlap at accessibility
            // sizes; cap only the chart's type size, like the old charts.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "\(metric.title) chart"))
            .accessibilityValue(accessibilitySummary)

            legend
        }
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { legendItems }
            VStack(alignment: .leading, spacing: 4) { legendItems }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var legendItems: some View {
        ProgressV2LegendItem(title: String(localized: "Daily average"), color: IronTheme.textSecondary)
        ProgressV2LegendItem(title: String(localized: "7-day trend"), color: IronTheme.bloodText, isLine: true)
        if goal != nil {
            ProgressV2LegendItem(title: String(localized: "Goal"), color: IronTheme.olive, isLine: true)
        }
    }

    private var yDomain: ClosedRange<Double> {
        var values = series.plottedDaily.map(\.value) + series.plottedTrend.map(\.value)
        if let goal { values.append(goal) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let minimumPadding: Double = metric == .bodyFat ? 1 : (unit == "kg" ? 1 : 2)
        let padding = max((high - low) * 0.15, minimumPadding)
        let lower = metric == .bodyFat ? max(0, low - padding) : low - padding
        return lower...(high + padding)
    }

    private var xLabelFormat: Date.FormatStyle {
        let spanDays = window.dayCount(calendar: calendar)
        let lastDay = window.closedRange.upperBound
        if spanDays > 150, !calendar.isDate(window.start, equalTo: lastDay, toGranularity: .year) {
            return .dateTime.month(.abbreviated).year(.twoDigits)
        }
        return .dateTime.month(.abbreviated).day()
    }

    private var accessibilitySummary: String {
        guard let first = series.daily.first, let last = series.daily.last else {
            return String(localized: "No readings")
        }
        let values = series.daily.map(\.value)
        let low = values.min() ?? last.value
        let high = values.max() ?? last.value
        let format: (Double) -> String = { value in
            unit == "%" ? ProgressV2Format.percent(value, locale: locale) : ProgressV2Format.mass(value, unit: unit, locale: locale)
        }
        let firstDate = ProgressV2Format.mediumDate(first.date, locale: locale, calendar: calendar, timeZone: timeZone)
        let lastDate = ProgressV2Format.mediumDate(last.date, locale: locale, calendar: calendar, timeZone: timeZone)
        var parts = [
            String(localized: "\(series.daily.count) days with readings in \(rangeDescription), from \(firstDate) to \(lastDate)."),
            String(localized: "Lowest \(format(low)), highest \(format(high)).")
        ]
        if let trend = series.trend.last {
            parts.append(String(localized: "Latest 7-day average \(format(trend.value))."))
        }
        if let goal {
            parts.append(String(localized: "Goal \(format(goal))."))
        }
        return parts.joined(separator: " ")
    }
}
