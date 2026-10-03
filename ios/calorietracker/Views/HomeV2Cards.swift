//
//  HomeV2Cards.swift
//  calorietracker
//
//  Home v2 cards. The diary and the add button stay in HomeView.
//

import Charts
import HealthKit
import SwiftUI

enum HomeCardID: String, CaseIterable, Identifiable, Codable {
    case weekStrip
    case today
    case dailyTargets
    case bodyTrend
    case recovery
    case peptides
    case weekSoFar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekStrip: "Week"
        case .today: "Today"
        case .dailyTargets: "Daily targets"
        case .bodyTrend: "Body trend"
        case .recovery: "Recovery"
        case .peptides: "Peptides"
        case .weekSoFar: "Week so far"
        }
    }
}

enum HomeCardLayout {
    static let storageKey = "jl.physical.homeCards.v1"

    static func load() -> (order: [HomeCardID], hidden: Set<HomeCardID>) {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            return (HomeCardID.allCases, [])
        }
        var order = stored.order.compactMap(HomeCardID.init(rawValue:))
        for card in HomeCardID.allCases where !order.contains(card) {
            order.append(card)
        }
        let hidden = Set(stored.hidden.compactMap(HomeCardID.init(rawValue:)))
        return (order, hidden)
    }

    static func save(order: [HomeCardID], hidden: Set<HomeCardID>) {
        let stored = Stored(order: order.map(\.rawValue), hidden: hidden.map(\.rawValue).sorted())
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private struct Stored: Codable {
        var order: [String]
        var hidden: [String]
    }
}

struct HomeV2Cards: View {
    @Binding var selectedDate: Date
    var refreshToken: Int
    var onViewNutrition: () -> Void

    @Environment(FoodStore.self) private var foodStore
    @Environment(WaterStore.self) private var waterStore
    @Environment(HealthKitManager.self) private var healthKitManager
    @Environment(ProfileStore.self) private var profileStore
    @Environment(WorkoutDraftStore.self) private var workoutDraftStore
    @Environment(PeptideLogStore.self) private var peptideStore
    @AppStorage("healthKitEnabled") private var healthKitEnabled = false
    @AppStorage("weekStartsOnMonday") private var weekStartsOnMonday = true
    @AppStorage(WaterSettings.enabledKey) private var waterTrackingEnabled = false
    @AppStorage(WaterSettings.dailyGoalKey) private var waterDailyGoal = WaterSettings.defaultDailyGoalMl
    @AppStorage(WaterSettings.unitKey) private var waterUnitRaw = WaterUnit.defaultUnit.rawValue
    @AppStorage(OptionalNutrientGoals.storageKey) private var optionalNutrientGoalsData = Data()

    @State private var order = HomeCardID.allCases
    @State private var hidden = Set<HomeCardID>()
    @State private var showingCustomize = false
    @State private var programRecord: TrainingProgramRecord?
    @State private var allowCachedProgram = true
    @State private var programNotice: String?
    @State private var workouts: [RemoteWorkout] = []
    @State private var workoutsLoaded = false
    @State private var sessionDetail: WorkoutDetailResponse?
    @State private var stepsByDay: [Date: Int]?
    @State private var burnedCalories: Int?
    @State private var weightSamples: [HealthSampleReading] = []
    @State private var fatSamples: [HealthSampleReading] = []
    @State private var leanSamples: [HealthSampleReading] = []
    @State private var bodyLoaded = false
    @State private var asleepSeconds: TimeInterval?
    @State private var restingHeartRate: Double?
    @State private var hrvSamples: [HealthSampleReading] = []
    @State private var recoveryLoaded = false
    @State private var peptideToday: PeptideTodayResponse?
    @State private var peptideInventory: [PeptideInventoryItem] = []
    @State private var activeScheduleCount = 0
    @State private var peptideError: String?
    @State private var loggingDay: ProgramV2Day?
    @State private var peptideAction: PeptideAction?
    @State private var showingPeptideLog = false

