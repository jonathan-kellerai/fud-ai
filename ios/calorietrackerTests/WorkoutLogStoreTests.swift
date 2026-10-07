import Foundation
import Testing
@testable import calorietracker

/// The workout log keeps every saved, corrected and deleted workout in one
/// file on this phone. Real drafts from the bundled Program V2 day, real
/// temporary files; no bridge.
@MainActor
struct WorkoutLogStoreTests {
    private let started = Date(timeIntervalSince1970: 1_791_300_000)
    private let finished = Date(timeIntervalSince1970: 1_791_304_000)

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("workout-log-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(WorkoutLogFile.fileName)
    }

    private func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// Lower A with two leg-press sets, one curl set and conditioning done.
    private func draft() -> WorkoutDraft {
        var draft = WorkoutDraft(day: ProgramV2Templates.day1LowerA, now: started)
        let press = draft.exercises[0].name
        let curl = draft.exercises[1].name
        draft.sets[press] = [
            LoggedSet(weight: 180, reps: 12, rir: 3, rpeText: ""),
            LoggedSet(weight: 185, reps: 10, rir: 1, rpeText: "8,5"),
        ]
        draft.sets[curl] = [LoggedSet(weight: 80, reps: 12, rir: 2, rpeText: "")]
        draft.conditioningCompleted = true
        return draft
    }

    @discardableResult
    private func save(_ store: WorkoutLogStore, _ payload: WorkoutPayload, id: String = UUID().uuidString) throws -> String {
        try store.save(payload, id: id)
        return id
    }

