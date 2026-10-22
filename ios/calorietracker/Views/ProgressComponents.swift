import SwiftUI
import Charts

// MARK: - Time Range

nonisolated enum TimeRange: String, CaseIterable, Sendable {
    case week = "1W"
    case month = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case year = "1Y"
    case allTime = "All"

    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .threeMonths: 90
        case .sixMonths: 180
        case .year: 365
        case .allTime: 3650
        }
    }

    /// Inclusive through the end of today. Ending at midnight dropped every entry
    /// logged today, so 1W could be empty while Weight History still had a row.
    func dateRange() -> ClosedRange<Date> {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday)!
        let end = calendar.date(byAdding: .day, value: 1, to: startOfToday)!.addingTimeInterval(-1)
        return start...end
    }

    var rangeDescription: String {
        switch self {
        case .week: "the last 7 days"
        case .month: "the last 30 days"
        case .threeMonths: "the last 3 months"
        case .sixMonths: "the last 6 months"
        case .year: "the last year"
        case .allTime: "the selected range"
        }
    }
}

// Weight / Body Fat / Lean Mass charts live in Views/ProgressV2.

/// Iron card for the Progress cards and history links in this file. The
/// radius argument is kept for existing call sites; every card is squared.
private struct ProgressCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.ironCard()
    }
}

private extension View {
    func progressCardStyle(cornerRadius: CGFloat = 6) -> some View {
        modifier(ProgressCardStyle())
    }
}

// MARK: - Calorie Chart Section

struct CalorieChartSection: View {
    let dailyCalories: [(date: Date, calories: Int)]
    let calorieGoal: Int
    var rangeDescription: String = "the selected range"

    private var averageCalories: Int {
        dailyCalories.reduce(0) { $0 + $1.calories } / max(dailyCalories.count, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressV2SectionTitle(
                title: String(localized: "Calories"),
                detail: dailyCalories.isEmpty
                    ? nil
                    : String(localized: "Average \(averageCalories.formatted()) kcal on logged days · goal \(calorieGoal.formatted())")
            )

            if dailyCalories.isEmpty {
                ProgressV2EmptyState(
                    title: String(localized: "No food logged in \(rangeDescription)"),
                    message: String(localized: "Log meals on Home to see daily calories against your goal."),
                    systemImage: "fork.knife"
                )
            } else {
                Chart {
                    ForEach(dailyCalories, id: \.date) { item in
                        BarMark(
                            x: .value("Date", item.date, unit: .day),
                            y: .value("Calories", item.calories)
                        )
                        .foregroundStyle(IronTheme.blood)
                    }

                    RuleMark(y: .value("Goal", calorieGoal))
                        .foregroundStyle(IronTheme.brass)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
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
                // Axis labels in a fixed-height plot overlapped ("SepS26S28")
                // at accessibility sizes; cap only the chart's type size.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Calories chart"))
                .accessibilityValue(String(localized: "\(dailyCalories.count) logged days. Average \(averageCalories.formatted()) kilocalories. Goal \(calorieGoal.formatted())."))
            }
        }
        .padding(14)
        .progressCardStyle()
    }
}

// MARK: - Macro Averages Section

/// One-pass Progress nutrition aggregates for a selected time range.
/// Built off the main path so range switching stays interruptible.
struct ProgressFoodRangeStats {
    let dailyCalories: [(date: Date, calories: Int)]
    let avgProtein: Double
    let avgCarbs: Double
    let avgFat: Double
    let nutrientItems: [NutrientAverageItem]
    /// Days in the range with at least one food entry.
    var loggedDays: Int = 0

    static let empty = ProgressFoodRangeStats(
        dailyCalories: [],
        avgProtein: 0,
        avgCarbs: 0,
        avgFat: 0,
        nutrientItems: []
    )

    static func compute(
        entries: [FoodEntry],
        dayCount: Int,
        profile: UserProfile,
        optionalGoals: OptionalNutrientGoals,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ProgressFoodRangeStats {
        let today = calendar.startOfDay(for: now)
        guard let rangeStart = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) else {
            return .empty
        }

        var buckets: [Date: [FoodEntry]] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            guard day >= rangeStart, day <= today else { continue }
            buckets[day, default: []].append(entry)
        }

