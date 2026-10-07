//
//  WorkoutHistoryEditView.swift
//  calorietracker
//
//  Edit or delete a Neon bridge workout.
//

import SwiftUI

struct WorkoutHistoryEditView: View {
    let workoutID: String
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
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

    private let neonBridge = NeonBridgeService.shared

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
                            Task { await save() }
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
            await load()
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
                Task { await deleteWorkout() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let detail = try await neonBridge.getWorkout(id: workoutID)
            title = detail.workout.title
            programDay = detail.workout.programDay
            programVersion = detail.workout.programVersion
            sessionDate = String(detail.workout.sessionDate.prefix(10))
            conditioning = detail.workout.conditioning ?? ""
            notes = detail.workout.notes.joined(separator: "\n")
            sets = detail.sets
                .sorted { $0.setOrder < $1.setOrder }
                .map { EditableBridgeSet($0) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
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
            _ = try await neonBridge.updateWorkout(id: workoutID, payload: payload)
            onChanged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteWorkout() async {
        do {
            try await neonBridge.deleteWorkout(id: workoutID)
            onChanged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
