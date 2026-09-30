import Charts
import SwiftUI

enum ProgressStepsLoadState {
    case loading
    /// Health is unavailable or the query failed (permission, no HealthKit).
    case unavailable
    case loaded(ProgressStepsSummary)
}

/// Daily steps from Apple Health against the 10,000 program goal.
struct ProgressStepsCard: View {
    let state: ProgressStepsLoadState
    let rangeDescription: String
    let goal: Int
    /// Says how far back the window reaches when it is bounded (All).
    var windowNote: String? = nil

    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @ScaledMetric(relativeTo: .body) private var scaledHeight: CGFloat = 190

    private var chartHeight: CGFloat { min(max(scaledHeight, 180), 300) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressV2SectionTitle(
                title: String(localized: "Steps"),
                detail: String(localized: "From Apple Health · goal \(ProgressV2Format.integer(goal, locale: locale)) a day")
            )

            switch state {
            case .loading:
                ProgressV2LoadingRow(title: String(localized: "Reading steps from Apple Health…"))
            case .unavailable:
                ProgressV2EmptyState(
                    title: String(localized: "Apple Health steps unavailable"),
                    message: String(localized: "Allow JL Physical to read Steps in the Health app (Sharing › Apps › JL Physical)."),
                    systemImage: "figure.walk"
                )
            case .loaded(let summary):
                if summary.isEmpty {
                    ProgressV2EmptyState(
                        title: String(localized: "No steps in \(rangeDescription)"),
                        message: String(localized: "Apple Health has no step counts for these days. If you carry your phone or wear a watch, check that JL Physical can read Steps in the Health app."),
                        systemImage: "figure.walk"
                    )
                } else {
                    loaded(summary)
                }
            }

            if let windowNote {
                Text(windowNote)
                    .font(.footnote)
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .ironCard()
    }

    @ViewBuilder
    private func loaded(_ summary: ProgressStepsSummary) -> some View {
        ProgressV2StatGrid(stats: [
            ProgressV2Stat(
                label: String(localized: "Days Met"),
                value: "\(summary.daysMet) / \(summary.trackedDays)",
                accessibilityValue: String(localized: "\(summary.daysMet) of \(summary.trackedDays) tracked days at or above \(ProgressV2Format.integer(goal, locale: locale)) steps")
            ),
            ProgressV2Stat(
                label: String(localized: "Daily Average"),
                value: summary.dailyAverage.map { ProgressV2Format.integer($0, locale: locale) } ?? ProgressV2Format.dash
            ),
        ])

        let maxSteps = summary.bars.map(\.steps).max() ?? 0
        let yUpper = Double(max(goal, maxSteps)) * 1.12
        let axisFormat: Date.FormatStyle = summary.isWeekly
            ? .dateTime.month(.abbreviated).year(.twoDigits)
            : .dateTime.month(.abbreviated).day()

        Chart {
            ForEach(summary.bars) { bar in
                BarMark(
                    x: .value("Date", bar.date, unit: summary.isWeekly ? .weekOfYear : .day),
                    y: .value("Steps", bar.steps)
                )
                .foregroundStyle(bar.steps >= goal ? IronTheme.olive : IronTheme.blood)
            }

            RuleMark(y: .value("Goal", goal))
                .foregroundStyle(IronTheme.brass)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("\(ProgressV2Format.integer(goal, locale: locale)) goal")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(IronTheme.brass)
                }
        }
        .chartYScale(domain: 0...yUpper)
        .chartXAxis {
            ProgressV2DateAxis.marks(format: axisFormat)
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
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Steps chart"))
        .accessibilityValue(accessibilitySummary(summary))

        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { legendItems }
            VStack(alignment: .leading, spacing: 4) { legendItems }
        }
        .accessibilityHidden(true)

        Text(summary.isWeekly
             ? String(localized: "Bars are weekly averages of tracked days. Days met counts individual days.")
             : String(localized: "Days with no steps in Apple Health are not counted."))
            .font(.footnote)
            .foregroundStyle(IronTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var legendItems: some View {
        ProgressV2LegendItem(title: String(localized: "Goal met"), color: IronTheme.olive)
        ProgressV2LegendItem(title: String(localized: "Under goal"), color: IronTheme.blood)
        ProgressV2LegendItem(title: String(localized: "Goal"), color: IronTheme.brass, isLine: true)
    }

    private func accessibilitySummary(_ summary: ProgressStepsSummary) -> String {
        var parts = [
            String(localized: "\(summary.daysMet) of \(summary.trackedDays) tracked days met the goal in \(rangeDescription).")
        ]
        if let average = summary.dailyAverage {
            parts.append(String(localized: "Daily average \(ProgressV2Format.integer(average, locale: locale)) steps."))
        }
        if let best = summary.bars.max(by: { $0.steps < $1.steps }) {
            let when = ProgressV2Format.mediumDate(best.date, locale: locale, calendar: calendar, timeZone: timeZone)
            let steps = ProgressV2Format.integer(best.steps, locale: locale)
            parts.append(summary.isWeekly
                ? String(localized: "Best week, starting \(when): \(steps) a day.")
                : String(localized: "Best day \(when): \(steps) steps."))
        }
        return parts.joined(separator: " ")
    }
}
