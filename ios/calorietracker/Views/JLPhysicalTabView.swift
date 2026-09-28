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
    
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var neonBridge = NeonBridgeService.shared
    /// Nil means "now". Visual QA snapshot tests pin a lifting day and a rest day.
    private let referenceDate: Date?

    init(referenceDate: Date? = nil) {
        self.referenceDate = referenceDate
    }

    private var todayPlan: ResolvedTrainingDay {
        TrainingProgramSchedule.resolve(programBody, on: referenceDate ?? Date())
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    todaysWorkoutCard
                    quickActionsCard
                    recentWorkoutsSection
                }
                .padding()
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
            .sheet(item: $loggingDay) { day in
                ProgramV2WorkoutLogView(day: day, onSaved: {
                    Task { await loadRecentWorkouts() }
                })
            }
            .task {
                await loadActiveProgram()
                await loadRecentWorkouts()
            }
        }
    }

    private var todaysWorkoutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch todayPlan {
            case .session(let dayIndex, let name, _):
                sessionCard(dayIndex: dayIndex, name: name)
            case .rest(let stepsTarget, _, _):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rest Day")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(stepsTarget.formatted()) steps")
                        .font(.title2.bold())
                    if let nextLabel = todayPlan.nextLabel {
                        Text(nextLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            case .upcoming(let name, let weekday, let stepsTarget):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Upcoming")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.title2.bold())
                    Text(weekday)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(stepsTarget.formatted()) steps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let bridgeNotice {
                Text(bridgeNotice)
                    .font(.caption)
                    .foregroundStyle(AppColors.calorie)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func sessionCard(dayIndex: Int, name: String) -> some View {
        let day = programBody.days.first { $0.dayIndex == dayIndex && $0.name == name }
            ?? programBody.days.first { $0.dayIndex == dayIndex }
        let title = VStack(alignment: .leading) {
            Text("Today's Workout")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(name)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
        }
        // At accessibility sizes the Start button no longer fits beside the
        // session name on small phones, so stack it full-width underneath
        // instead of squeezing "Start" into a one-letter-wide column.
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                title
                if let day {
                    startButton(day, fullWidth: true)
                }
            }
        } else {
            HStack {
                title
                Spacer(minLength: 12)
                if let day {
                    startButton(day, fullWidth: false)
                }
            }
        }
        if let day {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(AppColors.calorie)
                    Text("Conditioning: \(day.conditioningSummary)")
                        .font(.subheadline)
                }
                HStack {
                    Image(systemName: "dumbbell.fill")
                    Text("\(day.exercises.count) exercises")
                        .font(.subheadline)
                }
            }
            .foregroundStyle(.secondary)
        }
    }
    
    private func startButton(_ day: TrainingProgramDay, fullWidth: Bool) -> some View {
        Button {
            loggingDay = day.asProgramV2Day()
        } label: {
            Label("Start", systemImage: "play.fill")
                .font(.headline)
                .lineLimit(1)
                .fixedSize(horizontal: !fullWidth, vertical: false)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(AppColors.calorie)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
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
            let workouts = try await neonBridge.listWorkouts(limit: 5)
            await MainActor.run {
                recentWorkouts = workouts
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
