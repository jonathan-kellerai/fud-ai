import Charts
import SwiftUI

enum ProgressTrainingChartMetric: String, CaseIterable, Hashable {
    case sessions
    case sets
    case volume

    var title: String {
        switch self {
        case .sessions: String(localized: "Sessions")
        case .sets: String(localized: "Sets")
        case .volume: String(localized: "Volume")
        }
    }
}

/// Sessions, sets and volume per Monday–Sunday week from the Neon bridge.
struct ProgressTrainingCard: View {
    let state: ProgressTrainingLoadState
    let rangeDescription: String
    let useMetric: Bool
    let onRetry: () -> Void

    @State private var chartMetric: ProgressTrainingChartMetric = .sessions
    @ScaledMetric(relativeTo: .body) private var scaledHeight: CGFloat = 180

    private var chartHeight: CGFloat { min(max(scaledHeight, 170), 280) }
    private var volumeUnit: String { useMetric ? "kg" : "lb" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressV2SectionTitle(
                title: String(localized: "Training"),
                detail: String(localized: "Completed sessions from the Neon bridge · weeks run Monday–Sunday (Eastern)")
            )

            switch state {
            case .idle, .loading:
                ProgressV2LoadingRow(title: String(localized: "Loading training from the Neon bridge…"))
            case .notConfigured:
                ProgressV2EmptyState(
                    title: String(localized: "Neon bridge not set up"),
                    message: String(localized: "Add the bridge URL in More › Neon Bridge to see sessions, sets and volume."),
                    systemImage: "link"
                )
            case .failed(let message):
                ProgressV2EmptyState(
                    title: String(localized: "Couldn't reach the bridge"),
                    message: message,
                    systemImage: "exclamationmark.triangle"
                )
                Button(action: onRetry) {
                    Label(String(localized: "Retry"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(IronCompactButtonStyle())
            case .loaded(let summary):
                if summary.isEmpty {
                    ProgressV2EmptyState(
                        title: String(localized: "No completed workouts in \(rangeDescription)"),
                        message: String(localized: "Workouts saved from the Train tab show up here once they reach the Neon bridge."),
                        systemImage: "dumbbell"
                    )
                    notes(summary)
                } else {
                    loaded(summary)
                }
            }
        }
        .padding(14)
        .ironCard()
    }

    @ViewBuilder
    private func loaded(_ summary: ProgressTrainingSummary) -> some View {
        ProgressV2StatGrid(stats: [
            ProgressV2Stat(label: String(localized: "Sessions"), value: ProgressV2Format.integer(summary.totalSessions)),
            ProgressV2Stat(
                label: String(localized: "Per Week"),
                value: summary.averageSessionsPerWeek.map { ProgressV2Format.number($0) } ?? ProgressV2Format.dash,
                accessibilityValue: summary.averageSessionsPerWeek.map { String(localized: "\(ProgressV2Format.number($0)) sessions per week") }
            ),
            ProgressV2Stat(
                label: String(localized: "Sets"),
                value: summary.totalSets.map { ProgressV2Format.integer($0) } ?? ProgressV2Format.dash
            ),
            ProgressV2Stat(
                label: String(localized: "Volume"),
                value: summary.totalVolumeLb.map { volumeText($0) } ?? ProgressV2Format.dash
            ),
        ])

        ProgressV2SegmentedControl(
            options: ProgressTrainingChartMetric.allCases,
            selection: $chartMetric,
            label: { $0.title },
            accessibilityLabel: String(localized: "Training chart metric"),
            accessibilityColumns: 1
        )

        let bars = chartBars(summary)
        if bars.isEmpty {
            ProgressV2EmptyState(
                title: String(localized: "No \(chartMetric.title.lowercased()) data for these weeks"),
                message: String(localized: "Sets for these sessions haven't loaded from the bridge."),
                systemImage: "chart.bar"
            )
        } else {
            Chart {
                ForEach(bars) { bar in
                    BarMark(
                        x: .value("Week", bar.date, unit: .weekOfYear),
                        y: .value("Value", bar.value)
                    )
                    .foregroundStyle(IronTheme.blood)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                        .foregroundStyle(IronTheme.hairline)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
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
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "\(chartMetric.title) per week chart"))
            .accessibilityValue(accessibilitySummary(bars))
        }

        notes(summary)
    }

    @ViewBuilder
    private func notes(_ summary: ProgressTrainingSummary) -> some View {
        let lines = noteLines(summary)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(IronTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func noteLines(_ summary: ProgressTrainingSummary) -> [String] {
        var lines: [String] = []
        if summary.isTruncated {
            lines.append(String(localized: "Showing the most recent \(summary.weeks.count) of \(summary.weeksInRange) weeks in this range."))
        }
        if summary.listTruncated {
            if let cutoff = summary.sessionListCutoff {
                let date = Self.localDate(forDayKey: cutoff).map { ProgressV2Format.mediumDate($0) } ?? cutoff
                lines.append(String(localized: "Showing the \(ProgressTrainingMath.workoutListLimit) most recent sessions, back to \(date)."))
            } else {
                lines.append(String(localized: "Showing the \(ProgressTrainingMath.workoutListLimit) most recent sessions."))
            }
        }
        if summary.isDetailLimited {
            lines.append(String(localized: "Sets & volume: last \(summary.detailSessions) sessions."))
        }
        if summary.failedDetails > 0 {
            lines.append(String(localized: "Sets and volume didn't load for \(summary.failedDetails) sessions. Pull to refresh to retry."))
        }
        return lines
    }

    private struct WeekBar: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    private func chartBars(_ summary: ProgressTrainingSummary) -> [WeekBar] {
        summary.weeks.compactMap { week -> WeekBar? in
            guard let date = Self.localDate(forDayKey: week.weekStart) else { return nil }
            switch chartMetric {
            case .sessions:
                return WeekBar(date: date, value: Double(week.sessions))
            case .sets:
                return week.sets.map { WeekBar(date: date, value: Double($0)) }
            case .volume:
                return week.volumeLb.map { WeekBar(date: date, value: displayVolume($0)) }
            }
        }
    }

    private func displayVolume(_ pounds: Double) -> Double {
        useMetric ? pounds / ProgressV2Math.poundsPerKilogram : pounds
    }

    private func volumeText(_ pounds: Double) -> String {
        "\(displayVolume(pounds).formatted(.number.precision(.fractionLength(0)))) \(volumeUnit)"
    }

    private func barText(_ value: Double) -> String {
        switch chartMetric {
        case .sessions: String(localized: "\(ProgressV2Format.integer(Int(value))) sessions")
        case .sets: String(localized: "\(ProgressV2Format.integer(Int(value))) sets")
        case .volume: "\(value.formatted(.number.precision(.fractionLength(0)))) \(volumeUnit)"
        }
    }

    private func accessibilitySummary(_ bars: [WeekBar]) -> String {
        bars.suffix(8).map { bar in
            String(localized: "Week of \(ProgressV2Format.shortDate(bar.date)): \(barText(bar.value))")
        }
        .joined(separator: ". ")
    }

    /// YYYY-MM-DD as a local-calendar date for plotting.
    static func localDate(forDayKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
