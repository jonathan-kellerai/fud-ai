import Foundation
import Testing
@testable import calorietracker

/// The one-time import of the bridge's workout export from a file, using the
/// synthetic export (Fixtures/jl-workouts-import.json, 11 workouts, 87 sets).
@MainActor
struct WorkoutImportTests {
    private let now = Date(timeIntervalSince1970: 1_791_380_000)

    private var fixtureURL: URL { WorkoutImportFixture.url }

    private func fixture() throws -> WorkoutImportFile {
        try WorkoutImportFile.load(from: fixtureURL)
    }

    private func fixtureJSON() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("workout-import-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(WorkoutLogFile.fileName)
    }

    private func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test func theExportReadsAsElevenWorkoutsWithTheirSets() throws {
        let file = try fixture()
        #expect(file.workouts.count == 11)
        #expect(file.skipped == 0)
        #expect(file.workouts.reduce(0) { $0 + $1.sets.count } == 87)
        let first = try #require(file.workouts.first)
        #expect(first.workout.id == "a31158d9-6cec-40b9-8245-af4f7caabbfd")
        #expect(first.workout.programDay == "1-mon")
        #expect(first.workout.conditioning == "bike 10 min steady")
        #expect(first.workout.sourceFingerprint == "c2815b71a304081e7a7268163788bc5e")
        #expect(first.sets.map(\.setOrder) == Array(0..<8))
        #expect(first.sets[0].exercise == "Leg press")
        #expect(first.sets[0].loadLb == 200)
        #expect(first.sets[0].loggedAt == "2026-10-05T10:15:00.000Z")
    }

    @Test func importingTwiceStillGivesElevenWorkouts() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let store = WorkoutLogStore(persistence: .file(url))
        let file = try fixture()

        #expect(store.importSummary(of: file) == WorkoutImportSummary(added: 11, duplicates: 0, skipped: 0))
        let first = try store.importFile(file, now: now)
        #expect(first.resultText == "11 workouts imported, 0 duplicates")
        #expect(store.workouts.count == 11)
        #expect(store.hasImportedHistory)

        let second = try store.importFile(file, now: now.addingTimeInterval(60))
        #expect(second == WorkoutImportSummary(added: 0, duplicates: 11, skipped: 0))
        #expect(second.resultText == "0 workouts imported, 11 duplicates")

