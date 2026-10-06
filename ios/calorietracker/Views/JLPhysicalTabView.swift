//
//  JLPhysicalTabView.swift
//  calorietracker
//
//  JL Physical training tab with Program V2 integration
//

import SwiftUI

struct JLPhysicalTabView: View {
    @State private var programBody = TrainingProgramBody.bundledV2()
    @State private var bridgeNotice: String?
    @State private var showingPrograms = false
    @State private var loggingDay: ProgramV2Day?
    @State private var recentWorkouts: [RemoteWorkout] = []
    @State private var isLoadingRecent = false
    /// Set when the Coach handoff or Start finds an unsaved workout for another day.
    @State private var pendingResume: PendingResume?
    @State private var showingResumePrompt = false
    @State private var showingChangeWorkout = false
    
    private let routerHandoff = RouterHandoff.shared
    @Environment(WorkoutDraftStore.self) private var workoutDraftStore
    private var neonBridge = NeonBridgeService.shared
    /// Nil means "now". Visual QA snapshot tests pin a lifting day and a rest day.
    private let referenceDate: Date?
    @State private var trainMode: TrainMode
    /// Completed sessions and today's pick; Visual QA injects a seeded store.
    private let progress: TrainProgressStore

    init(referenceDate: Date? = nil, initialMode: TrainMode = .today, progress: TrainProgressStore = .shared) {
        self.referenceDate = referenceDate
        self.progress = progress
        _trainMode = State(initialValue: initialMode)
    }

    private var trainingContext: TrainingDayContext {
        progress.context(draft: workoutDraftStore.draft, days: programBody.days)
    }

