//
//  StepsView.swift
//  calorietracker
//
//  Daily steps tracking view
//

import SwiftUI
import HealthKit

struct StepsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var stepsService = StepsTrackingService.shared
    @State private var isLoading = false
    @State private var error: String?
    @State private var showingPermission = false

    /// Daily step goal from the active program. The bar is full at this value.
    static var dailyGoal: Int { StepsGoal.current }

    /// When false the view shows whatever `StepsTrackingService.shared` already holds
    /// and never asks HealthKit. Only the visual QA snapshot tests pass false.
    private let loadsHealthData: Bool

    init(loadsHealthData: Bool = true) {
        self.loadsHealthData = loadsHealthData
    }

    var body: some View {
        ScrollView {
                VStack(spacing: 20) {
                    // Today's Progress Card
                    todayCard

                    // 7-Day History
                    weeklyHistory

                    // Sync Status
                    syncStatus
                }
                .padding()
            }
            .background(IronTheme.canvas)
            .navigationTitle("Daily Steps")
            .refreshable {
                guard loadsHealthData else { return }
                await refreshSteps()
            }
            .task {
                guard loadsHealthData else { return }
                await loadInitialData()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active && loadsHealthData {
                    Task { await refreshSteps() }
                }
            }
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                if let error {
                    Text(error)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
    }

    private var todayCard: some View {
        let goal = Self.dailyGoal
        let steps = stepsService.todaySteps
        let met = steps >= goal
        return VStack(spacing: 16) {
            Text("Today")
                .font(.headline)
                .foregroundStyle(IronTheme.textPrimary)

            ZStack {
                Circle()
                    .stroke(IronTheme.surfaceRaised, lineWidth: 20)
                    .frame(width: 200, height: 200)

                Circle()
                    .trim(from: 0, to: min(Double(steps) / Double(goal), 1.0))
                    .stroke(
                        met ? IronTheme.brass : IronTheme.blood,
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: steps)

                VStack(spacing: 2) {
                    Text(steps.formatted(.number.grouping(.automatic)))
                        .font(.system(size: 44, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(IronTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("steps")
                        .font(.caption)
                        .foregroundStyle(IronTheme.textSecondary)

                    Group {
                        if met {
                            Text("Goal met")
                                .foregroundStyle(IronTheme.brass)
                        } else {
                            Text("\((goal - steps).formatted(.number.grouping(.automatic))) to go")
                                .foregroundStyle(IronTheme.textSecondary)
                        }
                    }
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 4)
                }
                .frame(width: 150)
            }
            .frame(height: 220)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .ironCard()
    }

    private var weeklyHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    historyTitle
                    Spacer(minLength: 8)
                    goalCaption
                }
                VStack(alignment: .leading, spacing: 2) {
                    historyTitle
                    goalCaption
                }
            }
            .padding(.horizontal)

            if stepsService.last7Days.isEmpty {
                Text("No step data yet. Pull to refresh after Apple Health syncs.")
                    .font(.subheadline)
                    .foregroundStyle(IronTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(stepsService.last7Days) { day in
                    StepsHistoryRow(
                        title: formatDate(day.date),
                        steps: day.steps,
                        goal: Self.dailyGoal
                    )
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard()
    }

    private var historyTitle: some View {
        Text("Last 7 Days")
            .font(.headline)
            .foregroundStyle(IronTheme.textPrimary)
    }

    private var goalCaption: some View {
        Text("Goal \(Self.dailyGoal.formatted(.number.grouping(.automatic)))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(IronTheme.brass)
            .lineLimit(1)
    }

    private var syncStatus: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(IronTheme.brass)
                
                VStack(alignment: .leading) {
                    Text("Sync Status")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(IronTheme.textPrimary)
                    
                    if stepsService.isSyncing {
                        Text("Syncing...")
                            .font(.caption)
                            .foregroundStyle(IronTheme.textSecondary)
                    } else if let lastSync = stepsService.lastSyncDate {
                        Text("Last synced: \(lastSync, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(IronTheme.textSecondary)
                    } else {
                        Text("Never synced")
                            .font(.caption)
                            .foregroundStyle(IronTheme.textSecondary)
                    }
                    
                    if let error = stepsService.lastSyncError {
                        Text("Error: \(error)")
                            .font(.caption)
                            .foregroundStyle(IronTheme.bloodText)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                Button {
                    Task { await syncNow() }
                } label: {
                    if stepsService.isSyncing {
                        ProgressView()
                    } else {
                        Text("Sync Now")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(IronTheme.blood)
                .disabled(stepsService.isSyncing)
            }
        }
        .padding()
        .ironCard()
    }
    
    private func loadInitialData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Request authorization if needed
            try await stepsService.requestAuthorization()
            
            // Fetch steps
            _ = try await stepsService.fetchTodaySteps()
            _ = try await stepsService.fetchLast7Days()
            
            // Enable background delivery
            stepsService.enableBackgroundDelivery()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    private func refreshSteps() async {
        do {
            _ = try await stepsService.fetchTodaySteps()
            _ = try await stepsService.fetchLast7Days()
        } catch {
            self.error = error.localizedDescription
        }
        await StepsTrackingService.syncBodyMeasurementsFromHealth()
    }
    
    private func syncNow() async {
        do {
            try await stepsService.syncStepsToBackend()
            _ = try await stepsService.fetchTodaySteps()
            _ = try await stepsService.fetchLast7Days()
        } catch {
            self.error = error.localizedDescription
            await StepsTrackingService.syncBodyMeasurementsFromHealth()
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "EEE M/d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - 7-day row

/// One day in the Daily Steps history: the day name and a bar with the count drawn inside it.
struct StepsHistoryRow: View {
    let title: String
    let steps: Int?
    let goal: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var titleWidth: CGFloat = 92

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    titleText
                    StepsHistoryBar(steps: steps, goal: goal)
                }
            } else {
                HStack(spacing: 12) {
                    titleText
                        .frame(width: titleWidth, alignment: .leading)
                    StepsHistoryBar(steps: steps, goal: goal)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private var titleText: some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(IronTheme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var accessibilityValue: String {
        guard let steps else { return "No data" }
        let count = steps.formatted(.number.grouping(.automatic))
        return steps >= goal ? "\(count) steps, goal met" : "\(count) steps"
    }
}

/// Horizontal bar capped at `goal`. The count sits inside the filled part when it fits
/// (right-aligned, contrasting ink) and otherwise just past the end of the fill.
struct StepsHistoryBar: View {
    let steps: Int?
    let goal: Int

    @ScaledMetric(relativeTo: .subheadline) private var barHeight: CGFloat = 28
    @ScaledMetric(relativeTo: .subheadline) private var labelInset: CGFloat = 8
    @State private var labelWidth: CGFloat = 0

    private var fraction: CGFloat {
        guard let steps, goal > 0, steps > 0 else { return 0 }
        return min(CGFloat(steps) / CGFloat(goal), 1)
    }

    private var metGoal: Bool { (steps ?? 0) >= goal && goal > 0 }

    private var labelText: String {
        guard let steps else { return "—" }
        return steps.formatted(.number.grouping(.automatic))
    }

    private var labelFont: Font { .subheadline.weight(.semibold).monospacedDigit() }

    /// Where the count goes for a bar `width` points wide.
    static func labelFitsInsideFill(fillWidth: CGFloat, labelWidth: CGFloat, inset: CGFloat) -> Bool {
        fillWidth > 0 && fillWidth >= labelWidth + inset * 2
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fillWidth = (width * fraction).rounded()
            let inside = Self.labelFitsInsideFill(fillWidth: fillWidth, labelWidth: labelWidth, inset: labelInset)
            let shape = RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)

            ZStack(alignment: .leading) {
                shape.fill(IronTheme.surfaceRaised)

                if fillWidth > 0 {
                    shape
                        .fill(metGoal ? IronTheme.brass : IronTheme.blood)
                        .frame(width: max(fillWidth, IronTheme.buttonRadius * 2))
                }

                if inside {
                    label
                        .foregroundStyle(metGoal ? IronTheme.canvas : IronTheme.textPrimary)
                        .frame(width: max(fillWidth - labelInset * 2, 0), alignment: .trailing)
                        .offset(x: labelInset)
                } else {
                    let start = (fillWidth > 0 ? max(fillWidth, IronTheme.buttonRadius * 2) : 0) + labelInset
                    label
                        .foregroundStyle(steps == nil ? IronTheme.textSecondary : IronTheme.textPrimary)
                        .frame(width: max(width - start - labelInset, 0), alignment: .leading)
                        .offset(x: start)
                }
            }
            .frame(width: width, height: proxy.size.height, alignment: .leading)
        }
        .frame(height: barHeight)
        .frame(maxWidth: .infinity)
        .background(alignment: .leading) {
            // Unscaled width of the count, used to decide inside vs. outside.
            Text(labelText)
                .font(labelFont)
                .lineLimit(1)
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = $0 }
        }
    }

    private var label: some View {
        Text(labelText)
            .font(labelFont)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
