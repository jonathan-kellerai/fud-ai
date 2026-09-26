//
//  JLPhysicalTabView.swift
//  calorietracker
//
//  JL Physical training tab with Program V2 integration
//

import SwiftUI

struct JLPhysicalTabView: View {
    @Environment(StrengthWorkoutStore.self) private var workoutStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedProgram: ProgramV2Template?
    @State private var showingTemplatePicker = false
    @State private var showingWorkoutLog = false
    @State private var selectedDay: ProgramV2Day?
    @State private var currentDate = Date()
    
    private var nextUnfinishedDay: ProgramV2Day? {
        guard let program = selectedProgram else { return nil }
        let calendar = Calendar.current
        let dayOfWeek = calendar.component(.weekday, from: currentDate)
        
        for offset in 0..<7 {
            let checkDate = calendar.date(byAdding: .day, value: offset, to: currentDate) ?? currentDate
            let checkDayOfWeek = calendar.component(.weekday, from: checkDate)
            
            for day in program.days {
                if matchesWeekday(day, checkDayOfWeek) {
                    let hasWorkout = workoutStore.plannedExercises.contains {
                        calendar.isDate($0.date, inSameDayAs: checkDate)
                    }
                    if !hasWorkout || offset == 0 {
                        return day
                    }
                }
            }
        }
        return program.days.first
    }
    
    private func matchesWeekday(_ day: ProgramV2Day, _ weekday: Int) -> Bool {
        let dayName = day.name.lowercased()
        switch weekday {
        case 1: return dayName.contains("sun")
        case 2: return dayName.contains("mon") || dayName.contains("lower")
        case 3: return dayName.contains("tue") || dayName.contains("upper")
        case 4: return dayName.contains("wed") || dayName.contains("pull")
        case 5: return dayName.contains("thu") || dayName.contains("push")
        case 6: return dayName.contains("fri") || dayName.contains("legs")
        case 7: return dayName.contains("sat")
        default: return false
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if selectedProgram == nil {
                        programSelectionPrompt
                    } else if let day = nextUnfinishedDay {
                        todaysWorkoutCard(day: day)
                    }
                    
                    quickActionsCard
                    
                    recentWorkoutsSection
                }
                .padding()
            }
            .navigationTitle("Train")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingTemplatePicker = true
                    } label: {
                        Image(systemName: selectedProgram == nil ? "plus.circle" : "list.bullet")
                    }
                }
            }
            .sheet(isPresented: $showingTemplatePicker) {
                ProgramV2TemplatePickerView { template in
                    selectedProgram = template
                    selectedDay = nextUnfinishedDay
                    showingTemplatePicker = false
                }
            }
            .sheet(isPresented: $showingWorkoutLog) {
                if let day = selectedDay {
                    ProgramV2WorkoutLogView(day: day, program: selectedProgram)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    currentDate = Date()
                }
            }
        }
    }
    
    private var programSelectionPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("Choose Your Program")
                .font(.title2.bold())
            
            Text("Select a Program V2 template to start tracking your workouts")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                showingTemplatePicker = true
            } label: {
                Label("Browse Programs", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
        .padding(.vertical, 40)
    }
    
    private func todaysWorkoutCard(day: ProgramV2Day) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Today's Workout")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text(day.name)
                        .font(.title2.bold())
                }
                
                Spacer()
                
                Button {
                    selectedDay = day
                    showingWorkoutLog = true
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                if let conditioning = day.conditioning {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                        Text("Conditioning: \(conditioning)")
                            .font(.subheadline)
                    }
                }
                
                HStack {
                    Image(systemName: "dumbbell.fill")
                    Text("\(day.movements.count) exercises")
                        .font(.subheadline)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
    }
    
    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
            
            HStack(spacing: 12) {
                NavigationLink(destination: StepsView()) {
                    QuickActionButton(icon: "figure.walk", title: "Steps", color: .green)
                }
                
                NavigationLink(destination: BridgeSettingsView()) {
                    QuickActionButton(icon: "server.rack", title: "Bridge", color: .blue)
                }
                
                if selectedProgram != nil {
                    Button {
                        showingTemplatePicker = true
                    } label: {
                        QuickActionButton(icon: "list.bullet", title: "Program", color: .orange)
                    }
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
                        .foregroundStyle(.blue)
                }
            }
            
            let recentWorkouts = workoutStore.plannedExercises
                .sorted { $0.date > $1.date }
                .prefix(3)
            
            if recentWorkouts.isEmpty {
                Text("No workouts logged yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(Array(recentWorkouts), id: \.id) { workout in
                    RecentWorkoutRow(workout: workout)
                }
            }
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
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

struct RecentWorkoutRow: View {
    let workout: StrengthPlannedExercise
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.exercise.name)
                    .font(.subheadline.bold())
                
                Text(workout.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if let lastSet = workout.sets.last {
                Text("\(lastSet.reps) × \(Int(lastSet.weight))lb")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

struct WorkoutHistoryListView: View {
    @Environment(StrengthWorkoutStore.self) private var workoutStore
    
    var body: some View {
        List {
            ForEach(workoutStore.plannedExercises.sorted { $0.date > $1.date }, id: \.id) { workout in
                NavigationLink(destination: Text("Workout detail")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.exercise.name)
                            .font(.headline)
                        
                        Text(workout.date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Workout History")
    }
}
