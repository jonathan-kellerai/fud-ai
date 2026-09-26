//
//  ProgramV2WorkoutLogView.swift
//  calorietracker
//
//  Workout logging for Program V2 with RIR-first entry and rest timer
//

import SwiftUI

struct ProgramV2WorkoutLogView: View {
    let day: ProgramV2Day
    let onSaved: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var workoutSets: [String: [LoggedSet]] = [:]
    @State private var conditioningCompleted = false
    @State private var showingRestTimer = false
    @State private var restDuration = 90
    @State private var currentExercise: ProgramV2Exercise?
    @State private var isSaving = false
    @State private var showingSaveConfirmation = false
    
    private var neonBridge = NeonBridgeService.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    conditioningCard(day.conditioning)
                    
                    ForEach(day.exercises) { exercise in
                        exerciseCard(exercise)
                    }
                    
                    saveButton
                }
                .padding()
            }
            .navigationTitle(day.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingRestTimer) {
                if let exercise = currentExercise {
                    RestTimerSheet(defaultSeconds: exercise.restSeconds.lowerBound)
                }
            }
            .alert("Workout Saved", isPresented: $showingSaveConfirmation) {
                Button("OK") {
                    onSaved()
                    dismiss()
                }
            } message: {
                Text("Your workout has been logged and synced.")
            }
        }
    }
    
    private func conditioningCard(_ conditioning: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("Conditioning (Do First!)")
                    .font(.headline)
            }
            
            Text(conditioning)
                .font(.subheadline)
            
            Text("Minimum: \(day.conditioningMinimum)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Toggle("Completed", isOn: $conditioningCompleted)
                .toggleStyle(.switch)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func exerciseCard(_ exercise: ProgramV2Exercise) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(exercise.name)
                        .font(.headline)
                    
                    HStack(spacing: 16) {
                        Text("\(exercise.sets) sets × \(exercise.reps)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if let starting = exercise.startLoadLb {
                            Text("Start: \(Int(starting))lb")
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
                
                Spacer()
            }
            
            if !exercise.rirTarget.isEmpty {
                Text("RIR Target: \(exercise.rirTarget)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            let sets = workoutSets[exercise.name] ?? []
            
            ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
                setRow(exercise: exercise, setIndex: index, set: set)
            }
            
            Button {
                addSet(for: exercise)
            } label: {
                Label("Add Set", systemImage: "plus.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
    }
    
    private func setRow(exercise: ProgramV2Exercise, setIndex: Int, set: LoggedSet) -> some View {
        HStack(spacing: 8) {
            Text("\(setIndex + 1)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            TextField("Load", value: Binding(
                get: { set.weight },
                set: { workoutSets[exercise.name]?[setIndex].weight = $0 }
            ), format: .number)
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
            .frame(width: 60)
            
            Text("lb ×")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            TextField("Reps", value: Binding(
                get: { set.reps },
                set: { workoutSets[exercise.name]?[setIndex].reps = $0 }
            ), format: .number)
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .frame(width: 50)
            
            Text("RIR")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            TextField("", value: Binding(
                get: { set.rir },
                set: { workoutSets[exercise.name]?[setIndex].rir = $0 }
            ), format: .number)
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .frame(width: 40)
            
            if set.weight > 0 && set.reps > 0 {
                Button {
                    currentExercise = exercise
                    showingRestTimer = true
                } label: {
                    Image(systemName: "timer")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
            
            Button {
                workoutSets[exercise.name]?.remove(at: setIndex)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    private func addSet(for exercise: ProgramV2Exercise) {
        let suggestedLoad = exercise.startLoadLb ?? 0
        
        let newSet = LoggedSet(
            weight: suggestedLoad,
            reps: 0,
            rir: 2
        )
        
        if workoutSets[exercise.name] == nil {
            workoutSets[exercise.name] = []
        }
        workoutSets[exercise.name]?.append(newSet)
    }
    
    private var saveButton: some View {
        Button {
            Task {
                await saveWorkout()
            }
        } label: {
            if isSaving {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Text("Save Workout")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canSave ? Color.accentColor : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .disabled(!canSave || isSaving)
    }
    
    private var canSave: Bool {
        conditioningCompleted || !workoutSets.isEmpty
    }
    
    private func saveWorkout() async {
        isSaving = true
        defer {
            Task { @MainActor in
                isSaving = false
            }
        }
        
        var allSets: [WorkoutSet] = []
        var order = 0
        
        for exercise in day.exercises {
            if let sets = workoutSets[exercise.name] {
                for set in sets {
                    allSets.append(WorkoutSet(
                        exercise: exercise.name,
                        load: set.weight,
                        reps: set.reps,
                        rir: set.rir,
                        rpe: nil,
                        order: order
                    ))
                    order += 1
                }
            }
        }
        
        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let sessionDate = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: now)
        
        let workout = WorkoutPayload(
            kind: "strength",
            programVersion: "v2",
            programDay: day.id,
            title: day.title,
            units: "lb",
            sessionDate: sessionDate,
            conditioning: conditioningCompleted ? day.conditioning : nil,
            notes: [],
            recordedAtUtc: timestamp,
            openedAtUtc: timestamp,
            source: "jl-physical-ios",
            sets: allSets
        )
        
        do {
            _ = try await neonBridge.postWorkout(workout)
            
            await MainActor.run {
                showingSaveConfirmation = true
            }
        } catch {
            print("Failed to save workout: \(error)")
        }
    }
}

struct LoggedSet {
    var weight: Double
    var reps: Int
    var rir: Int
}