    private let bridge = NeonBridgeService.shared

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = weekStartsOnMonday ? 2 : 1
        return calendar
    }

    private var programBody: TrainingProgramBody? {
        if let body = programRecord?.body { return body }
        guard allowCachedProgram else { return nil }
        return ActiveProgramCache.load()?.body
    }

    private var stepsTarget: Int {
        StepsGoal.resolved(programBody?.dailyStepsTarget)
    }

    var body: some View {
        ForEach(order.filter { !hidden.contains($0) }) { card in
            cardSection(card)
        }
        .task(id: loadKey) {
            await reload()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Customize") { showingCustomize = true }
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
        }
        .sheet(isPresented: $showingCustomize, onDismiss: reloadLayout) {
            CustomizeHomeSheet(order: order, hidden: hidden) { newOrder, newHidden in
                order = newOrder
                hidden = newHidden
                HomeCardLayout.save(order: newOrder, hidden: newHidden)
            }
        }
        .sheet(item: $loggingDay) { day in
            ProgramV2WorkoutLogView(day: day) {
                Task { await reloadWorkouts() }
            }
        }
        .sheet(item: $peptideAction) { action in
            PeptideActionSheet(action: action) {
                Task { await reloadPeptides() }
            }
        }
        .sheet(isPresented: $showingPeptideLog) {
            PeptideLogSheet(person: PeptidePersonMemory.load()) {
                // Re-read /today only once the queued write has gone out.
                Task {
                    await peptideStore.flush()
                    await reloadPeptides()
                }
            }
        }
    }

    private var loadKey: String {
        "\(selectedDate.timeIntervalSince1970)-\(refreshToken)-\(healthKitEnabled)"
    }

    @ViewBuilder
    private func cardSection(_ card: HomeCardID) -> some View {
        switch card {
        case .weekStrip:
            Section {
                weekStrip
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: {
                IronSectionTitle(title: "Week")
            }
        case .today:
            Section {
                if let draft = workoutDraftStore.draft {
                    ResumeWorkoutCard(draft: draft) {
                        loggingDay = draft.programV2Day
                    }
                    .listRowBackground(IronTheme.surface)
                }
                todayCard.listRowBackground(todaySurface)
            } header: {
                IronSectionTitle(title: "Today")
            }
        case .dailyTargets:
            Section {
                dailyTargets.listRowBackground(IronTheme.surface)
                Button(action: onViewNutrition) {
                    HStack {
                        Spacer()
                        Text("View More")
                            .font(.system(size: 13, weight: .heavy))
                            .fontWidth(.condensed)
                            .tracking(0.8)
                        Image(systemName: "chevron.right").font(.caption2)
                        Spacer()
                    }
                    .foregroundStyle(IronTheme.bloodText)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                NavigationLink {
                    ProfileView(settingsCategory: .dailyTargets)
                } label: {
                    HStack(spacing: 6) {
                        IronSectionTitle(title: "Daily targets")
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(IronTheme.textSecondary)
                    }
                }
            }
        case .bodyTrend:
            Section {
                bodyTrend.listRowBackground(IronTheme.surface)
            } header: {
                IronSectionTitle(title: "Body trend")
            }
        case .recovery:
            Section {
                recovery.listRowBackground(IronTheme.surface)
            } header: {
                IronSectionTitle(title: "Recovery")
            }
        case .peptides:
            if peptideSectionVisible {
                Section {
                    NavigationLink {
                        ReconView()
                    } label: {
                        HStack {
                            Text("Recon")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            Spacer()
                        }
                    }
                    .listRowBackground(IronTheme.surface)
                    peptideCard.listRowBackground(IronTheme.surface)
                    if HomePeptideSummary.hasContent(store: peptideStore, day: peptideDay, shownKeys: peptideShownKeys) {
                        HomePeptideSummary(day: peptideDay, shownKeys: peptideShownKeys).listRowBackground(IronTheme.surface)
                    }
                    NavigationLink {
                        PeptidesView()
                    } label: {
                        Text("Open Peptides")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    }
                    .listRowBackground(IronTheme.surface)
                } header: {
                    IronSectionTitle(title: "Peptides")
                }
            }
        case .weekSoFar:
            Section {
                weekSoFarCard.listRowBackground(IronTheme.surface)
            } header: {
                IronSectionTitle(title: "Week so far")
            }
        }
    }

    private var peptideDay: String {
        HomeV2Logic.newYorkDateString(from: selectedDate)
    }

    /// Row ids and client_request_ids the card already shows from /today.
    private var peptideShownKeys: Set<String> {
        HomePeptideSummary.shownKeys(peptideToday)
    }

    private var peptideSectionVisible: Bool {
        if peptideError != nil { return true }
        if peptideStore.hasLocalActivity(today: peptideDay) { return true }
        guard let peptideToday else { return false }
        return HomeV2Logic.peptideCardVisible(
            hasActiveSchedules: peptideToday.hasActiveSchedules || activeScheduleCount > 0,
            plannedCount: peptideToday.planned.filter { !$0.voided }.count,
            completedCount: peptideToday.completed.filter { !$0.voided }.count
        )
    }

    private var weekDates: [Date] {
        let end = calendar.startOfDay(for: selectedDate)
        let weekday = calendar.component(.weekday, from: end)
        let daysBack = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -daysBack, to: end) ?? end
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekStrip: some View {
        HStack(spacing: 0) {
            Button {
                shiftWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous week")
            ForEach(weekDates, id: \.timeIntervalSince1970) { date in
                weekDay(date)
            }
            Button {
                shiftWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isFutureWeek)
            .accessibilityLabel("Next week")
        }
        .foregroundStyle(AppColors.calorie)
        // Nine fixed-width columns cannot grow with accessibility text: the
        // 32pt day circles truncated "28" to "…". Cap the compact strip; each
        // day still carries a full VoiceOver label.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var isFutureWeek: Bool {
        guard let next = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: selectedDate)) else {
            return true
        }
        return next > calendar.startOfDay(for: Date())
    }

    private func weekDay(_ date: Date) -> some View {
        let status = status(for: date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.narrow)))
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                Text(date.formatted(.dateTime.day()))
                    .font(.system(.body, design: .rounded, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(width: 32, height: 32)
                    .background { if isSelected { Circle().fill(AppColors.calorie) } }
                HStack(spacing: 2) {
                    statusMark("dumbbell.fill", on: status.lifted)
                    statusMark("figure.walk", on: status.stepsHit)
                    statusMark("fork.knife", on: status.foodLogged)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(weekAccessibility(date, status: status))
    }

    private func statusMark(_ systemName: String, on value: Bool?) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(value == true ? AppColors.calorie : Color.secondary.opacity(value == nil ? 0 : 0.35))
            .opacity(value == nil ? 0 : 1)
    }

    private func status(for date: Date) -> HomeV2Logic.WeekDayStatus {
        let key = SessionDateFormatting.calendarDateString(from: date, calendar: calendar)
        let workout: Bool? = workoutsLoaded
            ? workouts.contains { String($0.sessionDate.prefix(10)) == key }
            : nil
        let steps = stepsByDay?[calendar.startOfDay(for: date)]
        let stepsValue: Int? = stepsByDay == nil ? nil : (steps ?? 0)
        return HomeV2Logic.weekDayStatus(
            workoutLogged: workout,
            steps: stepsValue,
            stepsTarget: stepsTarget,
            foodEntries: foodStore.entries(for: date).count
        )
    }

    private func weekAccessibility(_ date: Date, status: HomeV2Logic.WeekDayStatus) -> String {
        let day = date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return "\(day), workout \(markWord(status.lifted)), steps \(markWord(status.stepsHit)), food \(markWord(status.foodLogged))"
    }

    private func markWord(_ value: Bool?) -> String {
        switch value {
        case true: "done"
        case false: "not done"
        case nil: "unknown"
        }
    }

    private func shiftWeek(by delta: Int) {
        guard let next = calendar.date(byAdding: .day, value: delta * 7, to: selectedDate) else { return }
        if delta > 0 && calendar.startOfDay(for: next) > calendar.startOfDay(for: Date()) { return }
        selectedDate = next
    }

    private var todayCard: some View {
        let key = SessionDateFormatting.calendarDateString(from: selectedDate, calendar: calendar)
        let logged = workouts.first { String($0.sessionDate.prefix(10)) == key }
        return VStack(alignment: .leading, spacing: 8) {
            if let logged {
                loggedSummary(logged)
            } else if let programBody {
                plannedSession(programBody)
            } else {
                Text("No active program. Home loads it from the bridge.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
            }
            if let programNotice {
                Text(programNotice)
                    .font(.caption)
                    .foregroundStyle(IronTheme.bloodText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if todayShowsRule {
                Rectangle()
                    .fill(IronTheme.blood)
                    .frame(width: IronTheme.ruleWidth)
                    .padding(.vertical, -12)
                    .padding(.leading, -16)
            }
        }
    }

    private var todaySurface: Color {
        if case .rest = selectedResolution { return IronTheme.concrete }
        return IronTheme.surface
    }

    private var todayShowsRule: Bool {
        let key = SessionDateFormatting.calendarDateString(from: selectedDate, calendar: calendar)
        if workouts.contains(where: { String($0.sessionDate.prefix(10)) == key }) { return true }
        if case .session = selectedResolution { return true }
        return false
    }

    private var selectedResolution: ResolvedTrainingDay? {
        guard let programBody else { return nil }
        return TrainingProgramSchedule.resolve(programBody, on: selectedDate, calendar: calendar)
    }

    @ViewBuilder
    private func loggedSummary(_ logged: RemoteWorkout) -> some View {
        Text(logged.title.isEmpty ? logged.programDay : logged.title)
            .font(.system(.title3, design: .rounded, weight: .bold))
        if let sessionDetail, sessionDetail.workout.id == logged.id {
            let summary = HomeV2Logic.sessionSummary(
                sets: sessionDetail.sets.map { ($0.exercise, $0.loadLb, $0.reps) }
            )
            Text("\(summary.exercises.count) exercises · \(summary.totalSets) sets")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            ForEach(summary.exercises, id: \.exercise) { exercise in
                Text("\(exercise.exercise) · \(exercise.sets) sets · top \(HomeV2Logic.storedNumber(exercise.topLoadLb)) lb × \(exercise.topReps)")
                    .font(.system(.footnote, design: .rounded))
            }
        } else {
            Text("Logged")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func plannedSession(_ programBody: TrainingProgramBody) -> some View {
        let resolved = TrainingProgramSchedule.resolve(programBody, on: selectedDate, calendar: calendar)
        switch resolved {
        case .session(_, let name, _):
            Text(name)
                .font(.system(.title3, design: .rounded, weight: .bold))
            if let day = TrainingProgramSchedule.programDay(in: programBody, matching: resolved) {
                let datedDay = programBody.programV2Day(for: day, on: selectedDate)
                if let weekNote = datedDay.weekNote {
                    Text(weekNote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("\(datedDay.exercises.count) exercises · \(datedDay.conditioning)")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                Button {
                    loggingDay = datedDay
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(IronCompactButtonStyle())
            }
        case .rest:
            Text("REST. WALK. 10K.")
                .font(.system(size: 22, weight: .black))
                .fontWidth(.condensed)
                .tracking(1.2)
                .foregroundStyle(IronTheme.textPrimary)
            if let next = resolved.nextLabel {
                Text("Next · \(next)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(IronTheme.textSecondary)
            }
        case .upcoming(let name, let weekday, _):
            Text(name)
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text(weekday)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var dailyTargets: some View {
        let profile = profileStore.profile
        let eaten = foodStore.calories(for: selectedDate)
        let remainder = HomeV2Logic.CalorieRemainder.resolve(eaten: eaten, target: profile.effectiveCalories)
        let protein = foodStore.protein(for: selectedDate)
        let steps = stepsByDay?[calendar.startOfDay(for: selectedDate)]
        let pace = steps.map {
            HomeV2Logic.stepsPace(steps: $0, target: stepsTarget, now: paceNow, calendar: calendar)
        }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Steps")
                    .font(.system(size: 13, weight: .heavy))
                    .fontWidth(.condensed)
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(IronTheme.textSecondary)
                if let steps {
                    HStack(alignment: .center, spacing: 12) {
                        stepsRing(steps: steps, pace: pace)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(steps.formatted()) / \(stepsTarget.formatted())")
                                .font(.system(.title3, weight: .bold).monospacedDigit())
                                .fontWidth(.condensed)
                                .foregroundStyle(IronTheme.textPrimary)
                            if let pace {
                                Text(paceLine(pace))
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(stepsToneColor(steps: steps, pace: pace))
                            }
                        }
                    }
                } else {
                    Text("Steps aren’t in Apple Health for this day.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(IronTheme.textSecondary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Protein")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(Int(protein.rounded())) / \(profile.effectiveProtein) g")
                    .font(.system(size: 28, weight: .bold).monospacedDigit())
                    .foregroundStyle(IronTheme.textPrimary)
            }
            HStack {
                calorieColumn("Eaten", remainder.eaten.formatted())
                calorieColumn("Target", remainder.target.formatted())
                calorieColumn(remainderCaption(remainder), remainder.kind == .met ? "0" : remainder.amount.formatted())
            }
            if let burnedCalories {
                Text("\(burnedCalories.formatted()) burned")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(compactMacros(profile: profile))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
            if waterTrackingEnabled {
                let unit = WaterUnit(rawValue: waterUnitRaw) ?? .defaultUnit
                Text("Water \(unit.formatted(milliliters: waterStore.total(on: selectedDate))) / \(unit.formatted(milliliters: waterDailyGoal))")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var paceNow: Date {
        calendar.isDateInToday(selectedDate) ? Date() : selectedDate
    }

    private func stepsRing(steps: Int, pace: HomeV2Logic.StepsPace?) -> some View {
        let color = pace.map { stepsToneColor(steps: steps, pace: $0) } ?? IronTheme.blood
        let progress = stepsTarget > 0 ? min(Double(steps) / Double(stepsTarget), 1) : 0
        return ZStack {
            Circle().stroke(IronTheme.hairline, lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }

    private func stepsToneColor(steps: Int, pace: HomeV2Logic.StepsPace) -> Color {
        switch HomeV2Logic.stepsRingTone(
            steps: steps,
            pace: pace,
            hour: calendar.component(.hour, from: paceNow),
            goal: stepsTarget
        ) {
        case .olive: IronTheme.olive
        case .rust: IronTheme.rust
        case .blood: IronTheme.blood
        }
    }

    private func paceLine(_ pace: HomeV2Logic.StepsPace) -> String {
        if pace.met { return "Target hit" }
        if pace.windowClosed { return "\(pace.remaining.formatted()) left after 10 PM" }
        if let perHour = pace.perHour {
            return "~\(perHour.formatted())/hr to finish by 10 PM"
        }
        return "\(pace.remaining.formatted()) left"
    }

    private func remainderCaption(_ remainder: HomeV2Logic.CalorieRemainder) -> String {
        switch remainder.kind {
        case .remaining: "Remaining"
        case .over: "Over"
        case .met: "Remaining"
        }
    }

    private func calorieColumn(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.headline, weight: .semibold).monospacedDigit())
                .foregroundStyle(IronTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactMacros(profile: UserProfile) -> String {
        let goals = OptionalNutrientGoals.decoded(from: optionalNutrientGoalsData)
        let carbs = Int(foodStore.carbs(for: selectedDate).rounded())
        let fat = Int(foodStore.fat(for: selectedDate).rounded())
        let fiber = Int(foodStore.fiber(for: selectedDate).rounded())
        let fiberGoal = goals.goal(for: .fiber)
        return "Carbs \(carbs)/\(profile.effectiveCarbs) g · Fat \(fat)/\(profile.effectiveFat) g · Fiber \(fiber)/\(fiberGoal) g"
    }

    private var bodyTrend: some View {
        let ending = calendar.startOfDay(for: selectedDate)
        let weight = HomeV2Logic.windowTrend(samples: readings(weightSamples), ending: ending, calendar: calendar)
        let fat = HomeV2Logic.windowTrend(samples: readings(fatSamples, scale: 100), ending: ending, calendar: calendar)
        let lean = HomeV2Logic.windowTrend(samples: readings(leanSamples), ending: ending, calendar: calendar)
        return VStack(alignment: .leading, spacing: 8) {
            if !bodyLoaded {
                Text("Reading Apple Health…")
                    .foregroundStyle(.secondary)
            } else if weight.current == nil && fat.current == nil && lean.current == nil {
                Text("No weight, body fat, or lean mass in Apple Health for the last 7 days. A Withings weigh-in shows up here after it syncs to Apple Health.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                trendLine("Weight", trend: weight, unit: "lb", digits: 1)
                trendLine("Body fat", trend: fat, unit: "%", digits: 1)
                trendLine("Lean mass", trend: lean, unit: "lb", digits: 1)
                if let caption = HomeV2Logic.recompCaption(weightChangeLb: weight.change, leanChangeLb: lean.change) {
                    Text(caption)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
                if weight.sparkline.count > 1 {
                    Chart(weight.sparkline, id: \.date) { point in
                        LineMark(x: .value("Day", point.date), y: .value("lb", point.value))
                            .foregroundStyle(AppColors.calorie)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 48)
                    .accessibilityLabel("Weight sparkline")
                }
                if let source = weightSamples.last?.sourceName ?? leanSamples.last?.sourceName ?? fatSamples.last?.sourceName {
                    Text(source)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func readings(_ samples: [HealthSampleReading], scale: Double = 1) -> [HomeV2Logic.DatedValue] {
        samples.map { HomeV2Logic.DatedValue(date: $0.date, value: $0.value * scale) }
    }

    private func trendLine(_ title: String, trend: HomeV2Logic.WindowTrend, unit: String, digits: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            if let current = trend.current {
                Text("\(format(current, digits: digits)) \(unit) 7-day average")
                    .font(.system(.headline, design: .rounded))
                if let change = trend.change {
                    Text("\(signed(change, digits: digits)) \(unit) vs prior 7 days")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No prior 7-day average yet.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No \(title.lowercased()) in Apple Health for the last 7 days.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !recoveryLoaded {
                Text("Reading Apple Health…")
                    .foregroundStyle(.secondary)
            } else {
                if let asleepSeconds {
                    Text("Sleep \(sleepClock(asleepSeconds)) asleep")
                        .font(.system(.headline, design: .rounded))
                    if let rule = HomeV2Logic.poorSleepRuleIfShort(asleepSeconds: asleepSeconds, notes: programBody?.notes) {
                        Text(rule)
                            .font(.system(.footnote, design: .rounded))
                    }
                } else {
                    Text("No sleep in Apple Health for last night.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if let restingHeartRate {
                    Text("Resting heart rate \(Int(restingHeartRate.rounded())) bpm")
                        .font(.system(.subheadline, design: .rounded))
                } else {
                    Text("No resting heart rate in Apple Health for this day.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                hrvLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hrvLine: some View {
        let ending = calendar.startOfDay(for: selectedDate)
        let today = hrvSamples.filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }.max { $0.date < $1.date }
        let prior = hrvSamples.filter { $0.date < ending }
        let baseline = HomeV2Logic.windowTrend(
            samples: prior.map { HomeV2Logic.DatedValue(date: $0.date, value: $0.value * 1000) },
            ending: calendar.date(byAdding: .day, value: -1, to: ending) ?? ending,
            calendar: calendar
        ).current
        return VStack(alignment: .leading, spacing: 2) {
            if let today {
                let milliseconds = Int((today.value * 1000).rounded())
                Text("HRV \(milliseconds) ms")
                    .font(.system(.subheadline, design: .rounded))
                if let baseline {
                    Text("7-day baseline \(Int(baseline.rounded())) ms")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No 7-day HRV baseline yet.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No HRV in Apple Health for this day.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var weekSoFarCard: some View {
        let proteinDays = Dictionary(uniqueKeysWithValues: weekDates.map { date in
            (SessionDateFormatting.calendarDateString(from: date, calendar: calendar), foodStore.protein(for: date))
        })
        let stepDays = Dictionary(uniqueKeysWithValues: (stepsByDay ?? [:]).map { date, steps in
            (SessionDateFormatting.calendarDateString(from: date, calendar: calendar), steps)
        })
        let snapshot = HomeV2Logic.weekSoFar(
            today: selectedDate,
            calendar: calendar,
            trainingDaysPerWeek: programBody?.days.count ?? 0,
            workoutCivilDates: workouts.map(\.sessionDate),
            stepsByCivilDate: stepDays,
            stepsTarget: stepsTarget,
            proteinByCivilDate: proteinDays,
            programStartDate: programBody?.startDate,
            reductionWeek: programBody?.reductionWeek
        )
        return VStack(alignment: .leading, spacing: 6) {
            Text("Sessions \(snapshot.sessionsDone) / \(snapshot.sessionsScheduled)")
                .font(.system(.headline, design: .rounded))
            Text("Step days \(snapshot.stepDaysHit) / \(snapshot.daysElapsed)")
                .font(.system(.subheadline, design: .rounded))
            if let average = snapshot.averageProtein {
                Text("Avg protein \(Int(average.rounded())) g")
                    .font(.system(.subheadline, design: .rounded))
            } else {
                Text("No food logged this week.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if let milestone = snapshot.milestone {
                Text(milestone)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(IronTheme.rust)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var peptideCard: some View {
        if let peptideError {
            Text(peptideError)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(AppColors.calorie)
        } else if let peptideToday {
            VStack(alignment: .leading, spacing: 12) {
                let planned = peptideToday.planned.filter { !$0.voided }
                if planned.isEmpty {
                    Text("Nothing scheduled today.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                ForEach(planned) { row in
                    peptideRow(row, completed: peptideToday.completed)
                }
                ForEach(peptideToday.completed.filter { !$0.voided && $0.plannedId == nil }) { row in
                    completedRow(row)
                }
                Button("Log a dose I type") {
                    showingPeptideLog = true
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func peptideRow(_ row: PeptideAdministration, completed: [PeptideAdministration]) -> some View {
        let match = completed.first { $0.id == row.completedId }
        let inventory = inventoryItem(for: row)
        return VStack(alignment: .leading, spacing: 4) {
            Text(row.compound.isEmpty ? "Dose" : row.compound)
                .font(.system(.headline, design: .rounded))
            Text(doseLine(row))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            if let when = HomeV2Logic.displayNewYork(iso8601: row.datetime) {
                Text(when)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            volumeText(row, inventory: inventory)
            badgeList(row.badges + (inventory?.badges ?? []))
            warningList(inventory?.warnings ?? [])
            if let match {
                Text("Taken \(HomeV2Logic.displayNewYork(iso8601: match.datetime) ?? match.datetime)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                // Only rows this app recorded can be corrected or voided.
                if match.recordedVia == "app" {
                    Button("Correct or void") { peptideAction = .edit(match) }
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                }
            } else if row.completedId == nil {
                Button("Mark taken") { peptideAction = .mark(row) }
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.calorie)
            }
        }
    }

    private func completedRow(_ row: PeptideAdministration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.compound)
                .font(.system(.headline, design: .rounded))
            Text(doseLine(row))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            if let when = HomeV2Logic.displayNewYork(iso8601: row.datetime) {
                Text("Taken \(when)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            volumeText(row, inventory: inventoryItem(for: row))
            badgeList(row.badges)
            if row.recordedVia == "app" {
                Button("Correct or void") { peptideAction = .edit(row) }
                    .font(.system(.caption, design: .rounded, weight: .semibold))
            }
        }
    }

    private func doseLine(_ row: PeptideAdministration) -> String {
        let amount = row.dose.map(HomeV2Logic.storedNumber) ?? ""
        let units = row.units ?? ""
        return [amount, units].filter { !$0.isEmpty }.joined(separator: " ")
    }

    @ViewBuilder
    private func volumeText(_ row: PeptideAdministration, inventory: PeptideInventoryItem?) -> some View {
        let state = HomeV2Logic.volumeState(
            volume: row.volume,
            volumeUnits: row.volumeUnits,
            volumeBasis: row.volumeBasis,
            calcGate: row.calcGate ?? inventory?.calcGate,
            concentrationBasis: row.concentrationBasis ?? inventory?.concentrationBasis
        )
        switch state {
        case .unavailable:
            Text(HomeV2Logic.volumeUnavailableText)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
        case .shown(let amount, let units):
            Text([amount, units].filter { !$0.isEmpty }.joined(separator: " "))
                .font(.system(.footnote, design: .rounded))
        }
    }

    private func badgeList(_ badges: [String]) -> some View {
        var seen = Set<String>()
        var unique: [String] = []
        for badge in badges where !badge.isEmpty && seen.insert(badge).inserted {
            unique.append(badge)
        }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(unique, id: \.self) { badge in
                Text(badge)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.calorie.opacity(0.12), in: Capsule())
            }
        }
    }

    private func warningList(_ warnings: [PeptideWarning]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                Text(warning.text)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(AppColors.calorie)
            }
        }
    }

    private func inventoryItem(for row: PeptideAdministration) -> PeptideInventoryItem? {
        if let source = row.sourceVial, let match = peptideInventory.first(where: { $0.id == source }) {
            return match
        }
        return nil
    }

    private func format(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }

    private func signed(_ value: Double, digits: Int) -> String {
        let number = format(abs(value), digits: digits)
        if value > 0 { return "+\(number)" }
        if value < 0 { return "−\(number)" }
        return number
    }

    private func sleepClock(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }

    private func reloadLayout() {
        let stored = HomeCardLayout.load()
        order = stored.order
        hidden = stored.hidden
    }

    private func reload() async {
        reloadLayout()
        await reloadProgram()
        await reloadWorkouts()
        await reloadHealth()
        await reloadPeptides()
    }

    private func reloadProgram() async {
        do {
            let record = try await bridge.activeProgram()
            if record.body != nil {
                ActiveProgramCache.save(record)
                programRecord = record
                allowCachedProgram = true
                programNotice = nil
                return
            }
        } catch let error as NeonBridgeError where error.isNotFound {
            programRecord = nil
            allowCachedProgram = false
            programNotice = "No active program on the bridge."
        } catch {
            programNotice = "Bridge unavailable"
            allowCachedProgram = true
            if programRecord == nil, let cached = ActiveProgramCache.load() {
                programRecord = cached
            }
        }
    }

    private func reloadWorkouts() async {
        do {
            let listed = try await bridge.listWorkouts(limit: 50)
            workouts = listed
            workoutsLoaded = true
            let key = SessionDateFormatting.calendarDateString(from: selectedDate, calendar: calendar)
            if let match = listed.first(where: { String($0.sessionDate.prefix(10)) == key }) {
                sessionDetail = try? await bridge.getWorkout(id: match.id)
            } else {
                sessionDetail = nil
            }
        } catch {
            workoutsLoaded = false
        }
    }

    private func reloadHealth() async {
        let week = weekDates
        guard let first = week.first, let last = week.last else { return }
        stepsByDay = await healthKitManager.fetchStepsByDay(from: first, through: last)
        if let energy = await healthKitManager.readEnergyForDay(selectedDate) {
            burnedCalories = DailySummaryPolicy.resolveBurnedCalories(
                measuredTotalCalories: energy.totalCalories,
                externalActiveCalories: energy.activeCalories,
                profileBmrCalories: Int(profileStore.profile.bmr.rounded())
            )
        } else {
            burnedCalories = nil
        }
        let ending = selectedDate
        let start = calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: ending)) ?? ending
        weightSamples = await healthKitManager.fetchSamples(.bodyMass, unit: .pound(), from: start, through: ending) ?? []
        fatSamples = await healthKitManager.fetchSamples(.bodyFatPercentage, unit: .percent(), from: start, through: ending) ?? []
        leanSamples = await healthKitManager.fetchSamples(.leanBodyMass, unit: .pound(), from: start, through: ending) ?? []
        bodyLoaded = true
        asleepSeconds = await healthKitManager.fetchAsleepSeconds(on: selectedDate)
        restingHeartRate = await latestBeatsPerMinute(on: selectedDate)
        let hrvStart = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: selectedDate)) ?? selectedDate
        hrvSamples = await healthKitManager.fetchSamples(
            .heartRateVariabilitySDNN,
            unit: .second(),
            from: hrvStart,
            through: selectedDate
        ) ?? []
        recoveryLoaded = true
    }

    private func latestBeatsPerMinute(on date: Date) async -> Double? {
        let samples = await healthKitManager.fetchSamples(
            .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            from: date,
            through: date
        )
        return samples?.max { $0.date < $1.date }?.value
    }

    private func reloadPeptides() async {
        let day = HomeV2Logic.newYorkDateString(from: selectedDate)
        do {
            peptideToday = try await bridge.peptidesToday(date: day)
            peptideError = nil
            activeScheduleCount = (try? await bridge.peptideSchedules(activeOnly: true).count) ?? activeScheduleCount
            if let inventory = try? await bridge.peptideInventory() {
                peptideInventory = inventory
            }
        } catch {
            if case NeonBridgeError.httpError(let statusCode, _) = error, statusCode == 401 || statusCode == 503 {
                peptideError = "Add the bridge key in Train › Bridge to sync peptides."
            } else {
                peptideError = "Peptide schedule couldn’t be loaded."
            }
        }
        await peptideStore.refreshIfStale()
    }
}

private struct CustomizeHomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var order: [HomeCardID]
    @State var hidden: Set<HomeCardID>
    var onSave: ([HomeCardID], Set<HomeCardID>) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(order) { card in
                    Toggle(card.title, isOn: Binding(
                        get: { !hidden.contains(card) },
                        set: { isOn in
                            if isOn { hidden.remove(card) } else { hidden.insert(card) }
                        }
                    ))
                    .tint(AppColors.calorie)
                }
                .onMove { source, destination in
                    order.move(fromOffsets: source, toOffset: destination)
                }
            }
            .navigationTitle("Customize Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(order, hidden)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Peptides stays off Home until a dose is on the schedule. Drag to reorder.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
}

private enum PeptideAction: Identifiable {
    case mark(PeptideAdministration)
    case edit(PeptideAdministration)
    case unscheduled

    var id: String {
        switch self {
        case .mark(let row): "mark-\(row.id)"
        case .edit(let row): "edit-\(row.id)"
        case .unscheduled: "unscheduled"
        }
    }
}

private struct PeptideActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PeptideLogStore.self) private var peptideStore
    let action: PeptideAction
    var onFinished: () -> Void

    @State private var takenAt = Date()
    @State private var doseText = ""
    @State private var compound = ""
    @State private var units = ""
    @State private var notes = ""
    @State private var reason = ""
    @State private var errorText: String?
    @State private var isSaving = false
    @State private var clientRequestID = UUID().uuidString

    private let bridge = NeonBridgeService.shared

    var body: some View {
        NavigationStack {
            Form {
                switch action {
                case .mark(let row):
                    Text(row.compound)
                    DatePicker("Time", selection: $takenAt)
                    TextField("Dose", text: $doseText)
                        .keyboardType(.decimalPad)
                    Text("Units stay \(row.units ?? "as stored"). Editing the dose leaves volume unset.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("Notes", text: $notes, axis: .vertical)
                case .unscheduled:
                    TextField("Compound", text: $compound)
                    TextField("Dose", text: $doseText)
                        .keyboardType(.decimalPad)
                    TextField("Units", text: $units)
                    DatePicker("Time", selection: $takenAt)
                    TextField("Notes", text: $notes, axis: .vertical)
                    Text("Type the dose you took. Volume can’t be calculated for a dose that isn’t on the schedule.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .edit(let row):
                    Text(row.compound)
                    DatePicker("Time", selection: $takenAt)
                    TextField("Dose", text: $doseText)
                        .keyboardType(.decimalPad)
                    TextField("Notes", text: $notes, axis: .vertical)
                    TextField("Reason", text: $reason)
                    Button("Void this dose", role: .destructive) {
                        Task { await voidDose(row) }
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private var title: String {
        switch action {
        case .mark: "Mark taken"
        case .edit: "Correct dose"
        case .unscheduled: "Log a dose"
        }
    }

    private func prefill() {
        switch action {
        case .mark(let row):
            doseText = row.dose.map(HomeV2Logic.storedNumber) ?? ""
            notes = row.notes ?? ""
        case .edit(let row):
            doseText = row.dose.map(HomeV2Logic.storedNumber) ?? ""
            notes = row.notes ?? ""
            if let date = parseISO(row.datetime) { takenAt = date }
        case .unscheduled:
            break
        }
    }

    private func save() async {
        switch action {
        case .mark(let row):
            await markTaken(row)
        case .unscheduled:
            await logUnscheduled()
        case .edit(let row):
            await correct(row)
        }
    }

    private func markTaken(_ row: PeptideAdministration) async {
        isSaving = true
        defer { isSaving = false }
        let typed = Double(doseText.replacingOccurrences(of: ",", with: "."))
        let planned = row.dose
        let doseChanged = typed != nil && planned != nil && abs((typed ?? 0) - (planned ?? 0)) > 0.000_1
        // Queued through the Peptides log so it survives being offline.
        let opID = peptideStore.logPlanned(
            plannedID: row.id,
            takenAt: takenAt,
            dose: doseChanged ? typed : nil,
            notes: notes,
            clientRequestID: clientRequestID
        )
        await peptideStore.flush()
        if let message = peptideStore.failureMessage(forOp: opID) {
            errorText = message
            return
        }
        onFinished()
        dismiss()
    }

    private func logUnscheduled() async {
        let trimmedCompound = compound.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUnits = units.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCompound.isEmpty, !trimmedUnits.isEmpty, let dose = Double(doseText.replacingOccurrences(of: ",", with: ".")) else {
            errorText = "Type the compound, dose, and units."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await bridge.createCompletedAdministration(
                clientRequestID: clientRequestID,
                plannedID: nil,
                datetime: HomeV2Logic.iso8601NewYork(takenAt),
                dose: dose,
                units: trimmedUnits,
                compound: trimmedCompound,
                route: nil,
                notes: notes.isEmpty ? nil : notes,
                sourceVial: nil
            )
            onFinished()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func correct(_ row: PeptideAdministration) async {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            errorText = "A reason is required."
            return
        }
        var changes = PeptideCorrectionChanges(datetime: HomeV2Logic.iso8601NewYork(takenAt))
        if let dose = Double(doseText.replacingOccurrences(of: ",", with: ".")) {
            changes.dose = dose
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty { changes.notes = trimmedNotes }
        isSaving = true
        defer { isSaving = false }
        // Queued through the Peptides log so it survives being offline.
        if let message = peptideStore.correct(rowID: row.id, recordedVia: row.recordedVia, reason: trimmedReason, changes: changes) {
            errorText = message
            return
        }
        await peptideStore.flush()
        if let message = peptideStore.failureMessage(forRow: row.id) {
            errorText = message
            return
        }
        onFinished()
        dismiss()
    }

    private func voidDose(_ row: PeptideAdministration) async {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        if let message = peptideStore.void(rowID: row.id, recordedVia: row.recordedVia, reason: trimmedReason) {
            errorText = message
            return
        }
        await peptideStore.flush()
        if let message = peptideStore.failureMessage(forRow: row.id) {
            errorText = message
            return
        }
        onFinished()
        dismiss()
    }

    private func parseISO(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
