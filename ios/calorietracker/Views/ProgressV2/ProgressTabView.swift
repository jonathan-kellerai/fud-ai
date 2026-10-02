import SwiftUI

// MARK: - Progress Tab

/// Progress: body composition (weight, body fat, lean mass) with 7-day trends,
/// latest readings, steps from Apple Health, training volume from the Neon
/// bridge, workout burn, and nutrition averages for one selected range.
///
/// Heavy work (series, trends, downsampling, nutrition) runs in `.task(id:)`
/// keyed by the range and the data counts, never in `body`.
struct ProgressTabView: View {
    @Environment(FoodStore.self) private var foodStore
    @Environment(WeightStore.self) private var weightStore
    @Environment(BodyFatStore.self) private var bodyFatStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(StrengthWorkoutStore.self) private var strengthWorkoutStore
    @Environment(ImportedHealthWorkoutStore.self) private var importedHealthWorkoutStore
    @Environment(HealthKitManager.self) private var healthKitManager
    @AppStorage("weightUnit") private var weightUnitRaw = "lbs"

    @State private var timeRange: TimeRange
    @State private var metric: ProgressCompositionMetric
    @State private var composition: ProgressCompositionSnapshot?
    @State private var steps: ProgressStepsLoadState = .loading
    @State private var training: ProgressTrainingLoadState = .idle
    @State private var trainingRefreshToken = 0
    @State private var stepsRefreshToken = 0
    @State private var compositionRefreshToken = 0
    @State private var forceTrainingRefresh = false
    @State private var showLogWeight = false
    @State private var showLogBodyFat = false
    @State private var showGoalReached = false
    @State private var showAllWeights = false
    @State private var showAllBodyFat = false
    @State private var showWorkoutHistory = false
    @State private var showImportedHealthWorkoutHistory = false
    @State private var foodRangeStats: ProgressFoodRangeStats?
    @State private var isLoadingFoodRangeStats = false

    /// Set only by snapshot tests; replaces store, HealthKit and bridge data.
    private let fixture: ProgressV2Fixture?

    init() {
        fixture = nil
        _timeRange = State(initialValue: .week)
        _metric = State(initialValue: .weight)
    }

    /// Renders fixed data without touching HealthKit or the Neon bridge.
    init(fixture: ProgressV2Fixture) {
        self.fixture = fixture
        _timeRange = State(initialValue: fixture.timeRange)
        _metric = State(initialValue: fixture.metric)
        _training = State(initialValue: fixture.training)
    }

    // MARK: - Data

    private var userProfile: UserProfile { profileStore.profile }
    private var useMetric: Bool { weightUnitRaw == "kg" }

    /// All weight rows, lean mass included (Weight History lists both).
    private var weightRows: [WeightEntry] { fixture?.weightEntries ?? weightStore.entries }
    private var bodyFatRows: [BodyFatEntry] { fixture?.bodyFatEntries ?? bodyFatStore.entries }

    /// "Now" and the calendar for every window on the tab. Snapshot fixtures
    /// pin both so the view and the fixture data agree on today.
    private var referenceNow: Date { fixture?.now ?? .now }
    private var referenceCalendar: Calendar { fixture?.calendar ?? .current }

    private var dayStamp: Int {
        Int(referenceCalendar.startOfDay(for: referenceNow).timeIntervalSince1970)
    }

    /// Covers every row, so an edit to an older reading (or a lean-mass flag)
    /// rebuilds the snapshot, not just an added or removed last row.
    private var compositionTaskKey: String {
        let rows = ProgressCompositionBuilder.fingerprint(weightRows: weightRows, bodyFatRows: bodyFatRows)
        return "\(timeRange.rawValue)|\(weightUnitRaw)|\(rows)|\(dayStamp)|\(compositionRefreshToken)"
    }

    private var stepsTaskKey: String {
        "\(timeRange.rawValue)|\(dayStamp)|\(stepsRefreshToken)"
    }

    private var trainingTaskKey: String {
        "\(timeRange.rawValue)|\(dayStamp)|\(trainingRefreshToken)"
    }