        let nutrients = HomeTopNutrient.allCases.filter { $0 != .protein && $0 != .carbs && $0 != .fat }
        var dailyCalories: [(date: Date, calories: Int)] = []
        var totalP = 0.0, totalC = 0.0, totalF = 0.0
        var loggedDays = 0
        var nutrientTotals = Dictionary(uniqueKeysWithValues: nutrients.map { ($0, 0.0) })

        for day in buckets.keys.sorted() {
            let dayEntries = buckets[day] ?? []
            guard !dayEntries.isEmpty else { continue }

            let calories = dayEntries.reduce(0) { $0 + $1.calories }
            if calories > 0 {
                dailyCalories.append((day, calories))
            }

            totalP += dayEntries.reduce(0) { $0 + $1.protein }
            totalC += dayEntries.reduce(0) { $0 + $1.carbs }
            totalF += dayEntries.reduce(0) { $0 + $1.fat }
            loggedDays += 1

            for nutrient in nutrients {
                nutrientTotals[nutrient, default: 0] += nutrient.total(in: dayEntries)
            }
        }

        let divisor = Double(max(loggedDays, 1))
        let nutrientItems: [NutrientAverageItem] = loggedDays == 0
            ? []
            : nutrients.compactMap { nutrient in
                let average = (nutrientTotals[nutrient] ?? 0) / divisor
                let goal = Int(nutrient.goal(for: profile, optionalGoals: optionalGoals).rounded())
                if average < 0.05 && goal == 0 { return nil }
                return NutrientAverageItem(
                    id: nutrient.rawValue,
                    label: nutrient.optionalNutrient?.displayName ?? nutrient.displayName,
                    current: average,
                    goal: goal,
                    unit: nutrient.unit
                )
            }

        if loggedDays == 0 {
            return ProgressFoodRangeStats(
                dailyCalories: dailyCalories,
                avgProtein: 0,
                avgCarbs: 0,
                avgFat: 0,
                nutrientItems: []
            )
        }

        return ProgressFoodRangeStats(
            dailyCalories: dailyCalories,
            avgProtein: totalP / divisor,
            avgCarbs: totalC / divisor,
            avgFat: totalF / divisor,
            nutrientItems: nutrientItems,
            loggedDays: loggedDays
        )
    }
}

struct ProgressNutritionLoadingCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(IronTheme.bloodText)
            Text(LocalizedDisplayText.text("Loading nutrition…", polish: "Ładowanie wartości odżywczych…"))
                .font(.subheadline)
                .foregroundStyle(IronTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .progressCardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LocalizedDisplayText.text("Loading nutrition…", polish: "Ładowanie wartości odżywczych…"))
    }
}

struct MacroAveragesSection: View {
    let avgProtein: Double
    let avgCarbs: Double
    let avgFat: Double
    let proteinGoal: Int
    let carbsGoal: Int
    let fatGoal: Int
    var hasLoggedDays: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressV2SectionTitle(
                title: String(localized: "Macro Averages"),
                detail: hasLoggedDays ? String(localized: "Per logged day") : nil
            )

            if hasLoggedDays {
                MacroProgressRow(label: "Protein", current: avgProtein, goal: proteinGoal, unit: "g", color: IronTheme.bloodText, gradientColors: [IronTheme.blood])
                MacroProgressRow(label: "Carbs", current: avgCarbs, goal: carbsGoal, unit: "g", color: IronTheme.brass, gradientColors: [IronTheme.brass])
                MacroProgressRow(label: "Fat", current: avgFat, goal: fatGoal, unit: "g", color: IronTheme.olive, gradientColors: [IronTheme.olive])
            } else {
                ProgressV2EmptyState(
                    title: String(localized: "No food logged in this range"),
                    message: String(localized: "Protein, carbs and fat averages appear once meals are logged."),
                    systemImage: "fork.knife"
                )
            }
        }
        .padding(14)
        .progressCardStyle()
    }
}

