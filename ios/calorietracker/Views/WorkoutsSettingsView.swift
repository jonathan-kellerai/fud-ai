//
//  WorkoutsSettingsView.swift
//  calorietracker
//
//  More › Training › Workouts: how many workouts are on this phone, their
//  history, and the one-time import from a workouts file (Files picker).
//  Nothing here talks to a network.
//

import SwiftUI

struct WorkoutsSettingsView: View {
    @Environment(WorkoutLogStore.self) private var workoutLog
    @State private var isPickingFile = false
    @State private var importRequest: WorkoutImportRequest?
    @State private var importError: String?

    var body: some View {
        List {
            Section {
                LabeledContent("On this phone", value: WorkoutCount.text(workoutLog.workouts.count))
                    .accessibilityIdentifier("workouts.settings.count")
                NavigationLink {
                    WorkoutHistoryListView()
                } label: {
                    Label("Workout history", systemImage: "clock.arrow.circlepath")
                }
            } header: {
                IronSectionTitle(title: "Workouts")
            } footer: {
                Text("Workouts are saved only on this phone. Nothing is sent to the bridge.")
            }
            .listRowBackground(AppColors.appCard)

            Section {
                Button {
                    isPickingFile = true
                } label: {
                    Label("Import from a file", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("workouts.settings.import")
                .accessibilityHint("Adds workouts from a JL workouts export. You see what it adds first.")
            } header: {
                IronSectionTitle(title: "Import")
            } footer: {
                Text("Pick a JL workouts export (.json) in Files. Workouts already on this phone are skipped, so importing the same file twice adds nothing.")
            }
            .listRowBackground(AppColors.appCard)

            if let note = workoutLog.storageNote {
                Section {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(IronTheme.textSecondary)
                }
                .listRowBackground(AppColors.appCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: loadFile
        )
        .sheet(item: $importRequest) { request in
            WorkoutImportPreviewSheet(file: request.file)
        }
        .alert("Unable to Import", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "The selected file could not be imported.")
        }
    }

    /// Validates the picked file; nothing changes until the preview is confirmed.
    private func loadFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            importRequest = WorkoutImportRequest(file: try WorkoutImportFile.load(from: url))
        } catch {
            importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// A file that passed validation, waiting for the user to confirm.
struct WorkoutImportRequest: Identifiable {
    let id = UUID().uuidString
    var file: WorkoutImportFile
}

/// Says what the file adds before anything changes, then what it added.
struct WorkoutImportPreviewSheet: View {
    @Environment(WorkoutLogStore.self) private var workoutLog
    @Environment(\.dismiss) private var dismiss
    let file: WorkoutImportFile
    @State private var imported: WorkoutImportSummary?
    @State private var importError: String?

    init(file: WorkoutImportFile) {
        self.file = file
    }

    var body: some View {
        let summary = workoutLog.importSummary(of: file)
        return NavigationStack {
            List {
                if let imported {
                    Section {
                        Label(imported.resultText, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(IronTheme.textPrimary)
                            .accessibilityIdentifier("workouts.import.result")
                    } footer: {
                        Text("Nothing already on this phone was changed.")
                    }
                    .listRowBackground(AppColors.appCard)
                } else {
                    Section {
                        LabeledContent("New workouts", value: "\(summary.added)")
                        LabeledContent("Already on this phone", value: "\(summary.duplicates)")
                        if summary.skipped > 0 {
                            LabeledContent("Couldn't be read", value: "\(summary.skipped)")
                        }
                    } header: {
                        IronSectionTitle(title: "This file")
                    }
                    .listRowBackground(AppColors.appCard)

                    Section {
                        Button(summary.added == 0 ? "Nothing new to import" : "Import \(WorkoutCount.text(summary.added))") {
                            do {
                                imported = try workoutLog.importFile(file)
                            } catch {
                                importError = error.localizedDescription
                            }
                        }
                        .disabled(summary.added == 0)
                        .accessibilityIdentifier("workouts.import.confirm")
                    } footer: {
                        Text("Only workouts that aren't on this phone yet are added. Nothing is changed or removed.")
                    }
                    .listRowBackground(AppColors.appCard)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.appBackground)
            .navigationTitle("Import workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(imported == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
            .alert("Unable to Import", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }
}

#if DEBUG
extension WorkoutImportPreviewSheet {
    /// Visual QA shows the sheet after an import without tapping through it.
    init(file: WorkoutImportFile, visualQAImported: WorkoutImportSummary) {
        self.file = file
        _imported = State(initialValue: visualQAImported)
    }
}
#endif