    private var foodRangeStatsTaskKey: String {
        let latest = foodStore.entries.first?.id.uuidString ?? "none"
        return "\(timeRange.rawValue)|\(foodStore.entries.count)|\(latest)|\(dayStamp)"
    }

    private var workoutCalorieSessions: [StrengthWorkoutSession] {
        strengthWorkoutStore.completedSessions.filter {
            WorkoutBurnAggregation.isReliable($0.caloriesBurned)
        }
    }

    private var importedHealthWorkouts: [ImportedHealthWorkout] {
        importedHealthWorkoutStore.sortedWorkouts
    }

    /// All reaches back to the earliest workout instead of the body data.
    private var workoutRange: ClosedRange<Date> {
        let window = ProgressV2Math.window(for: timeRange, now: referenceNow, calendar: referenceCalendar, earliestData: nil)
        if timeRange == .allTime {
            return Date.distantPast...window.closedRange.upperBound
        }
        return window.closedRange
    }

    // MARK: - Body

    var body: some View {
        if let fixture {
            content
                .environment(\.locale, fixture.locale)
                .environment(\.calendar, fixture.calendar)
                .environment(\.timeZone, fixture.calendar.timeZone)
        } else {
            content
        }
    }

    private var content: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    ProgressV2SegmentedControl(
                        options: TimeRange.allCases,
                        selection: $timeRange,
                        label: { $0.rawValue },
                        accessibilityLabel: String(localized: "Time range"),
                        accessibilityColumns: 3,
                        compactColumns: 3,
                        spokenLabel: { Self.spokenRange($0) }
                    )

                    ProgressCompositionCard(
                        metric: $metric,
                        snapshot: composition,
                        goalWeightKg: userProfile.goalWeightKg,
                        goalBodyFatFraction: userProfile.goalBodyFatPercentage,
                        onLogWeight: { showLogWeight = true },
                        onLogBodyFat: { showLogBodyFat = true }
                    )

                    historyLinks

                    if let composition {
                        ProgressBodySummaryCard(snapshot: composition)
                    }

                    ProgressStepsCard(
                        state: steps,
                        rangeDescription: ProgressV2Math.stepsRangeDescription(timeRange),
                        goal: StepsView.dailyGoal,
                        windowNote: timeRange == .allTime
                            ? String(localized: "All shows the last 2 years of Apple Health steps.")
                            : nil
                    )

                    ProgressTrainingCard(
                        state: training,
                        rangeDescription: timeRange.rangeDescription,
                        useMetric: useMetric,
                        onRetry: retryTraining
                    )

                    workoutsSection