struct NutrientAverageItem: Identifiable {
    let id: String
    let label: String
    let current: Double
    let goal: Int
    let unit: String
}

struct NutrientAveragesSection: View {
    let items: [NutrientAverageItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressV2SectionTitle(
                title: String(localized: "Nutrient Averages"),
                detail: String(localized: "Per logged day")
            )

            if items.isEmpty {
                ProgressV2EmptyState(
                    title: String(localized: "No nutrients to average in this range"),
                    systemImage: "fork.knife"
                )
            } else {
                ForEach(items) { item in
                    MacroProgressRow(
                        label: item.label,
                        current: item.current,
                        goal: item.goal,
                        unit: item.unit,
                        color: IronTheme.textSecondary,
                        gradientColors: [IronTheme.textSecondary],
                        localizeLabel: false
                    )
                }
            }
        }
        .padding(14)
        .progressCardStyle()
    }
}

struct MacroProgressRow: View {
    let label: String
    let current: Double
    let goal: Int
    var unit: String = "g"
    let color: Color
    let gradientColors: [Color]
    var localizeLabel: Bool = true

    private var progress: Double {
        goal > 0 ? min(current / Double(goal), 1.0) : 0
    }

    private var valueText: String {
        let amount = "\(MacroValueFormatter.string(current))\(unit)"
        if goal > 0 {
            return "\(amount) / \(goal)\(unit)"
        }
        return amount
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            layout {
                Text(localizeLabel ? LocalizedDisplayText.text(label) : label)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(IronTheme.textPrimary)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                }
                Text(valueText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(IronTheme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(IronTheme.surfaceRaised)

                    Rectangle()
                        .fill(gradientColors.first ?? color)
                        .frame(width: max(4, geo.size.width * progress))
                }
            }
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Stats Section

struct StatsSection: View {
    let streak: Int
    let daysOnTarget: Int
    let totalEntries: Int
    let bestStreak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Streaks & Stats")
                .font(.system(size: 13, weight: .heavy))
                .fontWidth(.condensed)
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.textSecondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(icon: "flame.fill", label: "Current Streak", value: String(localized: "\(streak) days"), color: IronTheme.brass)
                StatTile(icon: "trophy.fill", label: "Best Streak", value: String(localized: "\(bestStreak) days"), color: IronTheme.brass)
                StatTile(icon: "target", label: "Days on Target", value: "\(daysOnTarget)", color: AppColors.protein)
                StatTile(icon: "fork.knife", label: "Total Entries", value: "\(totalEntries)", color: AppColors.fat)
            }
        }
        .padding()
        .ironCard()
    }
}

struct StatTile: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))

            Text(LocalizedDisplayText.text(label))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct StatBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.subheadline, weight: .bold).monospacedDigit())
                .foregroundStyle(IronTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(LocalizedDisplayText.text(label))
                .font(.system(.caption2, weight: .heavy))
                .fontWidth(.condensed)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        // Three badges share one row; beyond accessibility1 the values were
        // truncating to "202.3…" / "Net Ch…" even at the minimum scale.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(
            IronTheme.surfaceRaised,
            in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
        )
    }
}

// MARK: - Log Weight Sheet

