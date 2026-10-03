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
        _entry = State(initialValue: WorkoutSetEntry(day: day))
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(WorkoutDraftStore.self) private var draftStore
    @State private var showingRestTimer = false
    @State private var restDuration = RestTimerSettings.defaultSeconds
    @State private var entry: WorkoutSetEntry
    @State private var isSaving = false
    @State private var showingSaveConfirmation = false
    @State private var saveError: String?
    @State private var plausibilityMessage: String?
    
    @State private var showingDiscardConfirmation = false
    @State private var showingReplaceDraftPrompt = false
    /// The session date is the day the logger was opened, even if it is saved after midnight.
    @State private var openedAt = Date()
    /// CC ladder state for graduate-at hints on ladder finishers. Starts from
    /// the Ladders screen's memory cache and refreshes once per open.
    @State private var ccLadders: CCLaddersResponse? = CCLadderMemoryCache.last

    /// Logged sets live in the app-level draft store so they survive tab
    /// switches, dismissal and relaunch until the bridge confirms the save.
    private var workoutSets: [String: [LoggedSet]] {
        draftStore.existingDraft(for: day)?.sets ?? [:]
    }

    private var conditioningCompleted: Bool {
        draftStore.existingDraft(for: day)?.conditioningCompleted ?? false
    }

    private var blocks: [ExerciseBlock] {
        sessionOrder.blocks
    }

    private var sessionOrder: SessionOrder {
        entry.order(in: draftStore)
    }

    private func updateDraft(_ change: (inout WorkoutDraft) -> Void) {
        draftStore.update(day, startedAt: openedAt, change)
    }

    private func updateSet(_ exercise: ProgramV2Exercise, at setIndex: Int, _ change: (inout LoggedSet) -> Void) {
        entry.update(exercise, at: setIndex, in: draftStore, startedAt: openedAt, change)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let weekNote = day.weekNote {
                        Text(weekNote)
                            .font(.subheadline)
                            .foregroundStyle(IronTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
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
            .scrollDismissesKeyboard(.interactively)
            .background(IronTheme.canvas)
            .safeAreaInset(edge: .bottom) {
                if let deletion = entry.deletion {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if deletion.canRestore(at: context.date) {
                            HStack {
                                Text("Set \(deletion.index + 1) deleted")
                                Spacer()
                                Button("Undo") { entry.undo(in: draftStore, startedAt: openedAt) }
                                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                                    .foregroundStyle(IronTheme.brass)
                            }.padding(.horizontal).background(IronTheme.surfaceRaised)
                        }
                    }
                }
            }
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
                entry.lastPerformances = await ExerciseHistoryLoader.load(exerciseNames: day.exercises.map(\.name), programDay: day.id)
                refreshPrefilledLoads()
                await loadLaddersIfNeeded()
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
                Button("Keep It (Resume from Train)", role: .cancel) {
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

            if let hint = ladderHint(for: exercise) {
                Label(hint.text, systemImage: hint.isHold ? "timer" : "flag.checkered")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(IronTheme.brass)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 16) {
                Text("\(exercise.setsLabel ?? String(exercise.sets)) sets × \(exercise.reps)")
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
        ForEach(0..<SetEntryLogic.plannedRowCount(exercise: exercise, sets: sets), id: \.self) { index in
            setRow(exercise: exercise, block: block, setIndex: index,
                   set: entry.row(for: exercise, at: index, in: draftStore))
        }
    }

    private func addSetButton(_ exercise: ProgramV2Exercise) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let source = entry.repeatSource(for: exercise, in: draftStore) {
                Button {
                    if let index = entry.repeatLast(exercise, in: draftStore, startedAt: openedAt),
                       let block = blocks.first(where: { $0.exercises.contains { $0.name == exercise.name } }) {
                        logSet(exercise, in: block, setIndex: index)
                    }
                } label: { Label("Repeat set \(source + 1)", systemImage: "arrow.clockwise") }
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                .buttonStyle(.plain).foregroundStyle(IronTheme.textPrimary)
            }
            Button { addSet(for: exercise) } label: {
                Label("Add Set", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(IronTheme.bloodText)
            }.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
    }

    private func setRow(exercise: ProgramV2Exercise, block: ExerciseBlock, setIndex: Int, set: LoggedSet) -> some View {
        LoggerSetRow(
            setIndex: setIndex, set: set, startLoadLb: exercise.startLoadLb,
            isHold: ladderHint(for: exercise)?.isHold == true,
            kind: SetEntryLogic.rowKind(at: setIndex, sets: workoutSets[exercise.name] ?? [],
                editing: entry.editingStep == ExerciseStep(exerciseName: exercise.name, setIndex: setIndex)),
            isPersonalRecord: SetEntryLogic.isPersonalRecord(set: set, previous: lastPerformance(for: exercise)),
            targetText: exercise.reps,
            targetChips: SetEntryLogic.targetChips(for: exercise, at: setIndex),
            loadStep: SetEntryLogic.loadStep(set.weight),
            onEdit: { entry.editingStep = ExerciseStep(exerciseName: exercise.name, setIndex: setIndex) },
            onChange: { edit in entry.edit(exercise, at: setIndex, in: draftStore, startedAt: openedAt, edit) },
            onStep: { load, direction in
                entry.edit(exercise, at: setIndex, in: draftStore, startedAt: openedAt) {
                    $0 = SetEntryLogic.stepped($0, load: load, direction: direction, isHold: ladderHint(for: exercise)?.isHold == true)
                }
            },
            onLog: {
                if let index = entry.log(exercise, at: setIndex, in: draftStore, startedAt: openedAt) {
                    logSet(exercise, in: block, setIndex: index)
                }
            },
            onRemove: {
                entry.remove(exercise, at: setIndex, in: draftStore, startedAt: openedAt)
            }
        )
    }

    private func ladderHint(for exercise: ProgramV2Exercise) -> CCLoggerLadderHint? {
        guard CCLadderLogic.isLadderExerciseName(exercise.name) else { return nil }
        return CCLadderLogic.loggerHint(exerciseKey: exercise.key, exerciseName: exercise.name, in: ccLadders)
    }

    /// Best effort: without the bridge the logger simply shows no ladder hint.
    private func loadLaddersIfNeeded() async {
        guard day.exercises.contains(where: { CCLadderLogic.isLadderExerciseName($0.name) }) else { return }
        guard let fresh = try? await CCLadderClient.fetchLadders(settings: NeonBridgeService.shared.settings),
              !Task.isCancelled
        else { return }
        ccLadders = fresh
        CCLadderMemoryCache.last = fresh
    }

    private func lastPerformance(for exercise: ProgramV2Exercise) -> LastPerformance? {
        entry.lastPerformance(for: exercise)
    }

    private func suggestedLoad(for exercise: ProgramV2Exercise) -> Double? {
        entry.suggestedLoad(for: exercise, in: draftStore)
    }

    /// Sets added before history loaded were prefilled without it; move the
    /// untouched ones to the suggestion. Never creates a draft.
    private func refreshPrefilledLoads() {
        entry.refreshPrefilledLoads(in: draftStore, startedAt: openedAt)
    }

    /// Starts the rest timer when the rest policy asks for one. In a superset
    /// that is once per round, after the last member's set.
    private func logSet(_ exercise: ProgramV2Exercise, in block: ExerciseBlock, setIndex: Int) {
        let sets = workoutSets
        guard let seconds = SetEntryLogic.restAfterLogging(
            exerciseName: exercise.name,
            setIndex: setIndex,
            block: block,
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

    /// Uses the last logged set, never an unfinished row. Prefilled reps stay
    /// outside the draft so only entered reps count as logged.
    private func addSet(for exercise: ProgramV2Exercise) {
        entry.add(exercise, in: draftStore, startedAt: openedAt)
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
            let previousLb = lastPerformance(for: exercise)?.heaviestLoad
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