                    nutritionSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(IronTheme.canvas)
            .refreshable { await refresh() }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: compositionTaskKey) {
                await Task.yield()
                let snapshot = ProgressCompositionBuilder.build(
                    weightRows: weightRows,
                    bodyFatRows: bodyFatRows,
                    range: timeRange,
                    useMetric: useMetric,
                    now: referenceNow,
                    calendar: referenceCalendar
                )
                guard !Task.isCancelled else { return }
                composition = snapshot
            }
            .task(id: stepsTaskKey) {
                await loadSteps()
            }
            .task(id: trainingTaskKey) {
                await loadTraining()
            }
            .task(id: foodRangeStatsTaskKey) {
                isLoadingFoodRangeStats = true
                // Drop stale nutrition for a different range so charts don't lie
                // while a longer window is still computing. Switching ranges
                // cancels this task immediately via task(id:).
                foodRangeStats = nil
                // Let the picker / loading card paint before the single-pass work.
                await Task.yield()
                let dayCount: Int
                if timeRange == .allTime {
                    let earliest = foodStore.entries.map(\.timestamp).min()
                    dayCount = ProgressV2Math.window(for: .allTime, now: referenceNow, calendar: referenceCalendar, earliestData: earliest)
                        .dayCount(calendar: referenceCalendar)
                } else {
                    dayCount = timeRange.days
                }
                let stats = ProgressFoodRangeStats.compute(
                    entries: foodStore.entries,
                    dayCount: dayCount,
                    profile: userProfile,
                    optionalGoals: .current,
                    now: referenceNow,
                    calendar: referenceCalendar
                )
                guard !Task.isCancelled else { return }
                foodRangeStats = stats
                isLoadingFoodRangeStats = false
            }
            .sheet(isPresented: $showLogWeight) {
                LogWeightSheet(
                    currentWeightKg: weightStore.latestEntry?.weightKg ?? userProfile.weightKg,
                    previous: weightStore.latestEntry
                ) { weightKg in
                    weightStore.addEntry(WeightEntry(weightKg: weightKg))
                }
            }
            .sheet(isPresented: $showLogBodyFat) {
                // Seed from latest entry → profile current → sane default,
                // mirroring the LogWeightSheet seeding chain.
                let seed = bodyFatStore.latestEntry?.bodyFatFraction
                    ?? userProfile.bodyFatPercentage
                    ?? 0.20
                LogBodyFatSheet(
                    currentFraction: seed,
                    previousFraction: bodyFatStore.latestEntry?.bodyFatFraction,
                    previousDate: bodyFatStore.latestEntry?.date
                ) { fraction in
                    bodyFatStore.addEntry(BodyFatEntry(bodyFatFraction: fraction))
                }
            }
            .alert("Congratulations!", isPresented: $showGoalReached) {
                Button("Keep Going", role: .cancel) { }
            } message: {
                Text("You've reached your goal weight! Head to Settings to switch your goal (Maintain, Lose, or Gain) and tap Recalculate Goals to refresh your targets.")
            }
            .onReceive(NotificationCenter.default.publisher(for: .weightGoalReached)) { _ in
                showGoalReached = true
            }
            .sheet(isPresented: $showAllWeights) {
                AllWeightHistoryView(
                    entries: weightStore.entries.sorted { $0.date > $1.date },
                    useMetric: weightUnitRaw == "kg",
                    onDelete: { entry in weightStore.deleteEntry(entry) }
                )
            }
            .sheet(isPresented: $showAllBodyFat) {
                AllBodyFatHistoryView(
                    entries: bodyFatStore.entries.sorted { $0.date > $1.date },
                    onDelete: { entry in bodyFatStore.deleteEntry(entry) }
                )
            }
            .sheet(isPresented: $showWorkoutHistory) {
                WorkoutHistoryView(
                    sessions: workoutCalorieSessions,
                    onDelete: { session in
                        strengthWorkoutStore.deleteSession(session.id)
                    }
                )
            }
            .sheet(isPresented: $showImportedHealthWorkoutHistory) {
                ImportedHealthWorkoutHistoryView(workouts: importedHealthWorkouts)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Progress")
                .font(.system(.largeTitle, weight: .black))
                .fontWidth(.condensed)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let window = composition?.window, composition?.range == timeRange {
                Text(rangeSubtitle(window))
                    .font(.subheadline)
                    .foregroundStyle(IronTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var historyLinks: some View {
        if !weightRows.isEmpty {
            WeightHistoryLink(
                totalCount: weightRows.count,
                onTap: { showAllWeights = true }
            )
        }
        if !bodyFatRows.isEmpty {
            BodyFatHistoryLink(
                totalCount: bodyFatRows.count,
                onTap: { showAllBodyFat = true }
            )
        }
    }

    @ViewBuilder
    private var workoutsSection: some View {
        if !workoutCalorieSessions.isEmpty || !importedHealthWorkouts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ProgressV2SectionTitle(
                    title: String(localized: "Workout Burn & Health"),
                    detail: String(localized: "Calculated workout burn and Apple Health workouts.")
                )
                if !workoutCalorieSessions.isEmpty {
                    WorkoutBurnChartSection(
                        sessions: workoutCalorieSessions,
                        dateRange: workoutRange
                    )
                    WorkoutHistoryLink(
                        sessions: workoutCalorieSessions,
                        onTap: { showWorkoutHistory = true }
                    )
                }
                if !importedHealthWorkouts.isEmpty {
                    ImportedHealthWorkoutChartSection(
                        workouts: importedHealthWorkoutStore.workouts(
                            from: workoutRange.lowerBound,
                            through: workoutRange.upperBound
                        ),
                        dateRange: workoutRange
                    )
                    ImportedHealthWorkoutHistoryLink(
                        workouts: importedHealthWorkouts,
                        onTap: { showImportedHealthWorkoutHistory = true }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var nutritionSection: some View {
        // Calorie / macro / nutrient stats load asynchronously so the
        // range picker stays instant and interruptible mid-load.
        if let foodRangeStats {
            CalorieChartSection(
                dailyCalories: foodRangeStats.dailyCalories,
                calorieGoal: userProfile.effectiveCalories,
                rangeDescription: timeRange.rangeDescription
            )
            .opacity(isLoadingFoodRangeStats ? 0.45 : 1)

            MacroAveragesSection(
                avgProtein: foodRangeStats.avgProtein,
                avgCarbs: foodRangeStats.avgCarbs,
                avgFat: foodRangeStats.avgFat,
                proteinGoal: userProfile.effectiveProtein,
                carbsGoal: userProfile.effectiveCarbs,
                fatGoal: userProfile.effectiveFat,
                hasLoggedDays: foodRangeStats.loggedDays > 0
            )
            .opacity(isLoadingFoodRangeStats ? 0.45 : 1)

            if !foodRangeStats.nutrientItems.isEmpty {
                NutrientAveragesSection(items: foodRangeStats.nutrientItems)
                    .opacity(isLoadingFoodRangeStats ? 0.45 : 1)
            }
        } else {
            ProgressNutritionLoadingCard()
        }
    }

    // MARK: - Loading

    private func retryTraining() {
        forceTrainingRefresh = true
        trainingRefreshToken += 1
    }

    /// Pull to refresh: rebuild body composition, re-read Health steps and
    /// bypass the bridge caches (workout list and per-workout sets).
    private func refresh() async {
        retryTraining()
        stepsRefreshToken += 1
        compositionRefreshToken += 1
    }

    /// Steps never borrow body-composition dates; All is the last two years.
    private func loadSteps() async {
        let calendar = referenceCalendar
        let now = referenceNow
        let window = ProgressV2Math.stepsWindow(for: timeRange, now: now, calendar: calendar)
        let weekly = ProgressV2Math.usesWeeklyStepBars(timeRange)
        if let fixture {
            if let byDay = fixture.stepsByDay {
                steps = .loaded(ProgressV2Math.stepsSummary(
                    byDay: byDay,
                    window: window,
                    goal: StepsView.dailyGoal,
                    weekly: weekly,
                    calendar: calendar
                ))
            } else {
                steps = .unavailable
            }
            return
        }
        steps = .loading
        let byDay = await healthKitManager.fetchStepsByDay(from: window.start, through: now)
        guard !Task.isCancelled else { return }
        if let byDay {
            steps = .loaded(ProgressV2Math.stepsSummary(
                byDay: byDay,
                window: window,
                goal: StepsView.dailyGoal,
                weekly: weekly,
                calendar: calendar
            ))
        } else {
            steps = .unavailable
        }
    }

    private func loadTraining() async {
        if let fixture {
            training = fixture.training
            return
        }
        let force = forceTrainingRefresh
        forceTrainingRefresh = false
        training = .loading
        let result = await ProgressTrainingLoader.load(
            range: timeRange,
            forceRefresh: force,
            now: referenceNow
        )
        guard !Task.isCancelled else { return }
        training = result
    }

    // MARK: - Labels

    private static func spokenRange(_ range: TimeRange) -> String {
        switch range {
        case .week: String(localized: "1 week")
        case .month: String(localized: "1 month")
        case .threeMonths: String(localized: "3 months")
        case .sixMonths: String(localized: "6 months")
        case .year: String(localized: "1 year")
        case .allTime: String(localized: "All time")
        }
    }

    /// Uses the fixture's locale and calendar in snapshots, the user's otherwise.
    /// The tab sets the fixture environment on its content, so it reads the
    /// fixture directly rather than its own @Environment.
    private func rangeSubtitle(_ window: ProgressWindow) -> String {
        let start: String
        if let fixture {
            start = ProgressV2Format.mediumDate(
                window.start,
                locale: fixture.locale,
                calendar: fixture.calendar,
                timeZone: fixture.calendar.timeZone
            )
        } else {
            start = ProgressV2Format.mediumDate(window.start)
        }
        return String(localized: "\(start) – today")
    }
}
