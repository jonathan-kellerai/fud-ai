import Foundation
import Testing
@testable import calorietracker

/// Peptides are in the iCloud backup (as one peptides archive) and gone after
/// Delete Everything. Peptide stores use temporary files and a throwaway
/// UserDefaults suite, never the app-group file. Synthetic data only.
@MainActor
struct PeptideBackupAndResetTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("peptide-backup-\(UUID().uuidString)", isDirectory: true)
    }

    private func defaultsSuite() throws -> (UserDefaults, String) {
        let name = "peptide-backup-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    private func filledStore(at url: URL, defaults: UserDefaults? = nil, compound: String = "BPC-157", id: String = "e1") throws -> PeptideLogStore {
        let store = PeptideLogStore(persistence: .file(url, defaults: defaults))
        store.saveVial(PeptideVial(id: "v-" + id, compound: "Glow", diluentML: 2, createdAt: now))
        store.saveSchedule(PeptideUserSchedule(id: "s-" + id, compound: compound, frequency: ReconMath.Frequency(type: "daily"), startDate: "2026-09-01", createdAt: now))
        var draft = PeptideLogDraft.new(compound: compound, now: now)
        draft.drawText = "50"
        draft.drawUnit = .units
        _ = try #require(store.log(draft, id: id, now: now))
        return store
    }

    @Test func backupCarriesPeptidesAndRestoreReplacesThem() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (fromDefaults, fromName) = try defaultsSuite()
        let (toDefaults, toName) = try defaultsSuite()
        defer {
            fromDefaults.removePersistentDomain(forName: fromName)
            toDefaults.removePersistentDomain(forName: toName)
        }
        let source = try filledStore(at: folder.appendingPathComponent("a/peptide_log_v1.json"))
        let values = try CloudBackupService(defaults: fromDefaults, peptides: source).snapshotValues()
        let value = try #require(values[CloudBackupService.peptidesKey])
        #expect(value.t == "d")

        let targetURL = folder.appendingPathComponent("b/peptide_log_v1.json")
        let target = try filledStore(at: targetURL, compound: "MT2", id: "other")
        let service = CloudBackupService(defaults: toDefaults, peptides: target)
        service.applyValues(values)
        #expect(service.errorMessage == nil)
        #expect(target.entries == source.entries)
        #expect(target.vials == source.vials)
        #expect(target.schedules == source.schedules)
        // Saved, so a relaunch sees the restored peptides.
        #expect(PeptideLogStore(persistence: .file(targetURL)).entries == source.entries)
        // The archive is a backup value, never a UserDefaults key.
        #expect(toDefaults.object(forKey: CloudBackupService.peptidesKey) == nil)
    }

    @Test func unchangedPeptidesBackUpToTheSameBytes() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (defaults, name) = try defaultsSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = try filledStore(at: folder.appendingPathComponent("peptide_log_v1.json"))
        let service = CloudBackupService(defaults: defaults, peptides: store)
        let first = try service.snapshotValues()
        let second = try service.snapshotValues()
        #expect(CloudBackupArchive.contentHash(values: first, photos: [:]) == CloudBackupArchive.contentHash(values: second, photos: [:]))
        let encoded = try #require(first[CloudBackupService.peptidesKey]?.d)
        let bytes = try #require(Data(base64Encoded: encoded))
        let archive = try PeptideArchive.decode(bytes)
        #expect(archive.exportedAt == nil)
        #expect(archive.entries == store.entries)
    }

    @Test func badArchiveKeepsThePhonesPeptidesAndSaysSo() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (defaults, name) = try defaultsSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = try filledStore(at: folder.appendingPathComponent("peptide_log_v1.json"))
        let before = store.entries
        let service = CloudBackupService(defaults: defaults, peptides: store)
        service.applyValues([CloudBackupService.peptidesKey: .data(Data(#"{"format":"something-else","format_version":1}"#.utf8))])
        #expect(store.entries == before)
        #expect(service.errorMessage?.contains("kept") == true)

        service.errorMessage = nil
        service.applyValues([CloudBackupService.peptidesKey: CloudBackupValue(t: "d", d: "not base64!")])
        #expect(store.entries == before)
        #expect(service.errorMessage != nil)
    }

    @Test func damagedArchiveNeverReplacesThePhonesPeptides() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (defaults, name) = try defaultsSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let url = folder.appendingPathComponent("peptide_log_v1.json")
        let store = try filledStore(at: url)
        let before = (store.entries, store.vials, store.schedules)
        let saved = try Data(contentsOf: url)
        let service = CloudBackupService(defaults: defaults, peptides: store)
        let damaged = [
            #"{"format":"jl-peptides","format_version":1,"vials":[],"schedules":[],"entries":"bad"}"#,
            #"{"format":"jl-peptides","format_version":1,"vials":[],"schedules":[]}"#,
            #"{"format":"jl-peptides","format_version":1,"vials":[],"schedules":[],"entries":[{"id":"x","compound":"MT2"},{"id":""}]}"#,
        ]
        for json in damaged {
            service.errorMessage = nil
            service.applyValues([CloudBackupService.peptidesKey: .data(Data(json.utf8))])
            #expect(service.errorMessage?.contains("kept") == true)
            #expect(store.entries == before.0)
            #expect(store.vials == before.1)
            #expect(store.schedules == before.2)
            #expect(try Data(contentsOf: url) == saved)
        }
    }

    /// A backup whose `held_aside` can't be read is refused, so the phone keeps
    /// its own records and those it holds aside, on disk and in memory.
    @Test func malformedHeldAsideNeverReplacesThePhonesPeptides() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (defaults, name) = try defaultsSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let url = folder.appendingPathComponent("peptide_log_v1.json")
        let store = try filledStore(at: url)
        let heldJSON = """
        {"format":"jl-peptides","format_version":1,"vials":[],"schedules":[],"entries":[],
         "held_aside":{"vials":[],"schedules":[],"entries":[{"id":"held-e","compound":"MT2","datetime":"2026-09-20T07:15:00-04:00"}]}}
        """
        store.importArchive(try PeptideArchive.decode(Data(heldJSON.utf8)), now: now)
        #expect(store.heldAside.entries.map(\.id) == ["held-e"])
        let before = (store.entries, store.vials, store.schedules, store.heldAside)
        let saved = try Data(contentsOf: url)
        let service = CloudBackupService(defaults: defaults, peptides: store)
        let backup = #"{"format":"jl-peptides","format_version":1,"vials":[],"schedules":[],"entries":[{"id":"other","compound":"MT2","datetime":"2026-09-21T07:00:00-04:00"}]"#
        for bad in [#","held_aside":"bad""#, #","held_aside":{"entries":{}}"#] {
            service.errorMessage = nil
            service.applyValues([CloudBackupService.peptidesKey: .data(Data((backup + bad + "}").utf8))])
            #expect(service.errorMessage?.contains("kept") == true)
            #expect(store.entries == before.0)
            #expect(store.vials == before.1)
            #expect(store.schedules == before.2)
            #expect(store.heldAside == before.3)
            #expect(try Data(contentsOf: url) == saved)
        }
    }

    @Test func restoreThatCantBeSavedKeepsThePhonesPeptides() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (fromDefaults, fromName) = try defaultsSuite()
        let (toDefaults, toName) = try defaultsSuite()
        let (fallback, fallbackName) = try defaultsSuite()
        defer {
            fromDefaults.removePersistentDomain(forName: fromName)
            toDefaults.removePersistentDomain(forName: toName)
            fallback.removePersistentDomain(forName: fallbackName)
        }
        let source = try filledStore(at: folder.appendingPathComponent("a/peptide_log_v1.json"))
        let values = try CloudBackupService(defaults: fromDefaults, peptides: source).snapshotValues()

        // Saved by a newer app: saving is blocked, so nothing may be replaced.
        let blockedURL = folder.appendingPathComponent("b/peptide_log_v1.json")
        try FileManager.default.createDirectory(at: blockedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let newer = Data(#"{"version":7,"entries":[]}"#.utf8)
        try newer.write(to: blockedURL)
        let blocked = PeptideLogStore(persistence: .file(blockedURL))
        let blockedService = CloudBackupService(defaults: toDefaults, peptides: blocked)
        blockedService.applyValues(values)
        #expect(blockedService.errorMessage?.contains("kept") == true)
        #expect(blocked.entries.isEmpty && blocked.vials.isEmpty && blocked.schedules.isEmpty)
        #expect(try Data(contentsOf: blockedURL) == newer)

        // The file can't be written (a folder now sits at its path): memory
        // and the UserDefaults fallback keep what the phone had, so a
        // relaunch sees it too.
        let failingURL = folder.appendingPathComponent("c/peptide_log_v1.json")
        let failing = try filledStore(at: failingURL, defaults: fallback, compound: "MT2", id: "other")
        let before = (failing.entries, failing.vials, failing.schedules)
        try FileManager.default.removeItem(at: failingURL)
        try FileManager.default.createDirectory(at: failingURL, withIntermediateDirectories: false)
        // A normal save while the file can't be written keeps the phone's
        // records in the fallback.
        failing.deleteVial(id: "no-such-vial")
        let fallbackBytes = try #require(fallback.data(forKey: PeptideLogStore.defaultsKey))
        let failingService = CloudBackupService(defaults: toDefaults, peptides: failing)
        failingService.applyValues(values)
        #expect(failingService.errorMessage?.contains("kept") == true)
        #expect(failing.entries == before.0)
        #expect(failing.vials == before.1)
        #expect(failing.schedules == before.2)
        #expect(failing.entries != source.entries)
        #expect(fallback.data(forKey: PeptideLogStore.defaultsKey) == fallbackBytes)
        let reopened = PeptideLogStore(persistence: .file(failingURL, defaults: fallback))
        #expect(reopened.entries == before.0)
        #expect(reopened.vials == before.1)
        #expect(reopened.schedules == before.2)
    }

    /// Makes a saved log unreadable (as file protection does before first unlock) or readable again.
    private func lock(_ url: URL, _ locked: Bool) throws {
        try FileManager.default.setAttributes([.posixPermissions: locked ? 0o000 : 0o644], ofItemAtPath: url.path)
    }

    /// While the peptide log is read-only nothing is uploaded, so the last
    /// iCloud backup keeps its peptides: a log that can't be opened, and one
    /// a newer app saved (which used to back up as an empty archive).
    @Test func aReadOnlyPeptideLogSkipsTheWholeBackup() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (defaults, name) = try defaultsSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let lockedURL = folder.appendingPathComponent("a/peptide_log_v1.json")
        _ = try filledStore(at: lockedURL)
        try lock(lockedURL, true)
        defer { try? lock(lockedURL, false) }
        let locked = PeptideLogStore(persistence: .file(lockedURL))
        let newerURL = folder.appendingPathComponent("b/peptide_log_v1.json")
        try FileManager.default.createDirectory(at: newerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version":7,"entries":[]}"#.utf8).write(to: newerURL)
        let newer = PeptideLogStore(persistence: .file(newerURL))

        for (store, reason) in [(locked, "Peptides couldn't be read on this phone"),
                                (newer, "Peptides were saved by a newer version of the app")] {
            #expect(store.backupArchiveData() == .blocked(reason: reason))
            let service = CloudBackupService(defaults: defaults, peptides: store)
            #expect(throws: CloudBackupError.backupSkipped(reason)) { try service.snapshotValues() }
        }
        #expect(CloudBackupError.backupSkipped("Peptides couldn't be read on this phone").localizedDescription
            == "Peptides couldn't be read on this phone, so iCloud backup was skipped to keep your last backup.")
    }

    /// A backup with peptides isn't restored over a log that can't be opened:
    /// nothing changes, settings and diary included, so the phone isn't left half restored.
    @Test func restoreOverAPeptideLogThatCantBeOpenedChangesNothing() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (fromDefaults, fromName) = try defaultsSuite()
        let (toDefaults, toName) = try defaultsSuite()
        defer {
            fromDefaults.removePersistentDomain(forName: fromName)
            toDefaults.removePersistentDomain(forName: toName)
        }
        let source = try filledStore(at: folder.appendingPathComponent("a/peptide_log_v1.json"))
        fromDefaults.set(true, forKey: "weekStartsOnMonday")
        let values = try CloudBackupService(defaults: fromDefaults, peptides: source).snapshotValues()
        toDefaults.set("lbs", forKey: "weightUnit")

        let targetURL = folder.appendingPathComponent("b/peptide_log_v1.json")
        _ = try filledStore(at: targetURL, compound: "MT2", id: "other")
        let saved = try Data(contentsOf: targetURL)
        try lock(targetURL, true)
        defer { try? lock(targetURL, false) }
        let target = PeptideLogStore(persistence: .file(targetURL))
        let service = CloudBackupService(defaults: toDefaults, peptides: target)

        #expect(!service.applyValues(values))
        #expect(service.errorMessage == "Peptides couldn't be read on this phone, so nothing was restored and everything on this phone was kept.")
        #expect(toDefaults.string(forKey: "weightUnit") == "lbs")
        #expect(toDefaults.object(forKey: "weekStartsOnMonday") == nil)
        #expect(toDefaults.object(forKey: CloudBackupService.enabledKey) == nil)
        try lock(targetURL, false)
        #expect(try Data(contentsOf: targetURL) == saved)

        // A backup without peptides (older builds) still restores; the log is left alone.
        try lock(targetURL, true)
        service.errorMessage = nil
        #expect(service.applyValues(["weekStartsOnMonday": .bool(true)]))
        #expect(service.errorMessage == nil)
        #expect(toDefaults.bool(forKey: "weekStartsOnMonday"))

        // Once the log opens, the backup restores over it.
        try lock(targetURL, false)
        #expect(service.applyValues(values))
        #expect(service.errorMessage == nil)
        #expect(target.entries == source.entries)
    }

    @Test func olderBackupWithoutPeptidesLeavesThemUntouched() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (defaults, name) = try defaultsSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = try filledStore(at: folder.appendingPathComponent("peptide_log_v1.json"))
        let before = (store.entries, store.vials, store.schedules)
        let service = CloudBackupService(defaults: defaults, peptides: store)
        service.applyValues(["weekStartsOnMonday": .bool(true)])
        #expect(store.entries == before.0)
        #expect(store.vials == before.1)
        #expect(store.schedules == before.2)
        #expect(service.errorMessage == nil)
    }

    @Test func deleteAllLeavesAnEmptyFreshStore() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (defaults, name) = try defaultsSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let url = folder.appendingPathComponent("peptide_log_v1.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A version-1 log migrates and leaves its untouched copy next to the file.
        let version1 = #"{"version":1,"rows":[{"id":"r1","datetime":"2026-09-20T07:30:00-04:00","compound":"BPC-157","status":"COMPLETED","recorded_via":"app"}],"pendingOps":[],"meta":[],"vials":[],"schedules":[]}"#
        try Data(version1.utf8).write(to: url)
        try Data("unrelated".utf8).write(to: folder.appendingPathComponent("keep-me.txt"))
        let store = PeptideLogStore(persistence: .file(url, defaults: defaults))
        #expect(store.entries.count == 1)
        defaults.set(Data("fallback".utf8), forKey: PeptideLogStore.defaultsKey)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.contains { $0.hasPrefix("peptide_log_v1.pre-local-") })

        store.deleteAll()
        #expect(store.entries.isEmpty && store.vials.isEmpty && store.schedules.isEmpty)
        #expect(store.persistError == nil && store.storageNote == nil)
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(left == ["keep-me.txt"])
        #expect(defaults.data(forKey: PeptideLogStore.defaultsKey) == nil)
        let fresh = PeptideLogStore(persistence: .file(url, defaults: defaults))
        #expect(fresh.entries.isEmpty && fresh.vials.isEmpty && fresh.schedules.isEmpty)
        #expect(fresh.storageNote == nil)
    }

    /// Recon Bench (folded into Reconstitute in build 68) left a save in the
    /// app group and standard defaults. Its mixes move into Vials at launch
    /// (ReconBenchMigrationTests); Delete Everything still removes whatever is
    /// left. Whatever was there before the test is put back.
    @Test func reconBenchDataIsWiped() throws {
        let savedDefaults = UserDefaults.standard.data(forKey: ReconBenchStore.defaultsKey)
        let savedFile = ReconBenchStore.fileURL.flatMap { try? Data(contentsOf: $0) }
        defer {
            if let savedDefaults {
                UserDefaults.standard.set(savedDefaults, forKey: ReconBenchStore.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: ReconBenchStore.defaultsKey)
            }
            if let savedFile, let url = ReconBenchStore.fileURL {
                try? savedFile.write(to: url, options: .atomic)
            }
        }
        let old = Data(#"{"cards":{},"entries":[],"taken":{}}"#.utf8)
        UserDefaults.standard.set(old, forKey: ReconBenchStore.defaultsKey)
        if let url = ReconBenchStore.fileURL {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try old.write(to: url, options: .atomic)
        }
        #expect(UserDefaults.standard.data(forKey: ReconBenchStore.defaultsKey) != nil)

        ReconBenchStore.deleteSavedData()
        #expect(UserDefaults.standard.data(forKey: ReconBenchStore.defaultsKey) == nil)
        if let url = ReconBenchStore.fileURL {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }
}