    private func files(beside url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []).sorted()
    }

    @Test func aSavedWorkoutKeepsEverySetConditioningAndTheDay() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let store = WorkoutLogStore(persistence: .file(url))
        let session = draft()
        let id = try save(store, session.payload(now: finished))

        let detail = try #require(store.detail(id: id))
        #expect(detail.workout.programDay == ProgramV2Templates.day1LowerA.id)
        #expect(detail.workout.title == ProgramV2Templates.day1LowerA.title)
        #expect(detail.workout.sessionDate == session.sessionDate)
        #expect(detail.workout.conditioning == ProgramV2Templates.day1LowerA.conditioning)
        #expect(detail.workout.kind == "COMPLETED")
        #expect(detail.sets.map(\.loadLb) == [180, 185, 80])
        #expect(detail.sets.map(\.reps) == [12, 10, 12])
        #expect(detail.sets.map(\.rir) == [3, 1, 2])
        #expect(detail.sets[1].rpe == 8.5)
        #expect(detail.sets.map(\.setOrder) == [0, 1, 2])
        #expect(store.workouts.map(\.id) == [id])
        #expect(store.persistError == nil)
    }

    @Test func workoutsSurviveAReload() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let store = WorkoutLogStore(persistence: .file(url))
        let first = try save(store, draft().payload(now: finished))
        let second = try save(store, draft().payload(now: finished.addingTimeInterval(60)))

        let relaunched = WorkoutLogStore(persistence: .file(url))
        #expect(relaunched.records == store.records)
        // Same day: the later recording is listed first.
        #expect(relaunched.workouts.map(\.id) == [second, first])
        #expect(relaunched.storageNote == nil)
    }

    @Test func savingTheSameDraftAgainKeepsOneWorkout() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let store = WorkoutLogStore(persistence: .file(url))
        let id = try save(store, draft().payload(now: finished))
        // The draft survived a crash after the log write and is saved again.
        try save(store, draft().payload(now: finished.addingTimeInterval(30)), id: id)
        #expect(WorkoutLogStore(persistence: .file(url)).workouts.map(\.id) == [id])

        // A deleted workout isn't brought back by a repeated save, and the save says so.
        try store.delete(id: id)
        #expect(throws: WorkoutLogError.deletedSinceSaved) { try save(store, draft().payload(now: finished), id: id) }
        #expect(store.workouts.isEmpty)
    }

    @Test func aCorrectionChangesTheWorkoutAndKeepsThePriorVersion() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let store = WorkoutLogStore(persistence: .file(url))
        let original = draft().payload(now: finished)
        let id = try save(store, original)
        let before = try #require(store.detail(id: id))

        let corrected = WorkoutPayload(
            kind: "COMPLETED", programVersion: original.programVersion, programDay: original.programDay,
            title: "Lower A (fixed)", units: "lb", sessionDate: original.sessionDate, conditioning: nil,
            notes: ["Second set was 175"], recordedAtUtc: "2026-10-07T20:00:00.000Z",
            openedAtUtc: "2026-10-07T20:00:00.000Z", source: "jl-fud-native",
            sets: [
                WorkoutSet(exercise: original.sets[0].exercise, load: 180, reps: 12, rir: 3, rpe: nil, order: 0),
                WorkoutSet(exercise: original.sets[1].exercise, load: 175, reps: 10, rir: 1, rpe: 8.5, order: 1),
            ]
        )
        try store.correct(id: id, with: corrected, now: finished.addingTimeInterval(3600))

        let relaunched = WorkoutLogStore(persistence: .file(url))
        let record = try #require(relaunched.record(id: id))
        #expect(record.workout.title == "Lower A (fixed)")
        #expect(record.workout.notes == ["Second set was 175"])
        #expect(record.workout.conditioning == nil)
        #expect(record.sets.map(\.loadLb) == [180, 175])
        // Where and when the session happened don't change.
        #expect(record.workout.sessionDate == before.workout.sessionDate)
        #expect(record.workout.recordedAt == before.workout.recordedAt)
        #expect(record.revisions.count == 1)
        #expect(record.revisions[0].workout == before.workout)
        #expect(record.revisions[0].sets == before.sets)
        #expect(relaunched.workouts.count == 1)
    }

    @Test func aDeletedWorkoutLeavesEveryReadAndStaysDeleted() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let store = WorkoutLogStore(persistence: .file(url))
        let kept = try save(store, draft().payload(now: finished))
        let gone = try save(store, draft().payload(now: finished.addingTimeInterval(60)))
        try store.delete(id: gone, now: finished.addingTimeInterval(120))

        let relaunched = WorkoutLogStore(persistence: .file(url))
        #expect(relaunched.workouts.map(\.id) == [kept])
        #expect(relaunched.details.map(\.workout.id) == [kept])
        #expect(relaunched.detail(id: gone) == nil)
        let tombstone = try #require(relaunched.record(id: gone))
        #expect(tombstone.isDeleted)
        #expect(tombstone.sets.isEmpty)
        #expect(throws: WorkoutLogError.notFound) { try relaunched.delete(id: gone) }
        #expect(throws: WorkoutLogError.notFound) { try relaunched.correct(id: gone, with: draft().payload(now: finished)) }
    }

    @Test func anUnreadableLogIsSetAsideAndNeverOverwritten() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let garbage = Data("{not json".utf8)
        try garbage.write(to: url)

        let store = WorkoutLogStore(persistence: .file(url))
        #expect(store.workouts.isEmpty)
        #expect(store.storageNote != nil)
        let aside = try #require(files(beside: url).first { $0.hasPrefix("workout_log_v1.unreadable-") })
        #expect(try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(aside)) == garbage)

        // A new save starts a fresh log; the set-aside bytes are untouched.
        let id = try save(store, draft().payload(now: finished))
        #expect(WorkoutLogStore(persistence: .file(url)).workouts.map(\.id) == [id])
        #expect(try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(aside)) == garbage)
    }

    /// Opens the log while its folder can't be written to, so nothing can be set aside beside it.
    private func openWithoutCopies(_ url: URL) throws -> WorkoutLogStore {
        let directory = url.deletingLastPathComponent().path
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory) }
        return WorkoutLogStore(persistence: .file(url))
    }

    @Test func anUnreadableLogThatCantBeSetAsideIsNeverWrittenOver() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let garbage = Data("{not json".utf8)
        try garbage.write(to: url)

        let store = try openWithoutCopies(url)
        #expect(!files(beside: url).contains { $0.hasPrefix("workout_log_v1.unreadable-") })
        #expect(store.storageNote == WorkoutLogError.unreadableNotKept.localizedDescription)

        // The folder is writable again, but nothing may replace the only copy.
        #expect(throws: WorkoutLogError.unreadableNotKept) { try save(store, draft().payload(now: finished)) }
        #expect(store.persistError == WorkoutLogError.unreadableNotKept.localizedDescription)
        #expect(store.workouts.isEmpty)
        #expect(store.backupData() == nil)
        let source = WorkoutLogStore(persistence: .inMemory)
        try save(source, draft().payload(now: finished))
        let backup = try #require(source.backupData())
        #expect(store.restoreBackupData(backup) != nil)
        #expect(store.workouts.isEmpty)
        #expect(try Data(contentsOf: url) == garbage)

        // Next launch the copy can be made, so a new log starts and the old bytes are kept.
        let relaunched = WorkoutLogStore(persistence: .file(url))
        let aside = try #require(files(beside: url).first { $0.hasPrefix("workout_log_v1.unreadable-") })
        #expect(try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(aside)) == garbage)
        let id = try save(relaunched, draft().payload(now: finished))
        #expect(WorkoutLogStore(persistence: .file(url)).workouts.map(\.id) == [id])
    }

    /// Makes the saved log unreadable (as file protection does before first unlock) or readable again.
    private func lock(_ url: URL, _ locked: Bool) throws {
        try FileManager.default.setAttributes([.posixPermissions: locked ? 0o000 : 0o644], ofItemAtPath: url.path)
    }

    @Test func aLogThatCantBeOpenedIsNeverWrittenOverAndOpensOnceReadable() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let id = try save(WorkoutLogStore(persistence: .file(url)), draft().payload(now: finished))
        let saved = try Data(contentsOf: url)
        try lock(url, true)
        defer { try? lock(url, false) }

        let store = WorkoutLogStore(persistence: .file(url))
        #expect(store.workouts.isEmpty)
        #expect(store.storageNote == WorkoutLogError.notOpened.localizedDescription)
        #expect(throws: WorkoutLogError.notOpened) { try save(store, draft().payload(now: finished)) }
        #expect(store.persistError == WorkoutLogError.notOpened.localizedDescription)
        #expect(throws: WorkoutLogError.notOpened) {
            try store.importFile(WorkoutImportFile.load(from: WorkoutImportFixture.url), now: finished)
        }
        #expect(store.backupData() == nil)
        let source = WorkoutLogStore(persistence: .inMemory)
        try save(source, draft().payload(now: finished))
        #expect(store.restoreBackupData(try #require(source.backupData())) != nil)
        // Nothing was set aside or started in its place.
        #expect(files(beside: url) == [WorkoutLogFile.fileName])

        try lock(url, false)
        #expect(try Data(contentsOf: url) == saved)
        store.reloadIfNotOpened()
        #expect(store.workouts.map(\.id) == [id])
        #expect(store.storageNote == nil)
        let second = try save(store, draft().payload(now: finished))
        #expect(Set(WorkoutLogStore(persistence: .file(url)).workouts.map(\.id)) == [id, second])
    }

    @Test func aSaveAfterTheLogBecomesReadableKeepsEveryEarlierWorkout() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let id = try save(WorkoutLogStore(persistence: .file(url)), draft().payload(now: finished))
        try lock(url, true)
        let store = WorkoutLogStore(persistence: .file(url))
        try lock(url, false)

        // No foreground in between: the save itself reads the log first.
        let second = try save(store, draft().payload(now: finished))
        #expect(Set(store.workouts.map(\.id)) == [id, second])
        #expect(Set(WorkoutLogStore(persistence: .file(url)).workouts.map(\.id)) == [id, second])
    }

    @Test func skippedRecordsThatCantBeSetAsideAreShownButNeverDropped() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let id = try save(WorkoutLogStore(persistence: .file(url)), draft().payload(now: finished))
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var rows = try #require(json["workouts"] as? [[String: Any]])
        rows.append(["workout": ["id": "broken"]])
        json["workouts"] = rows
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let saved = try Data(contentsOf: url)

        let store = try openWithoutCopies(url)
        #expect(store.workouts.map(\.id) == [id])
        #expect(store.storageNote == WorkoutLogError.unreadableNotKept.localizedDescription)
        #expect(throws: WorkoutLogError.unreadableNotKept) { try store.delete(id: id) }
        #expect(throws: WorkoutLogError.unreadableNotKept) { try save(store, draft().payload(now: finished)) }
        #expect(store.workouts.map(\.id) == [id])
        #expect(try Data(contentsOf: url) == saved)
    }

    @Test func oneBadRecordIsSkippedCountedAndTheRestKept() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let store = WorkoutLogStore(persistence: .file(url))
        let id = try save(store, draft().payload(now: finished))
        // Break a copy of the saved log: a second record with no sets.
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var rows = try #require(json["workouts"] as? [[String: Any]])
        rows.append(["workout": ["id": "broken"]])
        json["workouts"] = rows
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let reopened = WorkoutLogStore(persistence: .file(url))
        #expect(reopened.workouts.map(\.id) == [id])
        #expect(reopened.storageNote == "1 saved workout couldn't be read, so it isn't listed.")
        #expect(files(beside: url).contains { $0.hasPrefix("workout_log_v1.unreadable-") })

        // The count is saved with the next change, so the note survives a relaunch.
        _ = try save(reopened, draft().payload(now: finished.addingTimeInterval(60)))
        let relaunched = WorkoutLogStore(persistence: .file(url))
        #expect(relaunched.workouts.count == 2)
        #expect(relaunched.storageNote == "1 saved workout couldn't be read, so it isn't listed.")
    }

    @Test func aLogFromANewerAppIsLeftUntouched() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let newer = Data(#"{"version":2,"workouts":[]}"#.utf8)
        try newer.write(to: url)

        let store = WorkoutLogStore(persistence: .file(url))
        #expect(store.storageNote != nil)
        #expect(throws: WorkoutLogError.newerVersion) { try save(store, draft().payload(now: finished)) }
        #expect(store.workouts.isEmpty)
        #expect(try Data(contentsOf: url) == newer)
    }

    @Test func aFailedWriteChangesNothing() throws {
        // The log's folder is a plain file, so nothing can be written under it.
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("workout-log-blocker-\(UUID().uuidString)")
        try Data("x".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let store = WorkoutLogStore(persistence: .file(blocker.appendingPathComponent(WorkoutLogFile.fileName)))

        #expect(throws: (any Error).self) { try save(store, draft().payload(now: finished)) }
        #expect(store.records.isEmpty)
        #expect(store.persistError != nil)
    }

    @Test func aHistoryCorrectionKeepsNonBlankNoteLinesAndDropsEmptyConditioning() throws {
        let set = RemoteWorkoutSet(id: "7", workoutId: "w", setOrder: 3, exercise: "Leg press", loadLb: 180,
                                   reps: 12, rir: 2, rpe: nil, exercisePosition: 1, plannedPosition: 2)
        var edited = EditableBridgeSet(set)
        edited.rpeText = "8,5"
        let payload = WorkoutPayload.historyCorrection(
            programVersion: "program-v2", programDay: "1-mon", sessionDate: "2026-10-06",
            title: "Lower A", conditioning: "", notesText: " first \n\n  second  \n",
            sets: [edited], now: Date(timeIntervalSince1970: 0)
        )
        #expect(payload.notes == ["first", "second"])
        #expect(payload.conditioning == nil)
        #expect(payload.recordedAtUtc == "1970-01-01T00:00:00Z")
        #expect(payload.sets == [WorkoutSet(exercise: "Leg press", load: 180, reps: 12, rir: 2, rpe: 8.5, order: 3,
                                            exercisePosition: 1, plannedPosition: 2)])
    }

    @Test func lastPerformanceAndTheProgressionRuleReadTheLog() throws {
        let store = WorkoutLogStore(persistence: .inMemory)
        let day = ProgramV2Templates.day1LowerA
        let press = day.exercises[0]
        // An older session, then the latest: leg press 180 x 15 at RIR 4 on set 1.
        var older = WorkoutDraft(day: day, now: started.addingTimeInterval(-7 * 86_400))
        older.sets[press.name] = [LoggedSet(weight: 175, reps: 12, rir: 2, rpeText: "")]
        try save(store, older.payload(now: finished.addingTimeInterval(-7 * 86_400)))
        var latest = WorkoutDraft(day: day, now: started)
        latest.sets[press.name] = [LoggedSet(weight: 180, reps: 15, rir: 4, rpeText: ""),
                                   LoggedSet(weight: 180, reps: 13, rir: 2, rpeText: "")]
        try save(store, latest.payload(now: finished))

        let history = ExerciseHistoryLoader.load(programDay: day.id, log: store)
        let last = try #require(history[LastPerformanceBuilder.key(for: press.name)])
        #expect(last.sessionDate == latest.sessionDate)
        #expect(last.sets.map(\.load) == [180, 180])
        // Top of 10-15 at RIR 4: +5 lb, computed on the phone.
        let decision = ProgressionRule.suggestedDecision(last: last, reps: press.reps, startLoadLb: press.startLoadLb)
        #expect(decision == ProgressionDecision(load: 185, reason: .increase))

        // A deleted session no longer counts.
        let latestID = try #require(store.workouts.first?.id)
        try store.delete(id: latestID)
        let afterDelete = try #require(ExerciseHistoryLoader.load(programDay: day.id, log: store)[LastPerformanceBuilder.key(for: press.name)])
        #expect(afterDelete.sets.map(\.load) == [175])
    }

    @Test func inMemoryLogsWriteNothing() throws {
        let store = WorkoutLogStore(persistence: .inMemory)
        let id = try save(store, draft().payload(now: finished))
        #expect(store.workouts.map(\.id) == [id])
        #expect(WorkoutLogStore(persistence: .inMemory).workouts.isEmpty)
    }
}
