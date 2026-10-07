import Foundation
import Testing
@testable import calorietracker

/// A saved peptide log this app can't open or can't read in full is never
/// written over: the store refuses changes until the file opens or its bytes
/// are kept aside. Real files in a temp directory, a throwaway UserDefaults
/// suite, synthetic data only.
@MainActor
struct PeptideUnreadableLogTests {
    private let takenAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func draft(compound: String = "BPC-157") -> PeptideLogDraft {
        var draft = PeptideLogDraft.new(compound: compound, now: takenAt)
        draft.drawText = "50"
        draft.drawUnit = .units
        return draft
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("peptide-unreadable-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("peptide_log_v1.json")
    }

    private func cleanUp(_ url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: directory)
    }

    private func files(beside url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []).sorted()
    }

    // MARK: Reading the file

    private func isMissing(_ url: URL) -> Bool {
        if case .missing = DeviceLogFile(url: url, defaults: nil, defaultsKey: "unused").readFile() { return true }
        return false
    }

    @Test func noFileAtThePathReadsAsMissingAndALockedFileDoesNot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("device-log-\(UUID().uuidString)")
        defer { cleanUp(directory.appendingPathComponent("locked.json")) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A plain file where a folder should be.
        let blocker = directory.appendingPathComponent("blocked")
        try Data().write(to: blocker)
        #expect(isMissing(blocker.appendingPathComponent("log.json")))
        // A folder where the file should be.
        let folder = directory.appendingPathComponent("folder.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        #expect(isMissing(folder))
        // A file that is there but can't be read.
        let locked = directory.appendingPathComponent("locked.json")
        try Data("{}".utf8).write(to: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        guard case .failed = DeviceLogFile(url: locked, defaults: nil, defaultsKey: "unused").readFile() else {
            Issue.record("A locked file should read as failed")
            return
        }
    }

    // MARK: A log that can't be opened

    private func defaultsSuite() throws -> (UserDefaults, String) {
        let name = "peptide-unreadable-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    /// Makes the saved log unreadable (as file protection does before first unlock) or readable again.
    private func lock(_ url: URL, _ locked: Bool) throws {
        try FileManager.default.setAttributes([.posixPermissions: locked ? 0o000 : 0o644], ofItemAtPath: url.path)
    }

    /// A saved log with one dose and one vial; returns the dose id.
    private func savedLog(at url: URL, defaults: UserDefaults? = nil) throws -> String {
        let store = PeptideLogStore(persistence: .file(url, defaults: defaults))
        store.saveVial(PeptideVial(id: "v-saved", compound: "BPC-157", diluentML: 2))
        let id = try #require(store.log(draft(), now: takenAt))
        #expect(store.persistError == nil)
        return id
    }

    private func otherArchive() throws -> Data {
        let source = PeptideLogStore(persistence: .inMemory)
        _ = source.log(draft(compound: "TB-500"), id: "from-backup", now: takenAt)
        return try #require(source.backupArchiveData().data)
    }

    @Test func aLogThatCantBeOpenedRefusesEveryChangeAndIsNeverWrittenOver() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let id = try savedLog(at: url)
        let saved = try Data(contentsOf: url)
        try lock(url, true)
        defer { try? lock(url, false) }

        let store = PeptideLogStore(persistence: .file(url))
        #expect(store.entries.isEmpty)
        #expect(store.vials.isEmpty)
        #expect(store.storageNote?.contains("couldn't be opened") == true)
        let refusal = try #require(store.changeRefusal)

        // Every change is refused and memory stays as it was.
        #expect(store.log(draft()) == nil)
        #expect(store.persistError == refusal)
        let missingEntry = try #require(PeptideLogStore(persistence: .inMemory).entry(from: draft(), id: id))
        #expect(store.correct(missingEntry, reason: "typo", changes: PeptideCorrectionChanges(draw: 25)) == refusal)
        #expect(store.void(missingEntry, reason: "duplicate") == refusal)
        store.saveVial(PeptideVial(id: "v-new", compound: "TB-500", diluentML: 1))
        store.saveSchedule(PeptideUserSchedule(id: "s-new", compound: "TB-500", frequency: ReconMath.Frequency(type: "daily"), startDate: "2026-10-01"))
        store.setSyringeScale(.u100)
        #expect(store.vials.isEmpty)
        #expect(store.schedules.isEmpty)
        #expect(store.syringeScale == nil)
        let archive = try PeptideArchive.decode(try otherArchive())
        #expect(store.importArchive(archive).total == 0)
        #expect(store.entries.isEmpty)

        // No backup of the empty log, and no restore over the file.
        #expect(store.backupArchiveData().data == nil)
        #expect(store.restoreArchiveData(try otherArchive()) != nil)
        #expect(store.entries.isEmpty)
        // Nothing was set aside or started in its place.
        #expect(files(beside: url) == ["peptide_log_v1.json"])

        try lock(url, false)
        #expect(try Data(contentsOf: url) == saved)
        store.reloadIfNotOpened()
        #expect(store.entries.map(\.id) == [id])
        #expect(store.vial(id: "v-saved") != nil)
        #expect(store.storageNote == nil)
        #expect(store.persistError == nil)
        #expect(store.changeRefusal == nil)
        let second = try #require(store.log(draft(compound: "TB-500"), now: takenAt))
        let reopened = PeptideLogStore(persistence: .file(url))
        #expect(Set(reopened.entries.map(\.id)) == [id, second])
        #expect(reopened.vial(id: "v-saved") != nil)
    }

    @Test func aChangeAfterTheLogBecomesReadableKeepsEveryEarlierRecord() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let id = try savedLog(at: url)
        try lock(url, true)
        let store = PeptideLogStore(persistence: .file(url))
        try lock(url, false)

        // No foreground in between: the change itself reads the log first.
        let second = try #require(store.log(draft(compound: "TB-500"), now: takenAt))
        #expect(Set(store.entries.map(\.id)) == [id, second])
        let reopened = PeptideLogStore(persistence: .file(url))
        #expect(Set(reopened.entries.map(\.id)) == [id, second])
        #expect(reopened.vial(id: "v-saved") != nil)
    }

    @Test func theUserDefaultsCopyIsNotUsedWhileTheFileCantBeOpened() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let (defaults, suite) = try defaultsSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = try savedLog(at: url, defaults: defaults)
        // An older copy, as left by a write that once failed.
        let staleURL = tempURL()
        defer { cleanUp(staleURL) }
        let stale = PeptideLogStore(persistence: .file(staleURL))
        _ = stale.log(draft(compound: "Stale"), id: "stale", now: takenAt)
        let staleBytes = try Data(contentsOf: staleURL)
        defaults.set(staleBytes, forKey: PeptideLogStore.defaultsKey)
        let saved = try Data(contentsOf: url)
        try lock(url, true)
        defer { try? lock(url, false) }

        let store = PeptideLogStore(persistence: .file(url, defaults: defaults))
        #expect(store.entries.isEmpty)
        #expect(store.changeRefusal != nil)
        #expect(store.log(draft()) == nil)
        #expect(defaults.data(forKey: PeptideLogStore.defaultsKey) == staleBytes)

        try lock(url, false)
        #expect(try Data(contentsOf: url) == saved)
        store.reloadIfNotOpened()
        #expect(store.entries.map(\.id) == [id])
    }

    @Test func withNoFileTheUserDefaultsCopyIsStillRead() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let (defaults, suite) = try defaultsSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let sourceURL = tempURL()
        defer { cleanUp(sourceURL) }
        let source = PeptideLogStore(persistence: .file(sourceURL))
        _ = source.log(draft(), id: "kept", now: takenAt)
        defaults.set(try Data(contentsOf: sourceURL), forKey: PeptideLogStore.defaultsKey)

        let store = PeptideLogStore(persistence: .file(url, defaults: defaults))
        #expect(store.entries.map(\.id) == ["kept"])
        #expect(store.changeRefusal == nil)
        #expect(store.storageNote == nil)
        // The next save writes the file and clears the copy.
        _ = store.log(draft(compound: "TB-500"), id: "added", now: takenAt)
        #expect(Set(PeptideLogStore(persistence: .file(url)).entries.map(\.id)) == ["kept", "added"])
        #expect(defaults.data(forKey: PeptideLogStore.defaultsKey) == nil)
    }

    /// A folder on the way to the log that can't be opened hides the file; it
    /// isn't gone. Neither the stale UserDefaults copy nor an empty log may stand in for it.
    @Test func aLogBehindAFolderThatCantBeOpenedIsNotMissing() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let (defaults, suite) = try defaultsSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = try savedLog(at: url, defaults: defaults)
        let saved = try Data(contentsOf: url)
        defaults.set(Data(#"{"version":3,"entries":[],"vials":[],"schedules":[]}"#.utf8), forKey: PeptideLogStore.defaultsKey)
        let folder = url.deletingLastPathComponent().path
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder) }

        guard case .failed = DeviceLogFile(url: url, defaults: nil, defaultsKey: "unused").readFile() else {
            Issue.record("A file behind a folder that can't be opened should read as failed")
            return
        }
        let store = PeptideLogStore(persistence: .file(url, defaults: defaults))
        #expect(store.entries.isEmpty)
        let refusal = try #require(store.changeRefusal)
        #expect(store.log(draft()) == nil)
        #expect(store.persistError == refusal)
        #expect(store.backupArchiveData().data == nil)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder)
        #expect(try Data(contentsOf: url) == saved)
        let second = try #require(store.log(draft(compound: "TB-500"), now: takenAt))
        let reopened = PeptideLogStore(persistence: .file(url))
        #expect(Set(reopened.entries.map(\.id)) == [id, second])
        #expect(reopened.vial(id: "v-saved") != nil)
    }

    @Test func deleteEverythingStillWorksWhileTheLogCantBeOpened() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        _ = try savedLog(at: url)
        try lock(url, true)
        defer { try? lock(url, false) }
        let store = PeptideLogStore(persistence: .file(url))
        #expect(store.changeRefusal != nil)

        store.deleteAll()
        #expect(store.changeRefusal == nil)
        #expect(store.storageNote == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let id = try #require(store.log(draft(), now: takenAt))
        #expect(PeptideLogStore(persistence: .file(url)).entries.map(\.id) == [id])
    }

    // MARK: Bytes that can't be read or kept aside

    /// Opens the log while its folder can't be written to, so nothing can be set aside beside it.
    private func openWithoutCopies(_ url: URL) throws -> PeptideLogStore {
        let directory = url.deletingLastPathComponent().path
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory) }
        return PeptideLogStore(persistence: .file(url))
    }

    private func unreadableCopy(beside url: URL) throws -> Data? {
        guard let name = files(beside: url).first(where: { $0.hasPrefix("peptide_log_v1.unreadable-") }) else { return nil }
        return try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(name))
    }

    @Test func anUnreadableLogThatCantBeSetAsideIsNeverWrittenOver() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let garbage = Data("{not json".utf8)
        try garbage.write(to: url)

        let store = try openWithoutCopies(url)
        #expect(try unreadableCopy(beside: url) == nil)
        #expect(store.storageNote?.contains("copied aside") == true)
        let refusal = try #require(store.changeRefusal)

        // The folder is writable again, but nothing may replace the only copy.
        #expect(store.log(draft()) == nil)
        #expect(store.persistError == refusal)
        store.saveVial(PeptideVial(id: "v-new", compound: "TB-500", diluentML: 1))
        #expect(store.entries.isEmpty && store.vials.isEmpty)
        #expect(store.backupArchiveData().data == nil)
        #expect(store.restoreArchiveData(try otherArchive()) != nil)
        #expect(store.entries.isEmpty)
        #expect(try Data(contentsOf: url) == garbage)
        #expect(files(beside: url) == ["peptide_log_v1.json"])

        // Next launch the copy can be made, so a new log starts and the old bytes are kept.
        let relaunched = PeptideLogStore(persistence: .file(url))
        #expect(try unreadableCopy(beside: url) == garbage)
        #expect(relaunched.changeRefusal == nil)
        let id = try #require(relaunched.log(draft(), now: takenAt))
        #expect(PeptideLogStore(persistence: .file(url)).entries.map(\.id) == [id])
        #expect(try unreadableCopy(beside: url) == garbage)
    }

    /// A version-3 log with one readable dose and one that isn't.
    private func logWithASkippedRecord(at url: URL) throws -> Data {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
        {"version":3,"entries":[
          {"id":"ok","compound":"MT2","dose":250,"units":"mcg","datetime":"2026-09-20T07:15:00-04:00","voided":false,"corrections":[]},
          {"compound":"no id"}
        ],"vials":[],"schedules":[]}
        """
        let data = Data(json.utf8)
        try data.write(to: url)
        return data
    }

    @Test func skippedRecordsThatCantBeSetAsideAreShownButNeverDropped() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let saved = try logWithASkippedRecord(at: url)

        let store = try openWithoutCopies(url)
        #expect(store.entries.map(\.id) == ["ok"])
        #expect(store.storageNote?.contains("copied aside") == true)
        let refusal = try #require(store.changeRefusal)
        #expect(store.log(draft()) == nil)
        #expect(store.persistError == refusal)
        let shown = try #require(store.entry(id: "ok"))
        #expect(store.void(shown, reason: "duplicate") == refusal)
        store.setSyringeScale(.u100)
        #expect(store.entries.map(\.id) == ["ok"])
        #expect(store.entry(id: "ok")?.voided == false)
        #expect(store.syringeScale == nil)
        #expect(store.backupArchiveData().data == nil)
        #expect(try Data(contentsOf: url) == saved)
    }

    @Test func skippedRecordsAreSetAsideBeforeASaveDropsThem() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let saved = try logWithASkippedRecord(at: url)

        let store = PeptideLogStore(persistence: .file(url))
        #expect(try unreadableCopy(beside: url) == saved)
        #expect(store.changeRefusal == nil)
        #expect(store.storageNote?.hasPrefix("1 saved peptide record") == true)
        let id = try #require(store.log(draft(), now: takenAt))
        let reopened = PeptideLogStore(persistence: .file(url))
        #expect(Set(reopened.entries.map(\.id)) == ["ok", id])
        #expect(reopened.storageNote == store.storageNote)
        #expect(try unreadableCopy(beside: url) == saved)
    }

    /// Version-3 logs whose lists are there but aren't lists. Each keeps the
    /// one readable dose.
    private func logsWithAMalformedList() -> [Data] {
        let dose = #"{"id":"ok","compound":"MT2","dose":250,"units":"mcg","datetime":"2026-09-20T07:15:00-04:00","voided":false,"corrections":[]}"#
        return [
            #"{"version":3,"entries":[\#(dose)],"vials":{"id":"v1"},"schedules":[]}"#,
            #"{"version":3,"entries":[\#(dose)],"vials":[],"schedules":"weekly"}"#,
            #"{"version":3,"entries":[\#(dose)],"vials":[],"schedules":[],"held_aside":[1]}"#,
            #"{"version":3,"entries":[\#(dose)],"vials":[],"schedules":[],"held_aside":{"entries":{"id":"held"}}}"#,
        ].map { Data($0.utf8) }
    }

    @Test func aListThatIsntAListIsSetAsideBeforeASaveDropsIt() throws {
        for saved in logsWithAMalformedList() {
            let url = tempURL()
            defer { cleanUp(url) }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try saved.write(to: url)

            let store = PeptideLogStore(persistence: .file(url))
            #expect(store.entries.map(\.id) == ["ok"])
            #expect(try unreadableCopy(beside: url) == saved)
            #expect(store.changeRefusal == nil)
            _ = try #require(store.log(draft(), now: takenAt))
            #expect(try unreadableCopy(beside: url) == saved)
        }
    }

    @Test func aListThatIsntAListAndCantBeSetAsideIsNeverWrittenOver() throws {
        for saved in logsWithAMalformedList() {
            let url = tempURL()
            defer { cleanUp(url) }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try saved.write(to: url)

            let store = try openWithoutCopies(url)
            #expect(store.entries.map(\.id) == ["ok"])
            let refusal = try #require(store.changeRefusal)
            #expect(store.log(draft()) == nil)
            #expect(store.persistError == refusal)
            #expect(store.backupArchiveData().data == nil)
            #expect(try Data(contentsOf: url) == saved)
        }
    }

    /// Lists that aren't saved (an empty held-aside set, older saves) read as empty, and nothing is set aside.
    @Test func absentListsAreEmptyAndNothingIsSetAside() throws {
        let dose = #"{"id":"ok","compound":"MT2","dose":250,"units":"mcg","datetime":"2026-09-20T07:15:00-04:00","voided":false,"corrections":[]}"#
        for json in [#"{"version":3,"entries":[\#(dose)]}"#,
                     #"{"version":3,"entries":[\#(dose)],"vials":[],"schedules":[],"held_aside":null}"#,
                     #"{"version":3,"entries":[\#(dose)],"vials":[],"schedules":[],"held_aside":{"vials":[]}}"#] {
            let url = tempURL()
            defer { cleanUp(url) }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(json.utf8).write(to: url)

            let store = PeptideLogStore(persistence: .file(url))
            #expect(store.entries.map(\.id) == ["ok"])
            #expect(store.storageNote == nil)
            #expect(store.changeRefusal == nil)
            #expect(files(beside: url) == ["peptide_log_v1.json"])
        }
    }

    /// The vial and schedule editors stay open on a refused delete: the store
    /// keeps the record and says why (a partly read log whose copy failed still shows them).
    @Test func deletingAShownVialOrScheduleIsRefusedWhileTheLogIsReadOnly() throws {
        let url = tempURL()
        defer { cleanUp(url) }
        let writer = PeptideLogStore(persistence: .file(url))
        writer.saveVial(PeptideVial(id: "v1", compound: "BPC-157", diluentML: 2))
        writer.saveSchedule(PeptideUserSchedule(id: "s1", compound: "BPC-157", frequency: ReconMath.Frequency(type: "daily"), startDate: "2026-10-01"))
        // Plus one dose that can't be read.
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["entries"] = [["compound": "no id"]]
        let saved = try JSONSerialization.data(withJSONObject: object)
        try saved.write(to: url)

        let store = try openWithoutCopies(url)
        #expect(store.vial(id: "v1") != nil)
        #expect(store.schedules.map(\.id) == ["s1"])
        let refusal = try #require(store.changeRefusal)
        store.deleteVial(id: "v1")
        store.deleteSchedule(id: "s1")
        #expect(store.vial(id: "v1") != nil)
        #expect(store.schedules.map(\.id) == ["s1"])
        #expect(store.persistError == refusal)
        #expect(try Data(contentsOf: url) == saved)
    }
}
