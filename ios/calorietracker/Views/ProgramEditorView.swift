//
//  ProgramEditorView.swift
//  calorietracker
//
//  Native program list and draft editor for the versioned bridge API.
//

import SwiftUI

enum ProgramEditorRoute: Identifiable, Hashable {
    case blank
    case copy(String)
    case draft(String)
    case revise(String)
    case remoteReadOnly(String)
    case bundled

    var id: String {
        switch self {
        case .blank: "blank"
        case .copy(let programID): "copy-\(programID)"
        case .draft(let programID): "draft-\(programID)"
        case .revise(let programID): "revise-\(programID)"
        case .remoteReadOnly(let programID): "read-\(programID)"
        case .bundled: "bundled"
        }
    }
}

struct ProgramLibraryView: View {
    @State private var programs: [TrainingProgramRecord] = []
    @State private var canEdit = false
    @State private var bridgeNotice: String?
    @State private var route: ProgramEditorRoute?
    @State private var showingDuplicatePicker = false
    @State private var errorMessage: String?
    @State private var isLoading = false

    private let bridge = NeonBridgeService.shared

    var body: some View {
        List {
            if let bridgeNotice {
                Section {
                    Label(bridgeNotice, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.calorie)
                    Text("Program V2 is read-only until the bridge is reachable.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(AppColors.appCard)
            }

            if canEdit {
                if let active = programs.first(where: { $0.status == .active }) {
                    Section("Active") {
                        programButton(active, route: .revise(active.id), badge: "Active")
                    }
                    .listRowBackground(AppColors.appCard)
                }

                Section("Drafts") {
                    if drafts.isEmpty {
                        Text("No drafts")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(drafts) { program in
                            programButton(program, route: .draft(program.id), badge: nil)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        Task { await deleteDraft(program.id) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .listRowBackground(AppColors.appCard)

                if !lineageGroups.isEmpty {
                    Section("Archived") {
                        ForEach(lineageGroups) { group in
                            DisclosureGroup {
                                ForEach(group.versions) { program in
                                    programButton(program, route: .remoteReadOnly(program.id), badge: "v\(program.version)")
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name)
                                    Text("\(group.versions.count) archived")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listRowBackground(AppColors.appCard)
                }
            } else if !isLoading {
                Section("Program V2") {
                    programButton(TrainingProgramRecord.bundledV2(), route: .bundled, badge: "Bundled")
                }
                .listRowBackground(AppColors.appCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .tint(AppColors.calorie)
        .navigationTitle("Programs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Blank Program", systemImage: "plus") {
                            route = .blank
                        }
                        Button("Duplicate Existing", systemImage: "doc.on.doc") {
                            showingDuplicatePicker = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Program")
                }
            }
        }
        .navigationDestination(item: $route) { route in
            ProgramEditorView(route: route) {
                Task { await reload() }
            }
        }
        .sheet(isPresented: $showingDuplicatePicker) {
            NavigationStack {
                List(programs) { program in
                    Button {
                        showingDuplicatePicker = false
                        route = .copy(program.id)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(program.name)
                            Text(program.status.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Duplicate")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingDuplicatePicker = false }
                    }
                }
            }
        }
        .overlay {
            if isLoading && programs.isEmpty && bridgeNotice == nil {
                ProgressView()
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .alert("Programs", isPresented: errorIsPresented) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var drafts: [TrainingProgramRecord] {
        programs.filter { $0.status == .draft }
    }

    private var lineageGroups: [ProgramLineageGroup] {
        let archived = programs.filter { $0.status == .archived }
        let grouped = Dictionary(grouping: archived, by: \.lineageId)
        return grouped.map { lineageID, versions in
            let sorted = versions.sorted { $0.version > $1.version }
            return ProgramLineageGroup(
                id: lineageID,
                name: sorted.first?.name ?? "Program",
                versions: sorted
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func programButton(
        _ program: TrainingProgramRecord,
        route destination: ProgramEditorRoute,
        badge: String?
    ) -> some View {
        Button {
            route = destination
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(program.name)
                        .foregroundStyle(.primary)
                    Text("Version \(program.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppColors.calorie.opacity(0.15), in: Capsule())
                        .foregroundStyle(AppColors.calorie)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            programs = try await bridge.listPrograms()
            canEdit = true
            bridgeNotice = nil
        } catch {
            programs = []
            canEdit = false
            let bridgeError = error as? NeonBridgeError
            bridgeNotice = bridgeError?.isConnectivityFailure == false
                ? (error.localizedDescription)
                : "Bridge unavailable"
        }
    }

    private func deleteDraft(_ id: String) async {
        do {
            try await bridge.deleteDraft(id: id)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProgramLineageGroup: Identifiable {
    let id: String
    let name: String
    let versions: [TrainingProgramRecord]
}

struct ProgramEditorView: View {
    let route: ProgramEditorRoute
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftName = ""
    @State private var draft = TrainingProgramBody.blank()
    @State private var sourceID = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmActivate = false
    @State private var confirmDelete = false
    @State private var showingReviseSheet = false
    @State private var changeReason = ""
    @State private var activateOnRevise = true
    @State private var loadFailed = false

    private let bridge = NeonBridgeService.shared

    private var isReadOnly: Bool {
        if loadFailed { return true }
        switch route {
        case .bundled, .remoteReadOnly:
            return true
        case .blank, .copy, .draft, .revise:
            return false
        }
    }

    private var isRevision: Bool {
        if case .revise = route { return true }
        return false
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading program")
            } else {
                editor
            }
        }
        .background(AppColors.appBackground)
        .navigationTitle(draftName.isEmpty ? "Program" : draftName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isReadOnly && !isLoading {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if isRevision {
                            showingReviseSheet = true
                        } else {
                            Task { await saveDraft() }
                        }
                    }
                    .disabled(isSaving || draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .task { await load() }
        .alert("Program", isPresented: errorIsPresented) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Set this program as active?", isPresented: $confirmActivate, titleVisibility: .visible) {
            Button("Set as Active") { Task { await saveAndActivate() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current active program will be archived. History is kept.")
        }
        .confirmationDialog("Delete this draft?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deleteDraft() } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingReviseSheet) {
            NavigationStack {
                Form {
                    Section {
                        TextField("What changed", text: $changeReason, axis: .vertical)
                            .lineLimit(2...4)
                    } footer: {
                        Text("A short note is required. This saves a new version and leaves the previous one in history.")
                    }
                    Toggle("Activate now", isOn: $activateOnRevise)
                        .tint(AppColors.calorie)
                }
                .navigationTitle("New Version")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingReviseSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await saveRevision() } }
                            .disabled(changeReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    }
                }
            }
        }
    }

    private var editor: some View {
        List {
            Section {
                TextField("Name", text: $draftName)
                DatePicker(
                    "Start date",
                    selection: startDateBinding,
                    displayedComponents: .date
                )
                Stepper(value: $draft.dailyStepsTarget, in: 0...50_000, step: 500) {
                    Text("Steps target: \(draft.dailyStepsTarget.formatted())")
                }
                Stepper(value: $draft.weeks, in: 1...52) {
                    Text("Weeks: \(draft.weeks)")
                }
                Stepper(value: reductionWeekBinding, in: 0...max(draft.weeks, 1)) {
                    Text(reductionLabel)
                }
                TextField("Notes", text: notesBinding, axis: .vertical)
                    .lineLimit(2...5)
            }
            .disabled(isReadOnly)
            .listRowBackground(AppColors.appCard)

            Section("Rest days") {
                ForEach(ProgramWeekday.allCases) { weekday in
                    Toggle(weekday.displayName, isOn: restBinding(weekday))
                        .tint(AppColors.calorie)
                }
            }
            .disabled(isReadOnly)
            .listRowBackground(AppColors.appCard)

            Section("Days") {
                ForEach(draft.days) { day in
                    NavigationLink {
                        ProgramDayEditor(day: dayBinding(day.id), isReadOnly: isReadOnly)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.name.isEmpty ? "Untitled day" : day.name)
                            Text("\(day.weekdayLabel) · \(day.exercises.count) exercises")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { source, destination in
                    guard !isReadOnly else { return }
                    moveDays(from: source, to: destination)
                }
                .onDelete { offsets in
                    guard !isReadOnly else { return }
                    deleteDays(at: offsets)
                }

                if !isReadOnly {
                    Button("Add Day", systemImage: "plus") {
                        addDay()
                    }
                }
            }
            .listRowBackground(AppColors.appCard)

            if !isReadOnly && !isRevision {
                Section {
                    Button("Set as Active") { confirmActivate = true }
                        .disabled(isSaving || draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !sourceID.isEmpty, case .draft = route {
                        Button("Delete Draft", role: .destructive) { confirmDelete = true }
                    }
                }
                .listRowBackground(AppColors.appCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .tint(AppColors.calorie)
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { SessionDateFormatting.date(from: draft.startDate) ?? Date() },
            set: { draft.startDate = SessionDateFormatting.calendarDateString(from: $0) }
        )
    }

    private var notesBinding: Binding<String> {
        Binding(get: { draft.notes ?? "" }, set: { draft.notes = $0 })
    }

    private var reductionWeekBinding: Binding<Int> {
        Binding(
            get: { draft.reductionWeek ?? 0 },
            set: { draft.reductionWeek = $0 == 0 ? nil : $0 }
        )
    }

    private var reductionLabel: String {
        if let week = draft.reductionWeek, week > 0 {
            return "Reduction week: \(week)"
        }
        return "Reduction week: none"
    }

    private func restBinding(_ weekday: ProgramWeekday) -> Binding<Bool> {
        Binding(
            get: { draft.restWeekdays.contains { ProgramWeekday.parse($0) == weekday } },
            set: { isOn in
                draft.restWeekdays.removeAll { ProgramWeekday.parse($0) == weekday }
                if isOn { draft.restWeekdays.append(weekday.rawValue) }
            }
        )
    }

    private func dayBinding(_ id: UUID) -> Binding<TrainingProgramDay> {
        Binding(
            get: { draft.days.first { $0.id == id } ?? TrainingProgramDay(dayIndex: 1, weekday: "mon", name: "", conditioning: nil, exercises: []) },
            set: { newValue in
                guard let index = draft.days.firstIndex(where: { $0.id == id }) else { return }
                draft.days[index] = newValue
            }
        )
    }

    private func addDay() {
        let used = Set(draft.days.compactMap { ProgramWeekday.parse($0.weekday) })
        let weekday = ProgramWeekday.allCases.first { !used.contains($0) } ?? .mon
        draft.days.append(
            TrainingProgramDay(
                dayIndex: draft.days.count + 1,
                weekday: weekday.rawValue,
                name: "Day \(draft.days.count + 1)",
                conditioning: TrainingProgramConditioning(minutes: 8, description: ""),
                exercises: []
            )
        )
    }

    private func moveDays(from source: IndexSet, to destination: Int) {
        draft.days.move(fromOffsets: source, toOffset: destination)
    }

    private func deleteDays(at offsets: IndexSet) {
        draft.days.remove(atOffsets: offsets)
    }

    private func load() async {
        guard isLoading else { return }
        switch route {
        case .blank:
            draftName = "New Program"
            draft = .blank()
            isLoading = false
        case .bundled:
            apply(TrainingProgramRecord.bundledV2())
            isLoading = false
        case .copy(let programID):
            await loadRemote(programID, copying: true)
        case .draft(let programID), .revise(let programID), .remoteReadOnly(let programID):
            await loadRemote(programID, copying: false)
        }
    }

    private func loadRemote(_ programID: String, copying: Bool) async {
        do {
            let record = try await bridge.program(id: programID)
            sourceID = copying ? "" : record.id
            if copying {
                draftName = "Copy of \(record.name)"
                draft = record.body ?? .blank()
            } else {
                apply(record)
            }
        } catch {
            errorMessage = (error as? NeonBridgeError)?.isConnectivityFailure == false
                ? error.localizedDescription
                : "Bridge unavailable"
            apply(TrainingProgramRecord.bundledV2())
            sourceID = ""
            loadFailed = true
        }
        isLoading = false
    }

    private func apply(_ record: TrainingProgramRecord) {
        sourceID = record.id
        draftName = record.name
        draft = record.body ?? .blank()
    }

    private func saveDraft() async {
        await write(thenActivate: false)
    }

    private func saveAndActivate() async {
        await write(thenActivate: true)
    }

    private func write(thenActivate: Bool) async {
        isSaving = true
        defer { isSaving = false }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isRevision else { return }
        do {
            let savedID: String
            if sourceID.isEmpty {
                let created = try await bridge.createProgram(name: name, body: draft)
                sourceID = created.id
                savedID = created.id
            } else {
                let updated = try await bridge.updateDraft(id: sourceID, name: name, body: draft)
                savedID = updated.id
            }
            if thenActivate {
                try await bridge.activateProgram(id: savedID)
            }
            onFinished()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveRevision() async {
        let reason = changeReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await bridge.reviseProgram(
                id: sourceID,
                name: draftName.trimmingCharacters(in: .whitespacesAndNewlines),
                body: draft,
                changeReason: reason,
                activate: activateOnRevise
            )
            showingReviseSheet = false
            onFinished()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteDraft() async {
        guard !sourceID.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await bridge.deleteDraft(id: sourceID)
            onFinished()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProgramDayEditor: View {
    @Binding var day: TrainingProgramDay
    let isReadOnly: Bool

    var body: some View {
        List {
            Section {
                TextField("Name", text: $day.name)
                Picker("Weekday", selection: weekdayBinding) {
                    ForEach(ProgramWeekday.allCases) { weekday in
                        Text(weekday.displayName).tag(weekday)
                    }
                }
                Stepper(value: minutesBinding, in: 0...180) {
                    Text("Conditioning: \(day.conditioning?.minutes ?? 0) min")
                }
                TextField("Conditioning description", text: descriptionBinding, axis: .vertical)
                    .lineLimit(2...4)
            }
            .disabled(isReadOnly)
            .listRowBackground(AppColors.appCard)

            Section("Exercises") {
                ForEach(day.exercises) { exercise in
                    NavigationLink {
                        ProgramExerciseEditor(exercise: exerciseBinding(exercise.id), isReadOnly: isReadOnly)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name.isEmpty ? "Untitled exercise" : exercise.name)
                            Text("\(exercise.sets) × \(exercise.reps) · \(exercise.restSec)s rest")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { source, destination in
                    guard !isReadOnly else { return }
                    moveExercises(from: source, to: destination)
                }
                .onDelete { offsets in
                    guard !isReadOnly else { return }
                    deleteExercises(at: offsets)
                }

                if !isReadOnly {
                    Button("Add Exercise", systemImage: "plus") {
                        day.exercises.append(
                            TrainingProgramExercise(
                                order: day.exercises.count,
                                name: "",
                                sets: 3,
                                reps: "10-12",
                                rir: "2",
                                restSec: 90
                            )
                        )
                    }
                }
            }
            .listRowBackground(AppColors.appCard)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .tint(AppColors.calorie)
        .navigationTitle(day.name.isEmpty ? "Day" : day.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isReadOnly {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
    }

    private var weekdayBinding: Binding<ProgramWeekday> {
        Binding(
            get: { ProgramWeekday.parse(day.weekday) ?? .mon },
            set: { day.weekday = $0.rawValue }
        )
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { day.conditioning?.minutes ?? 0 },
            set: { newValue in
                var conditioning = day.conditioning ?? TrainingProgramConditioning(minutes: 0, description: "")
                conditioning.minutes = newValue
                day.conditioning = conditioning
            }
        )
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { day.conditioning?.description ?? "" },
            set: { newValue in
                var conditioning = day.conditioning ?? TrainingProgramConditioning(minutes: 0, description: "")
                conditioning.description = newValue
                day.conditioning = conditioning
            }
        )
    }

    private func exerciseBinding(_ id: UUID) -> Binding<TrainingProgramExercise> {
        Binding(
            get: {
                day.exercises.first { $0.id == id }
                    ?? TrainingProgramExercise(order: 0, name: "", sets: 3, reps: "10-12")
            },
            set: { newValue in
                guard let index = day.exercises.firstIndex(where: { $0.id == id }) else { return }
                day.exercises[index] = newValue
            }
        )
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        day.exercises.move(fromOffsets: source, toOffset: destination)
    }

    private func deleteExercises(at offsets: IndexSet) {
        day.exercises.remove(atOffsets: offsets)
    }
}

private struct ProgramExerciseEditor: View {
    @Binding var exercise: TrainingProgramExercise
    let isReadOnly: Bool

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $exercise.name)
                Stepper(value: $exercise.sets, in: 1...20) {
                    Text("Sets: \(exercise.sets)")
                }
                TextField("Reps", text: $exercise.reps)
                TextField("RIR", text: $exercise.rir)
                Stepper(value: $exercise.restSec, in: 0...600, step: 5) {
                    Text("Rest: \(exercise.restSec) sec")
                }
                TextField("RPE", text: rpeBinding)
                TextField("Load note", text: loadNoteBinding)
                TextField("Notes", text: notesBinding, axis: .vertical)
                    .lineLimit(2...4)
            }
            Section("Substitutions") {
                ForEach(exercise.substitutions.indices, id: \.self) { index in
                    TextField("Substitution", text: $exercise.substitutions[index])
                }
                .onDelete { offsets in
                    exercise.substitutions.remove(atOffsets: offsets)
                }
                if !isReadOnly {
                    Button("Add Substitution", systemImage: "plus") {
                        exercise.substitutions.append("")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .tint(AppColors.calorie)
        .navigationTitle(exercise.name.isEmpty ? "Exercise" : exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isReadOnly)
    }

    private var rpeBinding: Binding<String> {
        Binding(
            get: {
                guard let rpe = exercise.rpe else { return "" }
                return rpe.rounded() == rpe ? String(Int(rpe)) : String(rpe)
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                exercise.rpe = trimmed.isEmpty ? nil : Double(trimmed.replacingOccurrences(of: ",", with: "."))
            }
        )
    }

    private var loadNoteBinding: Binding<String> {
        Binding(get: { exercise.loadNote ?? "" }, set: { exercise.loadNote = $0.isEmpty ? nil : $0 })
    }

    private var notesBinding: Binding<String> {
        Binding(get: { exercise.notes ?? "" }, set: { exercise.notes = $0.isEmpty ? nil : $0 })
    }
}
