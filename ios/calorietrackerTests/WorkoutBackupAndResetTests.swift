import Foundation
import Testing
@testable import calorietracker

/// Workouts are in the iCloud backup (the whole log) and gone after Delete
/// Everything. Workout logs use temporary files and a throwaway UserDefaults
/// suite, never the app's Application Support log.
@MainActor
struct WorkoutBackupAndResetTests {
    private let now = Date(timeIntervalSince1970: 1_791_300_000)

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("workout-backup-\(UUID().uuidString)", isDirectory: true)
    }

    private func defaultsSuite() throws -> (UserDefaults, String) {
        let name = "workout-backup-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    private func filledLog(at url: URL, load: Double = 180, id: String = "w1") throws -> WorkoutLogStore {
        let store = WorkoutLogStore(persistence: .file(url))
        var draft = WorkoutDraft(day: ProgramV2Templates.day1LowerA, now: now)
        draft.sets[draft.exercises[0].name] = [LoggedSet(weight: load, reps: 12, rir: 2, rpeText: "")]
        try store.save(draft.payload(now: now), id: id)
        return store
    }

    @Test func backupCarriesWorkoutsAndRestoreReplacesThem() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (fromDefaults, fromName) = try defaultsSuite()
        let (toDefaults, toName) = try defaultsSuite()
        defer {
            fromDefaults.removePersistentDomain(forName: fromName)
            toDefaults.removePersistentDomain(forName: toName)
        }
        let source = try filledLog(at: folder.appendingPathComponent("a/workout_log_v1.json"))
        try source.correct(id: "w1", with: WorkoutPayload.historyCorrection(
            programVersion: "program-v2", programDay: "Day1_LowerA", sessionDate: "2026-10-06",
            title: "Lower A", conditioning: "", notesText: "fixed", sets: [], now: now))
        let values = CloudBackupService(defaults: fromDefaults, workouts: source).snapshotValues()
        let value = try #require(values[CloudBackupService.workoutsKey])
        #expect(value.t == "d")

        let targetURL = folder.appendingPathComponent("b/workout_log_v1.json")
        let target = try filledLog(at: targetURL, load: 95, id: "other")
        let service = CloudBackupService(defaults: toDefaults, workouts: target)
        service.applyValues(values)
        #expect(service.errorMessage == nil)
        #expect(target.records == source.records)
        #expect(target.record(id: "w1")?.revisions.count == 1)
        // Saved, so a relaunch sees the restored workouts.
        #expect(WorkoutLogStore(persistence: .file(targetURL)).records == source.records)
        // The log is a backup value, never a UserDefaults key.
        #expect(toDefaults.object(forKey: CloudBackupService.workoutsKey) == nil)
    }

    @Test func unchangedWorkoutsBackUpToTheSameBytes() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (defaults, name) = try defaultsSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = try filledLog(at: folder.appendingPathComponent("workout_log_v1.json"))
        let service = CloudBackupService(defaults: defaults, workouts: store)
        let first = service.snapshotValues()
        let second = service.snapshotValues()
        #expect(CloudBackupArchive.contentHash(values: first, photos: [:]) == CloudBackupArchive.contentHash(values: second, photos: [:]))
    }

    @Test func aBadOrDamagedBackupKeepsThePhonesWorkoutsAndSaysSo() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (defaults, name) = try defaultsSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let url = folder.appendingPathComponent("workout_log_v1.json")
        let store = try filledLog(at: url)
        let before = store.records
        let saved = try Data(contentsOf: url)
        let service = CloudBackupService(defaults: defaults, workouts: store)
        let damaged = [
            #"{"version":2,"workouts":[]}"#,
            #"{"version":1}"#,
            #"{"version":1,"workouts":[{"workout":{"id":"x"}}]}"#,
            "not json",
        ]
        for json in damaged {
            service.errorMessage = nil
            service.applyValues([CloudBackupService.workoutsKey: .data(Data(json.utf8))])
            #expect(service.errorMessage?.contains("kept") == true)
            #expect(store.records == before)
            #expect(try Data(contentsOf: url) == saved)
        }
        service.errorMessage = nil
        service.applyValues([CloudBackupService.workoutsKey: CloudBackupValue(t: "d", d: "not base64!")])
        #expect(store.records == before)
        #expect(service.errorMessage != nil)
    }

    @Test func anOlderBackupWithoutWorkoutsLeavesThemAlone() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (defaults, name) = try defaultsSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = try filledLog(at: folder.appendingPathComponent("workout_log_v1.json"))
        let before = store.records
        let service = CloudBackupService(defaults: defaults, workouts: store)
        service.applyValues(["weightUnit": CloudBackupValue(t: "s", s: "lbs")])
        #expect(service.errorMessage == nil)
        #expect(store.records == before)
    }

    @Test func deleteEverythingRemovesTheLogAndItsCopies() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("workout_log_v1.json")
        let store = try filledLog(at: url)
        let bridgeRow = RemoteWorkout(id: "bridge-1", kind: "COMPLETED", programVersion: "program-v2", programDay: "2-tue",
                                      title: "Upper Push", units: "lb", sessionDate: "2026-09-29", conditioning: nil,
                                      notes: [], contentHash: "h1", synthetic: false, recordedAt: nil)
        try store.importFile(WorkoutImportFile(exportedAt: nil, workouts: [WorkoutDetailResponse(workout: bridgeRow, sets: [])],
                                               skipped: 0), now: now)
        let before = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        #expect(before.contains { $0.hasPrefix("workout_log_v1.pre-import-") })

        store.deleteAll()

        #expect(store.records.isEmpty)
        #expect(!store.hasImportedHistory)
        let left = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        #expect(left.filter { $0.hasPrefix("workout_log_v1") }.isEmpty)
        #expect(WorkoutLogStore(persistence: .file(url)).records.isEmpty)
    }
}