struct LogWeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weightUnit") private var weightUnitRaw = "lbs"
    let currentWeightKg: Double
    var previous: WeightEntry? = nil
    let onSave: (Double) -> Void

    @State private var wholeNumber: Int
    @State private var decimal: Int
    @State private var plausibilityMessage: String?

    init(currentWeightKg: Double, previous: WeightEntry? = nil, onSave: @escaping (Double) -> Void) {
        self.currentWeightKg = currentWeightKg
        self.previous = previous
        self.onSave = onSave
        // Respect @AppStorage at the time the sheet is created.
        let metric = UserDefaults.standard.string(forKey: "weightUnit") == "kg"
        let displayValue = metric ? currentWeightKg : currentWeightKg * 2.20462
        let whole = Int(displayValue)
        let dec = min(9, max(0, Int((displayValue - Double(whole)) * 10 + 0.5)))
        _wholeNumber = State(initialValue: whole)
        _decimal = State(initialValue: dec)
    }

    private var useMetric: Bool { weightUnitRaw == "kg" }

    private var selectedValue: Double {
        Double(wholeNumber) + Double(decimal) / 10.0
    }

    private var selectedKg: Double {
        useMetric ? selectedValue : selectedValue / 2.20462
    }

    private var unit: String { useMetric ? "kg" : "lb" }
    private var wholeRange: ClosedRange<Int> { useMetric ? 20...250 : 50...500 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Log Weight")
                    .font(.system(.title2, design: .rounded, weight: .bold))

                Picker("Unit", selection: $weightUnitRaw) {
                    Text("kg").tag("kg")
                    Text("lb").tag("lbs")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .onChange(of: weightUnitRaw) { _, newValue in
                    // Convert the currently selected value so toggling mid-edit keeps it,
                    // clamped into the destination wheel's rows (20...250 kg / 50...500 lbs)
                    // so the selection never lands on a tag the wheel doesn't offer.
                    let value = Double(wholeNumber) + Double(decimal) / 10.0
                    let converted = newValue == "kg" ? value / 2.20462 : value * 2.20462
                    let bounds = newValue == "kg" ? 20.0...250.0 : 50.0...500.0
                    let clamped = min(bounds.upperBound, max(bounds.lowerBound, converted))
                    let whole = Int(clamped)
                    wholeNumber = whole
                    decimal = min(9, max(0, Int((clamped - Double(whole)) * 10 + 0.5)))
                }

                // Scroll wheel pickers
                HStack(spacing: 0) {
                    Picker("Whole", selection: $wholeNumber) {
                        ForEach(wholeRange, id: \.self) { num in
                            Text("\(num)").tag(num)
                                .font(.system(.title2, design: .rounded, weight: .medium))
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 100)
                    .clipped()

                    Text(".")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .offset(y: -1)

                    Picker("Decimal", selection: $decimal) {
                        ForEach(0...9, id: \.self) { num in
                            Text("\(num)").tag(num)
                                .font(.system(.title2, design: .rounded, weight: .medium))
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 70)
                    .clipped()

                    Text(unit)
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }

                Button {
                    let days = previous.map { max(1, Calendar.current.dateComponents([.day], from: $0.date, to: .now).day ?? 1) } ?? 1
                    let flags = PlausibilityRules.weight(newKg: selectedKg, previousKg: previous?.weightKg, days: days)
                    Task {
                        let visible = await PlausibilityReview.visible(flags)
                        if visible.isEmpty {
                            onSave(selectedKg)
                            dismiss()
                        } else {
                            plausibilityMessage = visible.prefix(3).map(\.message).joined(separator: "\n")
                        }
                    }
                } label: {
                    Text("Save")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(colors: AppColors.calorieGradient, startPoint: .leading, endPoint: .trailing)
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.top, 24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .plausibilityConfirmation(
            title: "Save \(weightPrompt)?",
            message: plausibilityMessage,
            saveTitle: "Save",
            onSave: {
                let kg = selectedKg
                plausibilityMessage = nil
                Task { await JevRouter.shared.report(.plausibility, .userOverride, preview: "weight") }
                onSave(kg)
                dismiss()
            },
            onEdit: { plausibilityMessage = nil }
        )
    }

    private var weightPrompt: String {
        String(format: "%.1f %@", selectedValue, useMetric ? "kg" : "lb")
    }
}

// MARK: - Weight History Link (tap to open full list)

struct WeightHistoryLink: View {
    let totalCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.calorie)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weight History")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("\(totalCount) \(totalCount == 1 ? "entry" : "entries") · tap to view or delete")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .progressCardStyle(cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - All Weight History (full-screen sheet)

struct AllWeightHistoryView: View {
    let entries: [WeightEntry]
    let useMetric: Bool
    let onDelete: (WeightEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeletion: WeightEntry?
    // Local mirror so the list updates immediately after deletion without needing the parent to re-bind.
    @State private var visibleEntries: [WeightEntry] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(visibleEntries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayWeight(entry.weightKg, useMetric: useMetric))
                                .font(.system(.body, design: .rounded, weight: .medium))
                            Text(weightHistoryCaption(entry))
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDeletion = entry
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Weight History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { visibleEntries = entries }
        .alert("Delete Weight Entry", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Delete", role: .destructive) {
                if let entry = pendingDeletion {
                    visibleEntries.removeAll { $0.id == entry.id }
                    onDelete(entry)
                }
                pendingDeletion = nil
            }
        } message: {
            if let entry = pendingDeletion {
                Text("Remove \(weightHistoryFormatter.string(from: entry.date))'s entry of \(displayWeight(entry.weightKg, useMetric: useMetric))? This also deletes the matching sample from Apple Health.")
            }
        }
    }
}

private let weightHistoryFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
}()

private func weightHistoryCaption(_ entry: WeightEntry) -> String {
    var parts = [weightHistoryFormatter.string(from: entry.date)]
    if entry.isLeanBodyMass {
        parts.append("Lean body mass")
    }
    if let source = entry.healthSourceName {
        parts.append(source)
    }
    return parts.joined(separator: " · ")
}

private func displayWeight(_ kg: Double, useMetric: Bool) -> String {
    if useMetric {
        return String(format: "%.1f kg", kg)
    }
    let lbs = kg * 2.20462
    return String(format: "%.1f lb", lbs)
}

// MARK: - Body Fat History (link + full list, mirroring Weight History)

struct BodyFatHistoryLink: View {
    let totalCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.calorie)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Body Fat History")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("\(totalCount) \(totalCount == 1 ? "entry" : "entries") · tap to view or delete")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .progressCardStyle(cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }
}

