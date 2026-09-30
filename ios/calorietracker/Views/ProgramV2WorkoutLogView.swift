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
    @State private var restDuration = 90
    @State private var lastPerformances: [String: LastPerformance] = [:]
    @State private var isSaving = false
    @State private var showingSaveConfirmation = false
    @State private var saveError: String?
    @State private var showingDiscardConfirmation = false
    @State private var showingReplaceDraftPrompt = false
    /// The session date is the day the logger was opened, even if it is saved after midnight.
    @State private var openedAt = Date()

    /// Logged sets live in the app-level draft store so they survive tab
    /// switches, dismissal and relaunch until the bridge confirms the save.
    private var workoutSets: [String: [LoggedSet]] {
        draftStore.existingDraft(for: day)?.sets ?? [:]
    }

    private var conditioningCompleted: Bool {
        draftStore.existingDraft(for: day)?.conditioningCompleted ?? false
    }

    private var blocks: [ExerciseBlock] {
        SupersetGrouping.blocks(for: day.exercises)
    }

    private func updateDraft(_ change: (inout WorkoutDraft) -> Void) {
        draftStore.update(day, startedAt: openedAt, change)
    }

    private func updateSet(_ exercise: ProgramV2Exercise, at setIndex: Int, _ change: (inout LoggedSet) -> Void) {
        updateDraft { draft in
            guard let sets = draft.sets[exercise.name], sets.indices.contains(setIndex) else { return }
            change(&draft.sets[exercise.name]![setIndex])
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if draftStore.persistError != nil {
                        persistErrorBanner
                    }

                    conditioningCard(day.conditioning)
                        .disabled(isSaving)

                    ForEach(blocks) { block in
                        blockCard(block)
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
                lastPerformances = await ExerciseHistoryLoader.load(exerciseNames: day.exercises.map(\.name))
                refreshPrefilledLoads()
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

    /// Non-blocking: the sets stay in memory and can still be saved to the bridge.
    private var persistErrorBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(IronTheme.bloodText)
            Text("Couldn't save this workout on the phone. Your sets are still here; keep the app open and tap Save Workout.")
                .font(.subheadline)
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                draftStore.dismissPersistError()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(IronTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding()
        .ironCard(rule: true)
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
                set: { newValue in updateDraft { $0.conditioningCompleted = newValue } }
            ))
                .toggleStyle(.switch)
        }
        .padding()
        .ironCard(rule: true)
    }

    @ViewBuilder
    private func blockCard(_ block: ExerciseBlock) -> some View {
        if block.isSuperset {
            supersetCard(block)
        } else if let exercise = block.exercises.first {
            exerciseCard(exercise, in: block)
        }
    }

    private func exerciseCard(_ exercise: ProgramV2Exercise, in block: ExerciseBlock) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            exerciseHeader(exercise, badge: nil)
            setRows(exercise, in: block)
            addSetButton(exercise)
        }
        .padding()
        .ironCard()
    }

    private func supersetCard(_ block: ExerciseBlock) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SUPERSET · \(block.exercises.map(\.name).joined(separator: " + "))")
                    .font(.system(size: 15, weight: .heavy))
                    .fontWidth(.condensed)
                    .tracking(1.0)
                    .foregroundStyle(IronTheme.bloodText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(supersetSubtitle(block))
                    .font(.caption)
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let next = SupersetGrouping.nextUp(in: block, sets: workoutSets) {
                Label(
                    "Next: \(block.memberLabel(for: next.exerciseName) ?? "")\(next.setIndex + 1) \(next.exerciseName)",
                    systemImage: "arrow.right.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(IronTheme.brass)
                .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(block.exercises.enumerated()), id: \.element.id) { index, exercise in
                if index > 0 {
                    Rectangle()
                        .fill(IronTheme.hairline)
                        .frame(height: 1)
                }
                exerciseHeader(exercise, badge: ExerciseBlock.memberLabel(at: index))
                setRows(exercise, in: block)
                addSetButton(exercise)
            }

            Button {
                addRound(to: block)
            } label: {
                Label("Add Round", systemImage: "plus.square.on.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(IronCompactButtonStyle())
        }
        .padding()
        .ironCard(rule: true)
    }

    private func supersetSubtitle(_ block: ExerciseBlock) -> String {
        let labels = block.exercises.indices.map { ExerciseBlock.memberLabel(at: $0) }
        let members: String
        if labels.count == 2 {
            members = "\(labels[0]) and \(labels[1])"
        } else {
            members = labels.dropLast().joined(separator: ", ") + " and " + (labels.last ?? "")
        }
        let rest = SupersetGrouping.supersetRestSeconds(for: block)
        let unit = block.exercises.count == 2 ? "pair" : "round"
        return "Alternate \(members) · rest \(rest) s after each \(unit)"
    }

    private func exerciseHeader(_ exercise: ProgramV2Exercise, badge: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 13, weight: .heavy).monospacedDigit())
                        .foregroundStyle(IronTheme.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(IronTheme.blood, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius))
                }
                Text(exercise.name)
                    .font(.system(size: 17, weight: .heavy))
                    .fontWidth(.condensed)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            HStack(spacing: 16) {
                Text("\(exercise.sets) sets × \(exercise.reps)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(IronTheme.textSecondary)

                if lastPerformance(for: exercise) == nil {
                    loadChip(exercise.startLoadLb.map { "Start: \(LoggerFormatting.load($0))lb" } ?? "Select load")
                }
            }

            if let last = lastPerformance(for: exercise), let lastLine = LoggerFormatting.lastLine(last) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        lastLabel(lastLine)
                        nextChip(for: exercise)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        lastLabel(lastLine)
                        nextChip(for: exercise)
                    }
                }
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
        }
    }

    private func lastLabel(_ text: String) -> some View {
        Label(text, systemImage: "clock.arrow.circlepath")
            .font(.caption.monospacedDigit())
            .foregroundStyle(IronTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func nextChip(for exercise: ProgramV2Exercise) -> some View {
        if let suggestion = suggestedLoad(for: exercise) {
            loadChip("Next: \(LoggerFormatting.load(suggestion)) lb")
        }
    }

    private func loadChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(IronTheme.brass)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(IronTheme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius))
    }

    @ViewBuilder
    private func setRows(_ exercise: ProgramV2Exercise, in block: ExerciseBlock) -> some View {
        let sets = workoutSets[exercise.name] ?? []
        ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
            setRow(exercise: exercise, block: block, setIndex: index, set: set)
        }
    }

    private func addSetButton(_ exercise: ProgramV2Exercise) -> some View {
        Button {
            addSet(for: exercise)
        } label: {
            Label("Add Set", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(IronTheme.bloodText)
        }
    }

    private func setRow(exercise: ProgramV2Exercise, block: ExerciseBlock, setIndex: Int, set: LoggedSet) -> some View {
        let currentIndex = (workoutSets[exercise.name] ?? []).firstIndex { $0.reps == 0 }
        let previous = lastPerformance(for: exercise)?.heaviestLoad
        let isPersonalRecord = set.reps > 0 && previous.map { set.weight > $0 && $0 > 0 } == true
        // Narrow cards (iPhone SE) can't fit every input on one line; fall
        // back to load/reps on the first line and effort/actions on the second.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                setNumber(setIndex, isPersonalRecord: isPersonalRecord)
                loadField(exercise, setIndex: setIndex, set: set)
                rowLabel("lb ×")
                repsField(exercise, setIndex: setIndex, set: set)
                rowLabel("RIR")
                rirField(exercise, in: block, setIndex: setIndex, set: set)
                rpeField(exercise, setIndex: setIndex, set: set)
                logSetButton(exercise, in: block, setIndex: setIndex, set: set)
                removeSetButton(exercise, setIndex: setIndex)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    setNumber(setIndex, isPersonalRecord: isPersonalRecord)
                    loadField(exercise, setIndex: setIndex, set: set)
                    rowLabel("lb ×")
                    repsField(exercise, setIndex: setIndex, set: set)
                    rowLabel("reps")
                }
                HStack(spacing: 8) {
                    rowLabel("RIR")
                    rirField(exercise, in: block, setIndex: setIndex, set: set)
                    rpeField(exercise, setIndex: setIndex, set: set)
                    logSetButton(exercise, in: block, setIndex: setIndex, set: set)
                    removeSetButton(exercise, setIndex: setIndex)
                }
                // Indent under the fields: set-number width plus spacing.
                .padding(.leading, 28)
            }
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

    private func setNumber(_ setIndex: Int, isPersonalRecord: Bool) -> some View {
        HStack(spacing: 8) {
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
                    .fixedSize()
            }
        }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private func loadField(_ exercise: ProgramV2Exercise, setIndex: Int, set: LoggedSet) -> some View {
        // Bodyweight exercises (start load 0) show 0; otherwise an unset load is blank.
        let showsBlankLoad = set.weight == 0 && exercise.startLoadLb != 0
        return TextField("Load", value: Binding<Double?>(
            get: { showsBlankLoad ? nil : set.weight },
            set: { newValue in updateSet(exercise, at: setIndex) { $0.weight = newValue ?? 0 } }
        ), format: .number)
        .keyboardType(.decimalPad)
        .textFieldStyle(.roundedBorder)
        .frame(width: 60)
    }

    private func repsField(_ exercise: ProgramV2Exercise, setIndex: Int, set: LoggedSet) -> some View {
        // Unlogged sets (0 reps) show the placeholder rather than a 0.
        TextField("Reps", value: Binding<Int?>(
            get: { set.reps == 0 ? nil : set.reps },
            set: { newValue in updateSet(exercise, at: setIndex) { $0.reps = newValue ?? 0 } }
        ), format: .number)
        .keyboardType(.numberPad)
        .textFieldStyle(.roundedBorder)
        .frame(width: 50)
    }

    private func rirField(_ exercise: ProgramV2Exercise, in block: ExerciseBlock, setIndex: Int, set: LoggedSet) -> some View {
        TextField("", value: Binding(
            get: { set.rir },
            set: { newValue in updateSet(exercise, at: setIndex) { $0.rir = newValue } }
        ), format: .number)
        .keyboardType(.numberPad)
        .textFieldStyle(.roundedBorder)
        .frame(width: 40)
        .onSubmit {
            logSet(exercise, in: block, setIndex: setIndex)
        }
    }

    private func rpeField(_ exercise: ProgramV2Exercise, setIndex: Int, set: LoggedSet) -> some View {
        TextField("RPE", text: Binding(
            get: { set.rpeText },
            set: { newValue in updateSet(exercise, at: setIndex) { $0.rpeText = newValue } }
        ))
        .keyboardType(.decimalPad)
        .textFieldStyle(.roundedBorder)
        .frame(width: 44)
    }

    private func logSetButton(_ exercise: ProgramV2Exercise, in block: ExerciseBlock, setIndex: Int, set: LoggedSet) -> some View {
        Button {
            logSet(exercise, in: block, setIndex: setIndex)
        } label: {
            Image(systemName: set.reps > 0 ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(set.reps > 0 ? IronTheme.olive : IronTheme.textTertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log set")
    }

    private func removeSetButton(_ exercise: ProgramV2Exercise, setIndex: Int) -> some View {
        Button {
            updateDraft { draft in
                guard draft.sets[exercise.name]?.indices.contains(setIndex) == true else { return }
                draft.sets[exercise.name]?.remove(at: setIndex)
            }
        } label: {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(IronTheme.bloodText)
        }
        .buttonStyle(.plain)
    }

    private func lastPerformance(for exercise: ProgramV2Exercise) -> LastPerformance? {
        lastPerformances[LastPerformanceBuilder.key(for: exercise.name)]
    }

    private func suggestedLoad(for exercise: ProgramV2Exercise) -> Double? {
        ProgressionRule.suggestedLoad(
            last: lastPerformance(for: exercise),
            reps: exercise.reps,
            startLoadLb: exercise.startLoadLb
        )
    }

    /// Sets added before history loaded were prefilled without it; move the
    /// untouched ones to the suggestion. Never creates a draft.
    private func refreshPrefilledLoads() {
        guard !Task.isCancelled, draftStore.existingDraft(for: day) != nil else { return }
        var suggestions: [String: Double] = [:]
        for exercise in day.exercises where suggestions[exercise.name] == nil {
            if let suggestion = suggestedLoad(for: exercise) {
                suggestions[exercise.name] = suggestion
            }
        }
        let refreshed = PrefillRefresh.refreshedSets(
            exercises: day.exercises,
            sets: workoutSets,
            suggestions: suggestions
        )
        guard !refreshed.isEmpty else { return }
        updateDraft { draft in
            for (name, sets) in refreshed {
                draft.sets[name] = sets
            }
        }
    }

    /// Starts the rest timer when the rest policy asks for one. In a superset
    /// that is once per round, after the last member's set.
    private func logSet(_ exercise: ProgramV2Exercise, in block: ExerciseBlock, setIndex: Int) {
        let sets = workoutSets
        guard let exerciseSets = sets[exercise.name],
              exerciseSets.indices.contains(setIndex),
              exerciseSets[setIndex].reps > 0 else { return }
        guard let seconds = SupersetGrouping.restSeconds(
            afterLogging: exercise.name,
            setIndex: setIndex,
            in: block,
            sets: sets
        ) else { return }
        restDuration = seconds
        showingRestTimer = true
    }

    private func addRound(to block: ExerciseBlock) {
        for exercise in block.exercises {
            addSet(for: exercise)
        }
    }

    /// Prefills the load from the previous set this session, else the suggestion.
    private func addSet(for exercise: ProgramV2Exercise) {
        let load = workoutSets[exercise.name]?.last?.weight ?? suggestedLoad(for: exercise) ?? 0

        let newSet = LoggedSet(
            weight: load,
            reps: 0,
            rir: Int(exercise.rirTarget) ?? 0,
            rpeText: ""
        )

        updateDraft { draft in
            if draft.sets[exercise.name] == nil {
                draft.sets[exercise.name] = []
            }
            draft.sets[exercise.name]?.append(newSet)
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