    private var todayResolution: TrainingDayResolution {
        TrainingProgramSchedule.resolution(programBody, on: referenceDate ?? Date(), context: trainingContext)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let draft = workoutDraftStore.draft {
                        ResumeWorkoutCard(draft: draft) {
                            loggingDay = draft.programV2Day
                        }
                        .padding()
                        .ironCard(rule: true)
                    }
                    TodaysWorkoutCard(
                        resolution: todayResolution,
                        programBody: programBody,
                        date: referenceDate ?? Date(),
                        bridgeNotice: bridgeNotice,
                        onStart: { day in openLogger(for: day) },
                        onChangeWorkout: { showingChangeWorkout = true },
                        onBackToSuggested: { progress.clearOverride() }
                    )
                    quickActionsCard
                    recentWorkoutsSection
                }
                .padding()
            }
            // Overlay sits under the inset so the Today | Ladders switch stays on top.
            .overlay {
                if trainMode == .ladders {
                    CCLaddersView()
                        .background(IronTheme.canvas)
                }
            }
            .safeAreaInset(edge: .top) {
                TrainModeSwitch(mode: $trainMode)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(IronTheme.canvas)
            }
            .navigationTitle("Train")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingPrograms = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("Programs")
                }
            }
            .sheet(isPresented: $showingPrograms, onDismiss: {
                Task { await loadActiveProgram() }
            }) {
                NavigationStack {
                    ProgramLibraryView()
                }
            }
            .sheet(isPresented: $showingChangeWorkout) {
                ChangeWorkoutSheet(
                    options: TrainingProgramSchedule.workoutOptions(programBody, on: referenceDate ?? Date()),
                    suggestedDayIndex: TrainingProgramSchedule.suggestedDayIndex(
                        programBody, on: referenceDate ?? Date(), context: trainingContext),
                    currentDayIndex: todayResolution.dayIndex,
                    isChanged: todayResolution.isChanged,
                    onPick: { dayIndex in
                        progress.choose(dayIndex: dayIndex, in: programBody, on: referenceDate ?? Date(),
                                        draft: workoutDraftStore.draft)
                    },
                    onBackToSuggested: { progress.clearOverride() }
                )
            }
            .sheet(item: $loggingDay) { day in
                ProgramV2WorkoutLogView(day: day, progress: progress, onSaved: {
                    Task { await loadRecentWorkouts() }
                })
            }
            .confirmationDialog(
                "Unsaved Workout",
                isPresented: $showingResumePrompt,
                titleVisibility: .visible,
                presenting: pendingResume
            ) { pending in
                Button("Resume \(pending.draft.title)") {
                    loggingDay = pending.draft.programV2Day
                }
                Button("Discard and Start \(pending.today.title)", role: .destructive) {
                    workoutDraftStore.discard()
                    loggingDay = pending.today
                }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text("You have an unsaved \(pending.draft.title) session.")
            }
            .task {
                await loadActiveProgram()
                await loadRecentWorkouts()
                consumeWorkoutHandoff()
            }
            .onAppear {
                consumeWorkoutHandoff()
            }
            .onChange(of: routerHandoff.pendingOpenTodayWorkout) { _, _ in
                consumeWorkoutHandoff()
            }
        }
    }

    private func consumeWorkoutHandoff() {
        guard routerHandoff.pendingOpenTodayWorkout else { return }
        routerHandoff.pendingOpenTodayWorkout = false
        // The Ladders overlay would otherwise hide the logger or the resume prompt.
        trainMode = .today
        if let body = ActiveProgramCache.load()?.body {
            programBody = body
        }
        let resolved = TrainingProgramSchedule.resolve(programBody, on: referenceDate ?? Date(), context: trainingContext)
        guard let day = TrainingProgramSchedule.programDay(in: programBody, matching: resolved) else { return }
        openLogger(for: day)
    }

    /// Start and the Coach handoff: a draft for another day is offered back
    /// (resume or discard) instead of being replaced silently.
    private func openLogger(for day: TrainingProgramDay) {
        switch WorkoutHandoffDecision.decide(draft: workoutDraftStore.draft,
            today: workoutDraftStore.dayToOpen(day, in: programBody, on: referenceDate ?? Date())) {
        case .openToday(let today):
            loggingDay = today
        case .offerResume(let draft, let today):
            pendingResume = PendingResume(draft: draft, today: today)
            showingResumePrompt = true
        }
    }

    private struct PendingResume {
        let draft: WorkoutDraft
        let today: ProgramV2Day
    }

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
            
            HStack(spacing: 12) {
                NavigationLink(destination: StepsView()) {
                    QuickActionButton(icon: "figure.walk", title: "Steps", color: IronTheme.brass)
                }
                
                NavigationLink(destination: BridgeSettingsView()) {
                    QuickActionButton(icon: "server.rack", title: "Bridge", color: IronTheme.textSecondary)
                }
                
                NavigationLink(destination: WorkoutHistoryListView()) {
                    QuickActionButton(icon: "clock.arrow.circlepath", title: "History", color: IronTheme.bloodText)
                }
            }
        }
    }
    
    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Workouts")
                    .font(.headline)
                
                Spacer()
                
                NavigationLink(destination: WorkoutHistoryListView()) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.calorie)
                }
            }
            
            if isLoadingRecent {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if recentWorkouts.isEmpty {
                Text("No workouts logged yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(recentWorkouts.prefix(3), id: \.id) { workout in
                    RecentWorkoutRow(workout: workout)
                }
            }
        }
    }
    
    private func loadRecentWorkouts() async {
        isLoadingRecent = true
        defer { isLoadingRecent = false }
        
        do {
            // 20 rows cover the current program week for the next-in-cycle day.
            let workouts = try await neonBridge.listWorkouts(limit: 20)
            await MainActor.run {
                recentWorkouts = workouts
                progress.replaceHistory(with: workouts, days: programBody.days)
            }
        } catch {
            print("Failed to load recent workouts: \(error)")
        }
    }

    private func loadActiveProgram() async {
        do {
            let record = try await neonBridge.activeProgram()
            if let body = record.body {
                ActiveProgramCache.save(record)
                programBody = body
                bridgeNotice = nil
                return
            }
        } catch let error as NeonBridgeError where error.isNotFound {
            bridgeNotice = nil
        } catch {
            bridgeNotice = "Bridge unavailable"
        }

        if let cached = ActiveProgramCache.load(), let body = cached.body {
            programBody = body
            bridgeNotice = nil
        } else if bridgeNotice != nil {
            programBody = .bundledV2()
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            // Explicit bone-grey: `.secondary` inherits the NavigationLink tint
            // and rendered as low-contrast reddish-brown on iron black.
            Text(title)
                .font(.caption)
                .foregroundStyle(IronTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
        .padding(.horizontal, 8)
        .ironCard()
    }
}

struct RecentWorkoutRow: View {
    let workout: RemoteWorkout
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.programDay)
                    .font(.subheadline.bold())
                
                Text(SessionDateFormatting.displayString(from: workout.sessionDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if let conditioning = workout.conditioning {
                Image(systemName: "heart.fill")
                    .foregroundStyle(IronTheme.bloodText)
                    .font(.caption)
            }
        }
        .padding()
        .ironCard()
    }
}

struct WorkoutHistoryListView: View {
    @State private var workouts: [RemoteWorkout] = []
    @State private var isLoading = false
    
    private var neonBridge = NeonBridgeService.shared
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if workouts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No workouts yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            } else {
                List {
                    ForEach(workouts) { workout in
                        NavigationLink {
                            WorkoutHistoryEditView(workoutID: workout.id, onChanged: {
                                Task { await loadWorkouts() }
                            })
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.title)
                                    .font(.headline)
                                
                                Text(SessionDateFormatting.displayString(from: workout.sessionDate))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                if let conditioning = workout.conditioning {
                                    Text("Conditioning: \(conditioning)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task {
                                    await deleteWorkout(workout.id)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Workout History")
        .task {
            await loadWorkouts()
        }
    }
    
    private func loadWorkouts() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let workouts = try await neonBridge.listWorkouts(limit: 50)
            await MainActor.run {
                self.workouts = workouts
            }
        } catch {
            print("Failed to load workouts: \(error)")
        }
    }
    
    private func deleteWorkout(_ id: String) async {
        do {
            try await neonBridge.deleteWorkout(id: id)
            await loadWorkouts()
        } catch {
            print("Failed to delete workout: \(error)")
        }
    }
}
