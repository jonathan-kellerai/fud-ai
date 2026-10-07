//
//  WorkoutHistoryEditView.swift
//  calorietracker
//
//  Edit or delete a workout saved on this phone. A correction keeps the
//  version it replaces in the workout log.
//

import SwiftUI

struct WorkoutHistoryEditView: View {
    let workoutID: String
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(WorkoutLogStore.self) private var workoutLog
    @State private var title = ""
    @State private var programDay = ""
    @State private var programVersion = "program-v2"
    @State private var sessionDate = ""
    @State private var conditioning = ""
    @State private var notes = ""
    @State private var sets: [EditableBridgeSet] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    /// Widens the RPE input with Dynamic Type (capped at the row's xxLarge
    /// ceiling) so its placeholder never truncates.
    @ScaledMetric(relativeTo: .body) private var inputScale: CGFloat = 1

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading workout")
            } else {
                Form {
                    Section("Session") {
                        TextField("Title", text: $title)
                        Text(programDay)
                            .foregroundStyle(.secondary)
                        TextField("Conditioning", text: $conditioning, axis: .vertical)
                        TextField("Notes", text: $notes, axis: .vertical)
                    }

                    Section("Sets") {
                        ForEach($sets) { $set in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(set.exercise)
                                    .font(.subheadline.bold())
                                HStack {
                                    TextField("Load", value: $set.load, format: .number)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                    Text("lb ×")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize()
                                    TextField("Reps", value: $set.reps, format: .number)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.roundedBorder)
                                    Text("RIR")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize()
                                    TextField("RIR", value: $set.rir, format: .number)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.roundedBorder)
                                    TextField("RPE", text: $set.rpeText)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: (60 * min(max(inputScale, 1), 1.4)).rounded())
                                        .accessibilityLabel("RPE, rate of perceived exertion")
                                }
                                // Five inputs share one row; at accessibility
                                // sizes the load showed "…" and "lb ×" wrapped.
                                .lineLimit(1)
                                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                            }
                        }
                    }

                    Section {
                        Button("Save changes") {
                            save()
                        }
                        .disabled(isSaving || sets.isEmpty)

                        Button("Delete workout", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
        }
        .navigationTitle(title.isEmpty ? "Edit Workout" : title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            load()
        }
        .alert("Could Not Update", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteWorkout()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        guard let detail = workoutLog.detail(id: workoutID) else {
            errorMessage = WorkoutLogError.notFound.localizedDescription
            return
        }
        title = detail.workout.title
        programDay = detail.workout.programDay
        programVersion = detail.workout.programVersion
        sessionDate = String(detail.workout.sessionDate.prefix(10))
        conditioning = detail.workout.conditioning ?? ""
        notes = detail.workout.notes.joined(separator: "\n")
        sets = detail.sets
            .sorted { $0.setOrder < $1.setOrder }
            .map { EditableBridgeSet($0) }
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }

        let payload = WorkoutPayload.historyCorrection(
            programVersion: programVersion,
            programDay: programDay,
            sessionDate: sessionDate,
            title: title,
            conditioning: conditioning,
            notesText: notes,
            sets: sets
        )

        do {
            try workoutLog.correct(id: workoutID, with: payload)
            onChanged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteWorkout() {
        do {
            try workoutLog.delete(id: workoutID)
            onChanged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
