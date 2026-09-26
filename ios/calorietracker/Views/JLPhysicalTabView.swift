//
//  JLPhysicalTabView.swift
//  calorietracker
//
//  JL Physical training tab with Program V2 integration
//

import SwiftUI

struct JLPhysicalTabView: View {
    @State private var selectedDay: ProgramV2Day?
    @State private var showingTemplatePicker = false
    @State private var showingWorkoutLog = false
    @State private var recentWorkouts: [RemoteWorkout] = []
    @State private var isLoadingRecent = false
    
    private var neonBridge = NeonBridgeService.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if selectedDay == nil {
                        programSelectionPrompt
                    } else if let day = selectedDay {
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
                        Image(systemName: selectedDay == nil ? "plus.circle" : "list.bullet")
                    }
                }
            }
            .sheet(isPresented: $showingTemplatePicker) {
                ProgramV2TemplatePickerView { day in
                    selectedDay = day
                    showingTemplatePicker = false
                }
            }
            .sheet(isPresented: $showingWorkoutLog) {
                if let day = selectedDay {
                    ProgramV2WorkoutLogView(day: day, onSaved: {
                        Task {
                            await loadRecentWorkouts()
                        }
                    })
                }
            }
            .task {
                await loadRecentWorkouts()
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
            
            Text("Select a Program V2 day template to start tracking your workouts")
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
                    
                    Text(day.title)
                        .font(.title2.bold())
                }
                
                Spacer()
                
                Button {
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
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    Text("Conditioning: \(day.conditioning)")
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
                
                Button {
                    showingTemplatePicker = true
                } label: {
                    QuickActionButton(icon: "list.bullet", title: "Program", color: .orange)
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
    let workout: RemoteWorkout
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.programDay)
                    .font(.subheadline.bold())
                
                Text(workout.sessionDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if let conditioning = workout.conditioning {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.title)
                                .font(.headline)
                            
                            Text(workout.sessionDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            if let conditioning = workout.conditioning {
                                Text("Conditioning: \(conditioning)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
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
            try await neonBridge.deleteWorkout(id)
            await loadWorkouts()
        } catch {
            print("Failed to delete workout: \(error)")
        }
    }
}
