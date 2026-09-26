//
//  ProgramV2WorkoutLogView.swift
//  calorietracker
//
//  Workout logging for Program V2 with RIR-first entry and rest timer
//

import SwiftUI

struct ProgramV2WorkoutLogView: View {
    let day: ProgramV2Day
    let program: String?
    
    @Environment(StrengthWorkoutStore.self) private var workoutStore
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
                    if let conditioning = day.conditioning {
                        conditioningCard(conditioning)
                    }
                    
                    ForEach(day.exercises) { exercise in
                        exerciseCard(exercise)
                    }
                    
                    saveButton
                }
                .padding()
            }
            .navigationTitle(day.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingRestTimer) {
                RestTimerSheet(
                    duration: restDuration,
                    onComplete: {
                        showingRestTimer = false
                    }
                )
            }
            .alert("Workout Saved", isPresented: $showingSaveConfirmation) {
                Button("OK") {
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
                Text("Conditioning")
                    .font(.headline)
            }
            
            Text(conditioning)
                .font(.subheadline)
            
            Toggle("Completed", isOn: $conditioningCompleted)
                .toggleStyle(.switch)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func exerciseCard(_ exercise: ProgramV2Exercise) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(exercise.name)
                        .font(.headline)
                    
                    Text("\(exercise.sets) sets × \(exercise.reps) reps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if let starting = exercise.startLoadLb {
                    Text("\(Int(starting))lb")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                }
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
        HStack(spacing: 12) {
            Text("Set \(setIndex + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            
            TextField("Load", value: Binding(
                get: { set.weight },
                set: { workoutSets[exercise.name]?[setIndex].weight = $0 }
            ), format: .number)
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
            .frame(width: 70)
            
            Text("×")
                .foregroundStyle(.secondary)
            
            TextField("Reps", value: Binding(
                get: { set.reps },
                set: { workoutSets[exercise.name]?[setIndex].reps = $0 }
            ), format: .number)
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .frame(width: 60)
            
            TextField("RIR", value: Binding(
                get: { set.rir },
                set: { workoutSets[exercise.name]?[setIndex].rir = $0 }
            ), format: .number)
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .frame(width: 50)
            
            if set.weight > 0 && set.reps > 0 {
                Button {
                    currentExercise = exercise
                    showingRestTimer = true
                } label: {
                    Image(systemName: "timer")
                        .foregroundStyle(.orange)
                }
            }
            
            Button {
                workoutSets[exercise.name]?.remove(at: setIndex)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }
    
    private func addSet(for movement: ProgramV2Movement) {
        let suggestedLoad: Double
        
        if let lastSession = getLastSession(for: movement.name) {
            suggestedLoad = lastSession
        } else if let starting = movement.starting_load {
            suggestedLoad = starting.amount
        } else {
            suggestedLoad = 0
        }
        
        let newSet = WorkoutSet(
            weight: suggestedLoad,
            reps: 0,
            rir: 2
        )
        
        if workoutSets[movement.name] == nil {
            workoutSets[movement.name] = []
        }
        workoutSets[movement.name]?.append(newSet)
    }
    
    private func getLastSession(for exerciseName: String) -> Double? {
        workoutStore.plannedExercises
            .filter { $0.exercise.name == exerciseName }
            .sorted { $0.date > $1.date }
            .first?
            .sets
            .last?
            .weight
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
        
        let allSets = workoutSets.flatMap { exerciseName, sets -> [WorkoutSet] in
            sets.enumerated().map { index, set in
                WorkoutSet(
                    exercise: exerciseName,
                    load: set.weight,
                    reps: set.reps,
                    rir: set.rir,
                    rpe: set.rpe.map(Double.init),
                    order: index
                )
            }
        }
        
        let workout = WorkoutPayload(
            kind: "strength",
            programVersion: "v2",
            programDay: day.id,
            title: day.title,
            units: "lb",
            sessionDate: ISO8601DateFormatter().string(from: Date()),
            conditioning: conditioningCompleted ? day.conditioning : nil,
            notes: [],
            recordedAtUtc: ISO8601DateFormatter().string(from: Date()),
            openedAtUtc: ISO8601DateFormatter().string(from: Date()),
            source: "jl-physical-ios",
            sets: allSets
        )
        
        do {
            _ = try await neonBridge.postWorkout(workout)
            
            for (exerciseName, sets) in workoutSets {
                guard !sets.isEmpty else { continue }
                
                guard let exercise = workoutStore.exerciseLibrary.allExercises
                    .first(where: { $0.name == exerciseName })
                else { continue }
                
                let planned = StrengthPlannedExercise(
                    id: UUID(),
                    date: Date(),
                    exercise: exercise,
                    sets: sets.map { set in
                        StrengthPerformedSet(
                            id: UUID(),
                            weight: set.weight,
                            reps: set.reps,
                            isWarmup: false
                        )
                    },
                    notes: "RIR: \(sets.map { String($0.rir) }.joined(separator: ", "))"
                )
                
                workoutStore.addPlannedExercise(planned)
            }
            
            await MainActor.run {
                isSaving = false
                showingSaveConfirmation = true
            }
        } catch {
            print("Failed to save workout: \(error)")
            await MainActor.run {
                isSaving = false
            }
        }
    }
}

struct LoggedSet {
    var weight: Double
    var reps: Int
    var rir: Int
    var rpe: Int? = nil
}
