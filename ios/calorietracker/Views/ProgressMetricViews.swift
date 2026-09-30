import Charts
import SwiftUI

enum ProgressHistoryCountText {
    static func localized(_ count: Int) -> String {
        String(localized: "\(count) entry · tap to view or delete")
    }
}

struct WorkoutBurnDay: Identifiable, Equatable {
    let date: Date
    let calories: Int
    var id: Date { date }
}

enum WorkoutBurnAggregation {
    static let reliableCalories = 1...5_000

    static func isReliable(_ calories: Int?) -> Bool {
        guard let calories else { return false }
        return reliableCalories.contains(calories)
    }

    /// The burn calculator owns one estimate per diary day. Older data or a
    /// restore race can still contain duplicates, so choose the newest/highest
    /// sync-version record instead of summing and overstating the workout.
    static func daily(
        sessions: [StrengthWorkoutSession],
        in range: ClosedRange<Date>,
        calendar: Calendar = .current
    ) -> [WorkoutBurnDay] {
        var preferredByDay: [String: StrengthWorkoutSession] = [:]
        for session in sessions {
            guard isReliable(session.caloriesBurned) else { continue }
            let day = calendar.startOfDay(for: session.calendarDiaryDate)
            guard range.contains(day) else { continue }
            let key = session.stableDiaryDateKey
            if let current = preferredByDay[key], !shouldPrefer(session, over: current) { continue }
            preferredByDay[key] = session
        }
        return preferredByDay.values.compactMap { session in
            guard let calories = session.caloriesBurned else { return nil }
            return WorkoutBurnDay(
                date: calendar.startOfDay(for: session.calendarDiaryDate),
                calories: calories
            )
        }
        .sorted { $0.date < $1.date }
    }

    private static func shouldPrefer(
        _ candidate: StrengthWorkoutSession,
        over current: StrengthWorkoutSession
    ) -> Bool {
        let candidateVersion = candidate.healthSyncVersion ?? 0
        let currentVersion = current.healthSyncVersion ?? 0
        if candidateVersion != currentVersion { return candidateVersion > currentVersion }
        return candidate.completedAt > current.completedAt
    }
}

struct WorkoutBurnChartSection: View {
    let sessions: [StrengthWorkoutSession]
    let dateRange: ClosedRange<Date>

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var days: [WorkoutBurnDay] {
        WorkoutBurnAggregation.daily(sessions: sessions, in: dateRange)
    }

    private var total: Int { days.reduce(0) { $0 + $1.calories } }
    private var average: Int { days.isEmpty ? 0 : Int((Double(total) / Double(days.count)).rounded()) }
    private var latest: Int { days.last?.calories ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressV2SectionTitle(title: String(localized: "Calculated Workout Burn"))

            if days.isEmpty {
                ProgressMetricEmptyState("No calculated workout burn in this range")
            } else {
                workoutStatBadges

                Chart(days) { day in
                    BarMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("Calculated calories burned", day.calories)
                    )
                    .foregroundStyle(IronTheme.blood)
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
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(IronTheme.hairline)
                        AxisValueLabel()
                            .foregroundStyle(IronTheme.textSecondary)
                    }
                }
                .frame(height: 190)
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Calculated workout burn chart"))
                .accessibilityValue(String(localized: "\(days.count) days, \(total.formatted()) kilocalories total, average \(average.formatted())."))
            }

            Text("Only workout burns calculated in JL Physical are shown. Workouts without a burn estimate are not included.")
                .font(.caption)
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .progressMetricCardStyle()
    }

    @ViewBuilder
    private var workoutStatBadges: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                workoutStatBadgeContent
            }
        } else {
            HStack(spacing: 8) {
                workoutStatBadgeContent
            }
        }
    }

    @ViewBuilder
    private var workoutStatBadgeContent: some View {
        StatBadge(label: "Total", value: "\(total.formatted()) kcal")
        StatBadge(label: "Average", value: "\(average.formatted()) kcal")
        StatBadge(label: "Latest", value: "\(latest.formatted()) kcal")
        StatBadge(label: "Days", value: days.count.formatted())
    }
}

