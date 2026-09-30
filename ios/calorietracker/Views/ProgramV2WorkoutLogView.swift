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
    @Environment(WorkoutDraftStore.self) private var draftStore
    @State private var showingRestTimer = false
    @State private var restDuration = RestTimerSettings.defaultSeconds
    @State private var suggestedLoads: [String: Double] = [:]
    @State private var isSaving = false
    @State private var showingSaveConfirmation = false
    @State private var saveError: String?
    @State private var plausibilityMessage: String?
    
    @State private var showingDiscardConfirmation = false
    @State private var showingReplaceDraftPrompt = false

    private var neonBridge = NeonBridgeService.shared

    /// Logged sets live in the app-level draft store so they survive tab
    /// switches, dismissal and relaunch until the bridge confirms the save.
    private var workoutSets: [String: [LoggedSet]] {
        draftStore.existingDraft(for: day)?.sets ?? [:]
    }

    private var conditioningCompleted: Bool {
        draftStore.existingDraft(for: day)?.conditioningCompleted ?? false
    }

    private func updateSet(_ exercise: ProgramV2Exercise, at setIndex: Int, _ change: (inout LoggedSet) -> Void) {
        draftStore.update(day) { draft in
            guard let sets = draft.sets[exercise.name], sets.indices.contains(setIndex) else { return }
            change(&draft.sets[exercise.name]![setIndex])
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    conditioningCard(day.conditioning)
                        .disabled(isSaving)

                    ForEach(day.exercises) { exercise in
                        exerciseCard(exercise)
                            .disabled(isSaving)
                    }
                    
                    saveButton

                    if draftStore.existingDraft(for: day) != nil {
                        discardButton
                    }
                }
                .padding()
            }
            .background(IronTheme.canvas)
            .navigationTitle(day.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // Logged sets stay in the draft; closing never loses them.
                    Button("Close") {
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
            .onAppear {
                if draftStore.hasDraft(otherThan: day) {
                    showingReplaceDraftPrompt = true
                }
            }
            .alert("Unsaved Workout", isPresented: $showingReplaceDraftPrompt) {
                Button("Discard and Start", role: .destructive) {
                    draftStore.discard()
                }
                Button("Keep It", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("You have an unsaved \(draftStore.draft?.title ?? "workout") session. Starting \(day.title) discards it. Resume it from Today or Train instead.")
            }
            .confirmationDialog("Discard this workout?", isPresented: $showingDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard Workout", role: .destructive) {
                    draftStore.discard()
                    dismiss()
                }
            } message: {
                Text("Every set logged in this session will be deleted.")
            }
            .alert("Workout Saved", isPresented: $showingSaveConfirmation) {
                Button("OK") {
                    onSaved()
                    dismiss()
                }
            } message: {
                Text("Your workout has been logged and synced.")
            }
            .plausibilityConfirmation(
                title: "Double-check before saving",
                message: plausibilityMessage,
                onSave: {
                    plausibilityMessage = nil
                    Task {
                        await JevRouter.shared.report(.plausibility, .userOverride, preview: "workout")
                        await saveWorkout()
                    }
                },
                onEdit: { plausibilityMessage = nil }
            )
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
            
            Toggle("Completed", isOn: Binding(
                get: { conditioningCompleted },
                set: { newValue in draftStore.update(day) { $0.conditioningCompleted = newValue } }
            ))
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
                set: { newValue in updateSet(exercise, at: setIndex) { $0.weight = newValue } }
            ), format: .number)
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
            .frame(width: 60)
            
            Text("lb ×")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            TextField("Reps", value: Binding(
                get: { set.reps },
                set: { newValue in updateSet(exercise, at: setIndex) { $0.reps = newValue } }
            ), format: .number)
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .frame(width: 50)
            
            Text("RIR")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            TextField("", value: Binding(
                get: { set.rir },
                set: { newValue in updateSet(exercise, at: setIndex) { $0.rir = newValue } }
            ), format: .number)
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .frame(width: 40)
            .onSubmit {
                logSet(exercise, setIndex: setIndex)
            }

            TextField("RPE", text: Binding(
                get: { set.rpeText },
                set: { newValue in updateSet(exercise, at: setIndex) { $0.rpeText = newValue } }
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
                draftStore.update(day) { draft in
                    guard draft.sets[exercise.name]?.indices.contains(setIndex) == true else { return }
                    draft.sets[exercise.name]?.remove(at: setIndex)
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(IronTheme.bloodText)
            }
            .buttonStyle(.plain)
        }
        // Fixed-width numeric inputs: keep labels on one line and stop the
        // row growing past the card at accessibility sizes.
        .lineLimit(1)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
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
        
        draftStore.update(day) { draft in
            if draft.sets[exercise.name] == nil {
                draft.sets[exercise.name] = []
            }
            draft.sets[exercise.name]?.append(newSet)
        }
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
            Task { await reviewThenSave() }
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
    
    private var discardButton: some View {
        Button(role: .destructive) {
            showingDiscardConfirmation = true
        } label: {
            Text("Discard Workout")
                .font(.system(size: 15, weight: .heavy))
                .fontWidth(.condensed)
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.bloodText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .disabled(isSaving)
    }

    private var canSave: Bool {
        conditioningCompleted || !workoutSets.isEmpty
    }
    
    private func reviewThenSave() async {
        var flags: [PlausibilityFlag] = []
        for exercise in day.exercises {
            let sets = workoutSets[exercise.name] ?? []
            let loads = sets.map(\.weight)
            let previousLb = previousSessionLoad(for: exercise)
            for (index, set) in sets.enumerated() {
                let others = loads.enumerated().filter { $0.offset != index }.map(\.element)
                flags.append(contentsOf: PlausibilityRules.sets(
                    name: exercise.name,
                    loadKg: set.weight / 2.2046226218,
                    reps: set.reps,
                    referenceLoadsKg: previousLb.map { [$0 / 2.2046226218] } ?? [],
                    referenceReps: [],
                    sessionLoadsKg: others.map { $0 / 2.2046226218 }
                ))
            }
        }
        let visible = await PlausibilityReview.visible(flags)
        if visible.isEmpty {
            await saveWorkout()
        } else {
            plausibilityMessage = visible.prefix(3).map(\.message).joined(separator: "\n")
        }
    }

    private func saveWorkout() async {
        isSaving = true
        defer {
            Task { @MainActor in
                isSaving = false
            }
        }

        // The store builds the payload from the draft, posts it, and clears the
        // draft only after the bridge accepts it. On failure the draft stays.
        do {
            try await draftStore.save()

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

struct LoggedSet: Codable, Equatable {
    var weight: Double
    var reps: Int
    var rir: Int
    var rpeText: String
}

/// Today/Train entry point for an unsaved logger session.
struct ResumeWorkoutCard: View {
    let draft: WorkoutDraft
    let onResume: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resume workout")
                .font(.system(size: 15, weight: .heavy))
                .fontWidth(.condensed)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.bloodText)
            Text(draft.title)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(draft.loggedSetCount) sets logged · \(SessionDateFormatting.displayString(from: draft.sessionDate)) · not saved")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onResume) {
                Label("Resume", systemImage: "play.fill")
            }
            .buttonStyle(IronCompactButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