struct AllBodyFatHistoryView: View {
    let entries: [BodyFatEntry]
    let onDelete: (BodyFatEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeletion: BodyFatEntry?
    // Local mirror so the list updates immediately after deletion without needing the parent to re-bind.
    @State private var visibleEntries: [BodyFatEntry] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(visibleEntries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayBodyFat(entry.bodyFatFraction))
                                .font(.system(.body, design: .rounded, weight: .medium))
                            Text(bodyFatHistoryCaption(entry))
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDeletion = entry
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Body Fat History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { visibleEntries = entries }
        .alert("Delete Body Fat Entry", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Delete", role: .destructive) {
                if let entry = pendingDeletion {
                    visibleEntries.removeAll { $0.id == entry.id }
                    onDelete(entry)
                }
                pendingDeletion = nil
            }
        } message: {
            if let entry = pendingDeletion {
                Text("Remove \(weightHistoryFormatter.string(from: entry.date))'s entry of \(displayBodyFat(entry.bodyFatFraction))? This also deletes the matching sample from Apple Health.")
            }
        }
    }
}

private func bodyFatHistoryCaption(_ entry: BodyFatEntry) -> String {
    var parts = [weightHistoryFormatter.string(from: entry.date)]
    if let source = entry.healthSourceName {
        parts.append(source)
    }
    return parts.joined(separator: " · ")
}

private func displayBodyFat(_ fraction: Double) -> String {
    String(format: "%.1f%%", fraction * 100)
}

// MARK: - Log Body Fat Sheet

