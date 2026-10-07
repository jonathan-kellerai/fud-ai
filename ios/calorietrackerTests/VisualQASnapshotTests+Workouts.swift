import SwiftUI
import XCTest
@testable import calorietracker

/// Shots 106-109: workouts on this phone only (build 70). History (13) and
/// workout detail (14) already read the on-device log. Synthetic workouts
/// only: the real export is a unit-test fixture and never shown here.
extension VisualQASnapshotTests {
    /// More › Training › Workouts before the one-time import: nothing on this phone yet.
    func test106WorkoutsSettingsBeforeImport() async throws {
        VisualQAFixtures.workoutHistory = []
        defer { VisualQAFixtures.workoutHistory = nil }
        try await capture("106-workouts-settings") { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "Training") { WorkoutsSettingsView() }
            }
        }
    }

    /// The file picked in Files, previewed before anything changes.
    func test107WorkoutsImportPreview() async throws {
        let file = VisualQAFixtures.workoutImportFile()
        XCTAssertEqual(WorkoutLogStore(persistence: .inMemory).importSummary(of: file),
                       WorkoutImportSummary(added: 11, duplicates: 0, skipped: 0))
        VisualQAFixtures.workoutHistory = []
        defer { VisualQAFixtures.workoutHistory = nil }
        try await capture("107-workouts-import-preview", sheet: {
            WorkoutImportPreviewSheet(file: file)
        }) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "Training") { WorkoutsSettingsView() }
            }
        }
    }

    /// After Import: "11 workouts imported, 0 duplicates", over a log that now holds them.
    func test108WorkoutsImported() async throws {
        let file = VisualQAFixtures.workoutImportFile()
        let log = WorkoutLogStore(persistence: .inMemory)
        let result = try log.importFile(file)
        XCTAssertEqual(result.resultText, "11 workouts imported, 0 duplicates")
        XCTAssertEqual(try log.importFile(file).added, 0)
        VisualQAFixtures.workoutHistory = log.details
        defer { VisualQAFixtures.workoutHistory = nil }
        try await capture("108-workouts-imported", sheet: {
            WorkoutImportPreviewSheet(file: file, visualQAImported: result)
        }) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "Training") { WorkoutsSettingsView() }
            }
        }
    }

    /// The logger's confirmation once the workout is saved on this phone.
    func test109LoggerSaveConfirmation() async throws {
        executionTimeAllowance = 240
        VisualQAFixtures.workoutHistory = VisualQAFixtures.build62History()
        defer { VisualQAFixtures.workoutHistory = nil }
        try await capture("109-logger-saved", sheet: {
            let seeded = VisualQABuild62Fixture(scenario: .rows)
            VisualQAGraveyard.keep(seeded, seeded.drafts, seeded.entry, seeded.rest)
            return ProgramV2WorkoutLogView(visualQAEntry: seeded.entry, restSession: seeded.rest,
                                           openedAt: seeded.date, showsSaveConfirmation: true)
                .environment(seeded.drafts)
        }) { _ in
            VisualQATabShell(selected: .train) {
                JLPhysicalTabView(referenceDate: VisualQABuild62Fixture.Scenario.rows.date)
            }
        }
    }
}

@MainActor
extension VisualQAFixtures {
    /// A synthetic jl-workouts-export-v1 file: 11 Program V2 sessions on
    /// 9/14 – 10/6, three sets each, with bridge-style ids and content hashes.
    static func workoutImportFile() -> WorkoutImportFile {
        let days = TrainingProgramBody.bundledV2().days
        let dates = ["2026-09-14", "2026-09-15", "2026-09-16", "2026-09-17", "2026-09-21", "2026-09-22",
                     "2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-06"]
        let workouts = dates.enumerated().map { index, date -> WorkoutDetailResponse in
            let day = days[index % min(4, days.count)]
            let id = "qa-import-\(index + 1)"
            let workout = RemoteWorkout(id: id, kind: "COMPLETED", programVersion: "program-v2",
                programDay: day.asProgramV2Day().id, title: day.name, units: "lb",
                sessionDate: date + "T00:00:00.000Z", conditioning: index % 3 == 0 ? "Bike 15 min" : nil,
                notes: [], contentHash: "qa-hash-\(index + 1)", synthetic: false,
                recordedAt: date + "T11:40:00.000Z")
            let exercise = day.exercises.first?.name ?? "Leg press"
            let sets = (0..<3).map { set in
                RemoteWorkoutSet(id: "\(id)-\(set)", workoutId: id, setOrder: set, exercise: exercise,
                                 loadLb: Double(100 + index * 5), reps: 12 - set, rir: 2, rpe: nil)
            }
            return WorkoutDetailResponse(workout: workout, sets: sets)
        }
        return WorkoutImportFile(exportedAt: "2026-10-07", workouts: workouts, skipped: 0)
    }
}