struct ImportedHealthWorkoutDay: Identifiable, Equatable {
    let date: Date
    let sessionCount: Int
    let totalCalories: Int
    var id: Date { date }
}

enum ImportedHealthWorkoutAggregation {
    static func daily(
        workouts: [ImportedHealthWorkout],
        in range: ClosedRange<Date>,
        calendar: Calendar = .current
    ) -> [ImportedHealthWorkoutDay] {
        var grouped: [String: (date: Date, count: Int, calories: Int)] = [:]
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.calendarDiaryDate)
            guard range.contains(day) else { continue }
            var bucket = grouped[workout.diaryDateKey] ?? (day, 0, 0)
            bucket.count += 1
            bucket.calories += workout.totalEnergyBurned ?? 0
            grouped[workout.diaryDateKey] = bucket
        }
        return grouped.values.map {
            ImportedHealthWorkoutDay(date: $0.date, sessionCount: $0.count, totalCalories: $0.calories)
        }
        .sorted { $0.date < $1.date }
    }
}

struct ImportedHealthWorkoutChartSection: View {
    let workouts: [ImportedHealthWorkout]
    let dateRange: ClosedRange<Date>

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var days: [ImportedHealthWorkoutDay] {
        ImportedHealthWorkoutAggregation.daily(workouts: workouts, in: dateRange)
    }

    private var totalSessions: Int { days.reduce(0) { $0 + $1.sessionCount } }
    private var totalCalories: Int { days.reduce(0) { $0 + $1.totalCalories } }
    private var averageCalories: Int {
        let daysWithCalories = days.filter { $0.totalCalories > 0 }
        guard !daysWithCalories.isEmpty else { return 0 }
        let sum = daysWithCalories.reduce(0) { $0 + $1.totalCalories }
        return Int((Double(sum) / Double(daysWithCalories.count)).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressV2SectionTitle(title: String(localized: "Apple Health Workouts"))

            if days.isEmpty {
                ProgressMetricEmptyState("No Apple Health workouts in this range")
            } else {
                workoutStatBadges

                Chart(days) { day in
                    BarMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("Sessions", day.sessionCount)
                    )
                    .foregroundStyle(IronTheme.rust)
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
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(IronTheme.hairline)
                        AxisValueLabel()
                            .foregroundStyle(IronTheme.textSecondary)
                    }
                }
                .frame(height: 190)
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Apple Health workouts chart"))
                .accessibilityValue(String(localized: "\(totalSessions) sessions on \(days.count) days."))
            }

            Text("Imported from Apple Health and Apple Watch. Read-only here — edit or delete them in the Health app. These sessions do not affect Energy Burn goals.")
                .font(.caption)
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .progressMetricCardStyle()
    }

    @ViewBuilder
    private var workoutStatBadges: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                workoutStatBadgeContent
            }
        } else {
            HStack(spacing: 8) {
                workoutStatBadgeContent
            }
        }
    }

    @ViewBuilder
    private var workoutStatBadgeContent: some View {
        StatBadge(label: "Sessions", value: totalSessions.formatted())
        StatBadge(label: "Calories", value: "\(totalCalories.formatted()) kcal")
        StatBadge(label: "Average", value: "\(averageCalories.formatted()) kcal")
        StatBadge(label: "Days", value: days.count.formatted())
    }
}

struct ProgressMetricEmptyState: View {
    let message: LocalizedStringKey

    init(_ message: LocalizedStringKey) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(IronTheme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}

private struct ProgressMetricCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.ironCard()
    }
}

private extension View {
    func progressMetricCardStyle() -> some View {
        modifier(ProgressMetricCardStyle())
    }
}