/// Single-wheel picker for body-fat %. Whole-number precision (matches
/// BodyFatPickerSheet in Settings) — body-fat measurements rarely justify
/// 0.1% resolution given the noise of calipers / smart scales.
struct LogBodyFatSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentFraction: Double
    var previousFraction: Double? = nil
    var previousDate: Date? = nil
    let onSave: (Double) -> Void

    @State private var percentage: Int
    @State private var plausibilityMessage: String?

    init(currentFraction: Double, previousFraction: Double? = nil, previousDate: Date? = nil, onSave: @escaping (Double) -> Void) {
        self.currentFraction = currentFraction
        self.previousFraction = previousFraction
        self.previousDate = previousDate
        self.onSave = onSave
        _percentage = State(initialValue: Int(currentFraction * 100))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Log Body Fat")
                    .font(.system(.title2, design: .rounded, weight: .bold))

                HStack(spacing: 0) {
                    Picker("Percentage", selection: $percentage) {
                        ForEach(3...60, id: \.self) { n in
                            Text("\(n)").tag(n)
                                .font(.system(.title2, design: .rounded, weight: .medium))
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 100)
                    .clipped()

                    Text("%")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }

                Button {
                    let fraction = Double(percentage) / 100.0
                    let days = previousDate.map { max(1, Calendar.current.dateComponents([.day], from: $0, to: .now).day ?? 1) } ?? 1
                    let flags = PlausibilityRules.bodyFat(
                        newPercent: Double(percentage),
                        previousPercent: previousFraction.map { $0 * 100 },
                        days: days
                    )
                    Task {
                        let visible = await PlausibilityReview.visible(flags)
                        if visible.isEmpty {
                            onSave(fraction)
                            dismiss()
                        } else {
                            plausibilityMessage = visible.prefix(3).map(\.message).joined(separator: "\n")
                        }
                    }
                } label: {
                    Text("Save")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(colors: AppColors.calorieGradient, startPoint: .leading, endPoint: .trailing)
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.top, 24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .plausibilityConfirmation(
            title: "Save \(percentage)% body fat?",
            message: plausibilityMessage,
            saveTitle: "Save",
            onSave: {
                let fraction = Double(percentage) / 100.0
                plausibilityMessage = nil
                Task { await JevRouter.shared.report(.plausibility, .userOverride, preview: "body fat") }
                onSave(fraction)
                dismiss()
            },
            onEdit: { plausibilityMessage = nil }
        )
    }
}

// MARK: - Body Measurements

/// cm → display string in the user's unit ("92.0 cm" / "36.2 in").
private func displayLength(_ cm: Double, useMetric: Bool) -> String {
    useMetric ? String(format: "%.1f cm", cm) : String(format: "%.1f in", cm / 2.54)
}

/// The logged sites in display order, skipping any that weren't entered.
private func measurementSites(_ m: BodyMeasurement) -> [(label: String, cm: Double)] {
    var rows: [(String, Double)] = []
    func add(_ label: String, _ value: Double?) { if let value { rows.append((label, value)) } }
    add("Neck", m.neckCm)
    add("Waist", m.waistCm)
    add("Hips", m.hipsCm)
    add("Chest", m.chestCm)
    add("Upper arm", m.upperArmCm)
    add("Thigh", m.thighCm)
    add("Calf", m.calfCm)
    add("Wrist", m.wristCm)
    return rows
}

/// The four derived metrics that can be computed from `m` + the profile, skipping any that can't.
private func derivedMetricChips(_ m: BodyMeasurement, gender: Gender, heightCm: Double) -> [(label: String, value: String)] {
    var chips: [(String, String)] = []
    if let whr = m.waistToHipRatio {
        chips.append(("Waist-to-hip", String(format: "%.2f", whr)))
    }
    if let whtr = m.waistToHeightRatio(heightCm: heightCm) {
        chips.append(("Waist-to-height", String(format: "%.2f", whtr)))
    }
    if let bf = m.usNavyBodyFatPercent(gender: gender, heightCm: heightCm) {
        chips.append(("Body fat (Navy)", String(format: "%.0f%%", bf)))
    }
    if let frame = m.wristFrame(gender: gender, heightCm: heightCm) {
        chips.append(("Frame", frame.label))
    }
    return chips
}

/// Settings → Personal Info detail screen. Mirrors the Other Nutrients screen: a tappable row per
/// body part that opens a wheel picker to set its value, plus the AI-derived metrics and history.
/// Lives in Settings (not Progress) so it sits with the other body inputs.
struct BodyMeasurementsDetailView: View {
    @Environment(BodyMeasurementStore.self) private var store
    @AppStorage("heightUnit") private var heightUnitRaw = "ftin"
    let gender: Gender
    let heightCm: Double

    private var useMetric: Bool { heightUnitRaw == "cm" }

    @State private var editingSite: BodyMeasurement.Site?
    @State private var showHistory = false

    private var latest: BodyMeasurement? { store.latestEntry }
    private var unit: String { useMetric ? "cm" : "in" }

    private func displayValue(_ site: BodyMeasurement.Site) -> String {
        guard let cm = latest?.value(for: site) else { return "Not set" }
        return useMetric ? String(format: "%.0f cm", cm) : String(format: "%.0f in", cm / 2.54)
    }

    var body: some View {
        List {
            Section {
                ForEach(BodyMeasurement.Site.allCases) { site in
                    Button {
                        editingSite = site
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "ruler")
                                .foregroundStyle(AppColors.calorie)
                                .frame(width: 22)
                            Text(site.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(displayValue(site))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Measurements")
            } footer: {
                Text("Optional. JL Physical turns these into waist-to-hip, waist-to-height, body-fat %, and frame size, and reads them when it recalculates your goals and in Coach.")
            }
            .listRowBackground(AppColors.appCard)

            if let latest {
                let chips = derivedMetricChips(latest, gender: gender, heightCm: heightCm)
                if !chips.isEmpty {
                    Section("Derived") {
                        ForEach(chips, id: \.label) { chip in
                            HStack {
                                Text(chip.label)
                                Spacer()
                                Text(chip.value)
                                    .foregroundStyle(AppColors.calorie)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .listRowBackground(AppColors.appCard)
                }
            }

            if store.entries.count > 1 {
                Section {
                    Button {
                        showHistory = true
                    } label: {
                        HStack {
                            Text("Measurement History")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(store.entries.count)")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(AppColors.appCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle("Body Measurements")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingSite) { site in
            MeasurementEditSheet(
                site: site,
                currentCm: latest?.value(for: site),
                previousCm: previousMeasurement(site, in: store)?.cm,
                previousDate: previousMeasurement(site, in: store)?.date,
                onSave: { cm in store.setValue(site, cm: cm) },
                onClear: { store.setValue(site, cm: nil) }
            )
        }
        .sheet(isPresented: $showHistory) {
            AllBodyMeasurementsHistoryView(
                entries: store.sortedEntries,
                gender: gender,
                heightCm: heightCm,
                useMetric: useMetric,
                onDelete: { entry in store.deleteEntry(entry) }
            )
        }
    }
}

/// Latest value for a site before today, for the plausibility check.
private func previousMeasurement(_ site: BodyMeasurement.Site, in store: BodyMeasurementStore) -> (cm: Double, date: Date)? {
    for entry in store.sortedEntries {
        guard let value = entry.value(for: site), !Calendar.current.isDateInToday(entry.date) else { continue }
        return (value, entry.date)
    }
    return nil
}

/// Editor for one measurement site. The cm|in switcher persists the shared
/// length standard (same pref as the Height editor), and — matching the
/// height/weight editors — flipping it converts the value currently on the
/// wheel (clamped into the destination wheel's rows) instead of re-seeding.
private struct MeasurementEditSheet: View {
    let site: BodyMeasurement.Site
    let hasCurrent: Bool
    var previousCm: Double? = nil
    var previousDate: Date? = nil
    let onSave: (Double) -> Void
    let onClear: () -> Void

    @AppStorage("heightUnit") private var heightUnitRaw = "ftin"
    @State private var displayValue: Int
    @State private var plausibilityMessage: String?
    @State private var pendingCm: Double?
    @Environment(\.dismiss) private var dismiss

    init(
        site: BodyMeasurement.Site,
        currentCm: Double?,
        previousCm: Double? = nil,
        previousDate: Date? = nil,
        onSave: @escaping (Double) -> Void,
        onClear: @escaping () -> Void
    ) {
        self.site = site
        self.hasCurrent = currentCm != nil
        self.previousCm = previousCm
        self.previousDate = previousDate
        self.onSave = onSave
        self.onClear = onClear
        let metric = UserDefaults.standard.string(forKey: "heightUnit") == "cm"
        let seed = currentCm.map { metric ? Int($0.rounded()) : Int(($0 / 2.54).rounded()) } ?? (metric ? 80 : 32)
        _displayValue = State(initialValue: seed)
    }

    private var useMetric: Bool { heightUnitRaw == "cm" }

    // Converts in the binding's setter so the new unit and the converted value
    // land in the same update — the re-keyed wheel below then seeds correctly.
    private var unitSelection: Binding<String> {
        Binding(
            get: { heightUnitRaw },
            set: { newValue in
                guard newValue != heightUnitRaw else { return }
                if newValue == "cm" {
                    displayValue = min(250, max(10, Int((Double(displayValue) * 2.54).rounded())))
                } else {
                    displayValue = min(100, max(4, Int((Double(displayValue) / 2.54).rounded())))
                }
                heightUnitRaw = newValue
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Unit", selection: unitSelection) {
                Text("cm").tag("cm")
                Text("in").tag("ftin")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.top, 20)

            NutritionPickerSheet(
                label: site.label,
                unit: useMetric ? "cm" : "in",
                currentValue: displayValue,
                range: useMetric ? 10...250 : 4...100,
                step: 1,
                onSave: { value in
                    onSave(useMetric ? Double(value) : Double(value) * 2.54)
                },
                shouldSave: { value in
                    let cm = useMetric ? Double(value) : Double(value) * 2.54
                    let days = previousDate.map { max(1, Calendar.current.dateComponents([.day], from: $0, to: .now).day ?? 1) } ?? 1
                    let flags = PlausibilityRules.measurement(newCm: cm, previousCm: previousCm, days: days)
                    let visible = await PlausibilityReview.visible(flags)
                    if visible.isEmpty { return true }
                    pendingCm = cm
                    plausibilityMessage = visible.prefix(3).map(\.message).joined(separator: "\n")
                    return false
                },
                onResetToAuto: hasCurrent ? onClear : nil,
                resetLabel: "Clear",
                onValueChange: { displayValue = $0 }
            )
            // Re-key so a unit flip rebuilds the wheel seeded with the value
            // converted above (its selection state is set once, in init).
            .id(heightUnitRaw)
        }
        .plausibilityConfirmation(
            title: "Double-check before saving",
            message: plausibilityMessage,
            saveTitle: "Save",
            onSave: {
                if let pendingCm { onSave(pendingCm) }
                plausibilityMessage = nil
                Task { await JevRouter.shared.report(.plausibility, .userOverride, preview: "measurement") }
                dismiss()
            },
            onEdit: { plausibilityMessage = nil }
        )
    }
}

/// Full history with swipe-to-delete, mirroring AllWeightHistoryView.
struct AllBodyMeasurementsHistoryView: View {
    let entries: [BodyMeasurement]
    let gender: Gender
    let heightCm: Double
    let useMetric: Bool
    let onDelete: (BodyMeasurement) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeletion: BodyMeasurement?
    @State private var visibleEntries: [BodyMeasurement] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(visibleEntries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(weightHistoryFormatter.string(from: entry.date))
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Text(summary(entry))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDeletion = entry
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Measurement History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { visibleEntries = entries }
        .alert("Delete Measurement", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Delete", role: .destructive) {
                if let entry = pendingDeletion {
                    visibleEntries.removeAll { $0.id == entry.id }
                    onDelete(entry)
                }
                pendingDeletion = nil
            }
        } message: {
            if let entry = pendingDeletion {
                Text("Remove \(weightHistoryFormatter.string(from: entry.date))'s measurements?")
            }
        }
    }

    private func summary(_ m: BodyMeasurement) -> String {
        let sites = measurementSites(m).map { "\($0.label) \(displayLength($0.cm, useMetric: useMetric))" }
        if let bf = m.usNavyBodyFatPercent(gender: gender, heightCm: heightCm) {
            return (sites + [String(format: "BF %.0f%%", bf)]).joined(separator: " · ")
        }
        return sites.joined(separator: " · ")
    }
}