        let relaunched = WorkoutLogStore(persistence: .file(url))
        #expect(relaunched.workouts.count == 11)
        #expect(relaunched.details.reduce(0) { $0 + $1.sets.count } == 87)
        // Newest session first; the two 9/17 sessions both kept.
        #expect(relaunched.workouts.first?.sessionDate.hasPrefix("2026-10-05") == true)
        #expect(relaunched.workouts.filter { $0.sessionDate.hasPrefix("2026-09-17") }.count == 2)
        #expect(relaunched.hasImportedHistory)
        #expect(try relaunched.importFile(file).added == 0)
    }

    @Test func importAddsToWorkoutsAlreadySavedAndCopiesTheLogFirst() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let store = WorkoutLogStore(persistence: .file(url))
        var draft = WorkoutDraft(day: ProgramV2Templates.day1LowerA, now: now)
        draft.sets[draft.exercises[0].name] = [LoggedSet(weight: 185, reps: 12, rir: 2, rpeText: "")]
        try store.save(draft.payload(now: now), id: "saved-on-phone")
        let before = try Data(contentsOf: url)

        try store.importFile(try fixture(), now: now)

        #expect(store.workouts.count == 12)
        #expect(store.detail(id: "saved-on-phone") != nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        let copy = try #require(names.first { $0.hasPrefix("workout_log_v1.pre-import-") })
        #expect(try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(copy)) == before)
    }

    @Test func aContentHashDuplicateOrADeletedWorkoutIsNotAdded() throws {
        var json = try fixtureJSON()
        var rows = try #require(json["workouts"] as? [[String: Any]])
        // The first workout again under a new id: same content hash.
        var copy = rows[0]
        var workout = try #require(copy["workout"] as? [String: Any])
        workout["id"] = "same-content-new-id"
        copy["workout"] = workout
        rows.append(copy)
        json["workouts"] = rows
        let file = try WorkoutImportFile.decode(JSONSerialization.data(withJSONObject: json))

        let store = WorkoutLogStore(persistence: .inMemory)
        #expect(store.importSummary(of: file) == WorkoutImportSummary(added: 11, duplicates: 1, skipped: 0))
        try store.importFile(file)
        #expect(store.workouts.count == 11)

        // Deleted on the phone: a later import of the same file doesn't bring it back.
        let deleted = "a31158d9-6cec-40b9-8245-af4f7caabbfd"
        try store.delete(id: deleted)
        #expect(try store.importFile(file).added == 0)
        #expect(store.detail(id: deleted) == nil)
        #expect(store.workouts.count == 10)
    }

    @Test func aCorrectedThenDeletedWorkoutIsNotAddedBackByItsOriginalHash() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let store = WorkoutLogStore(persistence: .file(url))
        let file = try fixture()
        try store.importFile(file, now: now)
        let original = try #require(file.workouts.first?.workout)
        let hash = try #require(original.contentHash)

        // A correction moves the original hash into the replaced version; Delete drops that version.
        var draft = WorkoutDraft(day: ProgramV2Templates.day1LowerA, now: now)
        draft.sets[draft.exercises[0].name] = [LoggedSet(weight: 205, reps: 8, rir: 1, rpeText: "")]
        try store.correct(id: original.id, with: draft.payload(now: now), now: now)
        try store.delete(id: original.id, now: now.addingTimeInterval(60))

        let relaunched = WorkoutLogStore(persistence: .file(url))
        let record = try #require(relaunched.record(id: original.id))
        #expect(record.isDeleted)
        #expect(record.sets.isEmpty && record.revisions.isEmpty)
        #expect(record.tombstone == WorkoutTombstone(ids: [original.id], contentHashes: [hash]))

        // The same file, plus the original under a new id: nothing comes back.
        var json = try fixtureJSON()
        var rows = try #require(json["workouts"] as? [[String: Any]])
        var copy = rows[0]
        var workout = try #require(copy["workout"] as? [String: Any])
        workout["id"] = "same-content-new-id"
        copy["workout"] = workout
        rows.append(copy)
        json["workouts"] = rows
        let again = try WorkoutImportFile.decode(JSONSerialization.data(withJSONObject: json))
        #expect(try relaunched.importFile(again) == WorkoutImportSummary(added: 0, duplicates: 12, skipped: 0))
        #expect(relaunched.workouts.count == 10)
        #expect(relaunched.detail(id: "same-content-new-id") == nil)
    }

    @Test func aWrongFormatOversizeOrBrokenFileIsRefusedAndChangesNothing() throws {
        var json = try fixtureJSON()
        json["format"] = "jl-peptides"
        #expect(throws: WorkoutImportError.wrongFormat) {
            try WorkoutImportFile.decode(JSONSerialization.data(withJSONObject: json))
        }
        #expect(throws: WorkoutImportError.unreadable) { try WorkoutImportFile.decode(Data("{not json".utf8)) }
        #expect(throws: WorkoutImportError.unreadable) {
            try WorkoutImportFile.decode(Data(#"{"format":"jl-workouts-export-v1"}"#.utf8))
        }
        #expect(throws: WorkoutImportError.tooLarge) {
            try WorkoutImportFile.decode(Data(repeating: 0x20, count: WorkoutImportFile.maxBytes + 1))
        }

        let big = tempURL()
        defer { cleanUp(big) }
        try FileManager.default.createDirectory(at: big.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x20, count: WorkoutImportFile.maxBytes + 1).write(to: big)
        #expect(throws: WorkoutImportError.tooLarge) { try WorkoutImportFile.load(from: big) }
    }

    @Test func aBadWorkoutIsSkippedAndCountedAndTheRestImported() throws {
        var json = try fixtureJSON()
        var rows = try #require(json["workouts"] as? [Any])
        rows.append(["workout": ["id": "no-sets"]])
        var undated = try #require(rows[1] as? [String: Any])
        var workout = try #require(undated["workout"] as? [String: Any])
        workout["id"] = "undated"
        workout["content_hash"] = "undated-hash"
        workout["session_date"] = "sometime"
        undated["workout"] = workout
        rows.append(undated)
        rows.append("garbage")
        json["workouts"] = rows
        let file = try WorkoutImportFile.decode(JSONSerialization.data(withJSONObject: json))
        #expect(file.workouts.count == 11)
        #expect(file.skipped == 3)

        let store = WorkoutLogStore(persistence: .inMemory)
        #expect(try store.importFile(file) == WorkoutImportSummary(added: 11, duplicates: 0, skipped: 3))
    }

    @Test func aReadOnlyLogRefusesTheImport() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let newer = Data(#"{"version":2,"workouts":[]}"#.utf8)
        try newer.write(to: url)
        let store = WorkoutLogStore(persistence: .file(url))
        #expect(throws: WorkoutLogError.newerVersion) { try store.importFile(try fixture()) }
        #expect(store.workouts.isEmpty)
        #expect(try Data(contentsOf: url) == newer)
    }

    @Test func afterAnImportNextInCycleReadsOnlyTheLog() throws {
        let suiteName = "WorkoutImportTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let body = TrainingProgramBody.bundledV2()
        // A stale bridge-era cache: one session on a day the export doesn't have.
        let stale = RemoteWorkout(id: "stale", kind: "COMPLETED", programVersion: "program-v2", programDay: "5-fri",
                                  title: "", units: "lb", sessionDate: "2026-10-02", conditioning: nil, notes: [],
                                  contentHash: nil, synthetic: false, recordedAt: nil)
        TrainProgressStore(defaults: defaults).replaceHistory(with: [stale], days: body.days)

        let store = TrainProgressStore(defaults: defaults)
        let log = WorkoutLogStore(persistence: .inMemory)
        try log.importFile(try fixture())
        store.adopt(log, days: body.days)

        #expect(!store.history.contains { $0.sessionDate == "2026-10-02" })
        #expect(store.history.contains(CompletedProgramSession(dayIndex: 1, sessionDate: "2026-10-05",
                                                                 recordedAt: "2026-10-05T10:15:00.000Z")))
        // Saved, so a relaunch before the log is read sees the same history.
        #expect(TrainProgressStore(defaults: defaults).history == store.history)
    }
}
