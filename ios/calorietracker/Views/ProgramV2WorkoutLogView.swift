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
    
    init(day: ProgramV2Day, onSaved: @escaping () -> Void = {}) {
        self.day = day
        self.onSaved = onSaved
    }
    
    @Environment(\.dismiss) private var dismiss
    @State private var workoutSets: [String: [LoggedSet]] = [:]
    @State private var conditioningCompleted = false
    @State private var showingRestTimer = false
    @State private var restDuration = 90
    @State private var suggestedLoads: [String: Double] = [:]
    @State private var isSaving = false
    @State private var showingSaveConfirmation = false
    @State private var saveError: String?
    
    private var neonBridge = NeonBridgeService.shared
    
    var body: some View {
        NavigationStack {
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
            .background(IronTheme.canvas)
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
                RestTimerSheet(defaultSeconds: restDuration)
            }
            .task {
                await loadLastSessionLoads()
            }
            .alert("Workout Saved", isPresented: $showingSaveConfirmation) {
                Button("OK") {
                    onSaved()
                    dismiss()
                }
            } message: {
                Text("Your workout has been logged and synced.")
            }
            .alert("Could Not Save", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }
    
    private func conditioningCard(_ conditioning: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(IronTheme.bloodText)
                Text("Conditioning · Do first")
                    .font(.system(size: 15, weight: .heavy))
                    .fontWidth(.condensed)
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(IronTheme.textPrimary)
            }
            
            Text(conditioning)
                .font(.subheadline)

            if !day.conditioningMinimum.isEmpty {
                Text("Minimum: \(day.conditioningMinimum)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Toggle("Completed", isOn: $conditioningCompleted)
                .toggleStyle(.switch)
        }
        .padding()
        .ironCard(rule: true)
    }
    
    private func exerciseCard(_ exercise: ProgramV2Exercise) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(exercise.name)
                        .font(.system(size: 17, weight: .heavy))
                        .fontWidth(.condensed)
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(IronTheme.textPrimary)
                    
                    HStack(spacing: 16) {
                        Text("\(exercise.sets) sets × \(exercise.reps)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(IronTheme.textSecondary)
                        
                        if let starting = exercise.startLoadLb {
                            Text("Start: \(Int(starting))lb")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(IronTheme.brass)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(IronTheme.surfaceRaised)
                                .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius))
                        }
                    }
                }
                
                Spacer()
            }

            if !exercise.loadNote.isEmpty {
                Text(exercise.loadNote)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !exercise.notes.isEmpty {
                Text(exercise.notes)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if !exercise.rirTarget.isEmpty {
                Text("RIR Target: \(exercise.rirTarget)")
                    .font(.subheadline.weight(.semibold))
            }
            
            let sets = workoutSets[exercise.name] ?? []
            
            ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
                setRow(exercise: exercise, setIndex: index, set: set)
            }
            
            Button {
                addSet(for: exercise)
            } label: {
                Label("Add Set", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IronTheme.bloodText)
            }
        }
        .padding()
        .ironCard()
    }
    
    private func setRow(exercise: ProgramV2Exercise, setIndex: Int, set: LoggedSet) -> some View {
        let currentIndex = (workoutSets[exercise.name] ?? []).firstIndex { $0.reps == 0 }
        let previous = previousSessionLoad(for: exercise)
        let isPersonalRecord = set.reps > 0 && previous.map { set.weight > $0 && $0 > 0 } == true
        return HStack(spacing: 8) {
            Text("\(setIndex + 1)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(IronTheme.textSecondary)
                .frame(width: 20)
            if isPersonalRecord {
                Text("PR")
                    .font(.system(size: 11, weight: .heavy))
                    .fontWidth(.condensed)
                    .tracking(0.6)
                    .foregroundStyle(IronTheme.brass)
            }
            
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
            .onSubmit {
                logSet(exercise, setIndex: setIndex)
            }

            TextField("RPE", text: Binding(
                get: { set.rpeText },
                set: { workoutSets[exercise.name]?[setIndex].rpeText = $0 }
            ))
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
            .frame(width: 44)

            Button {
                logSet(exercise, setIndex: setIndex)
            } label: {
                Image(systemName: set.reps > 0 ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(set.reps > 0 ? IronTheme.olive : IronTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log set")
            
            Button {
                workoutSets[exercise.name]?.remove(at: setIndex)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(IronTheme.bloodText)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            if currentIndex == setIndex {
                Rectangle()
                    .fill(IronTheme.blood)
                    .frame(width: IronTheme.ruleWidth)
            }
        }
    }

    private func previousSessionLoad(for exercise: ProgramV2Exercise) -> Double? {
        let key = exercise.name.lowercased()
        return suggestedLoads.first { $0.key.lowercased() == key }?.value
    }
    
    private func logSet(_ exercise: ProgramV2Exercise, setIndex: Int) {
        guard let set = workoutSets[exercise.name]?[setIndex], set.reps > 0 else { return }
        restDuration = exercise.restSeconds.lowerBound
        showingRestTimer = true
    }

    private func addSet(for exercise: ProgramV2Exercise) {
        let suggestedLoad = suggestedLoad(for: exercise)
        
        let newSet = LoggedSet(
            weight: suggestedLoad,
            reps: 0,
            rir: Int(exercise.rirTarget) ?? 0,
            rpeText: ""
        )
        
        if workoutSets[exercise.name] == nil {
            workoutSets[exercise.name] = []
        }
        workoutSets[exercise.name]?.append(newSet)
    }

    private func suggestedLoad(for exercise: ProgramV2Exercise) -> Double {
        let key = exercise.name.lowercased()
        if let match = suggestedLoads.first(where: { $0.key.lowercased() == key }) {
            return match.value
        }
        return exercise.startLoadLb ?? 0
    }

    private func loadLastSessionLoads() async {
        do {
            let workouts = try await neonBridge.listWorkouts(limit: 50)
            guard let previous = workouts.first(where: { $0.programDay == day.id }) else { return }
            let detail = try await neonBridge.getWorkout(id: previous.id)
            var loads: [String: Double] = [:]
            for set in detail.sets.sorted(by: { $0.setOrder < $1.setOrder }) {
                loads[set.exercise] = set.loadLb
            }
            await MainActor.run {
                suggestedLoads = loads
            }
        } catch {
            suggestedLoads = [:]
        }
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
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(IronPrimaryButtonStyle(enabled: canSave && !isSaving))
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
                    let rpe = Double(set.rpeText.replacingOccurrences(of: ",", with: "."))
                    allSets.append(WorkoutSet(
                        exercise: exercise.name,
                        load: set.weight,
                        reps: set.reps,
                        rir: set.rir,
                        rpe: rpe,
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
            kind: "COMPLETED",
            programVersion: "program-v2",
            programDay: day.id,
            title: day.title,
            units: "lb",
            sessionDate: sessionDate,
            conditioning: conditioningCompleted ? day.conditioning : nil,
            notes: [],
            recordedAtUtc: timestamp,
            openedAtUtc: timestamp,
            source: "jl-fud-native",
            sets: allSets
        )
        
        do {
            _ = try await neonBridge.postWorkout(workout)
            
            await MainActor.run {
                showingSaveConfirmation = true
            }
        } catch {
            await MainActor.run {
                saveError = error.localizedDescription
            }
        }
    }
}

struct LoggedSet {
    var weight: Double
    var reps: Int
    var rir: Int
    var rpeText: String
}
