import Foundation
import Testing
@testable import calorietracker

/// One person per phone. Build 67 saved every record with one of two profile
/// tags (version 2). The first profile's records, and untagged ones, become
/// the user's own. The second profile's are never dropped: they're held aside,
/// on disk and in the backup, until the user picks "Keep them in my log" or
/// "Delete them" once. Real files in a temp directory; synthetic data only.
@MainActor
struct PeptideSecondProfileTests {
    /// Build 67's raw profile tags, as its saves carry them.
    private let firstTag = PeptideLegacyProfile.firstProfileRawValue
    private let secondTag = PeptideLegacyProfile.secondProfileRawValue

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("peptide-second-profile-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("peptide_log_v1.json")
    }

    /// A version-2 save: the first profile's dose, vial and schedule, one
    /// untagged dose, and the second profile's dose (linked to its vial),
    /// vial and schedule.
    private var version2: String {
        """
        {"version":2,
         "entries":[
          {"id":"own-1","person":"\(firstTag)","compound":"BPC-157","dose":500,"units":"mcg",
           "datetime":"2026-09-20T07:30:00-04:00","voided":false,"corrections":[],"vial_id":"own-vial"},
          {"id":"own-2","compound":"Tesamorelin","dose":1.4,"units":"mg",
           "datetime":"2026-09-20T21:30:00-04:00","voided":false,"corrections":[]},
          {"id":"second-1","person":"\(secondTag)","compound":"MT2","dose":250,"units":"mcg",
           "datetime":"2026-09-20T07:15:00-04:00","voided":false,"corrections":[],"vial_id":"second-vial",
           "drawn_volume":10,"drawn_unit":"units"}
         ],
         "vials":[
          {"id":"own-vial","person":"\(firstTag)","compound":"BPC-157","isBlend":false,"components":[],
           "concentrationConfirmed":false,"status":"active","notes":"","createdAt":800000000},
          {"id":"second-vial","person":"\(secondTag)","compound":"Glow","isBlend":true,"components":[],
           "concentrationConfirmed":false,"status":"active","notes":"Fridge","createdAt":800000000}
         ],
         "schedules":[
          {"id":"own-sched","person":"\(firstTag)","compound":"BPC-157","frequency":{"type":"daily","days":[]},
           "startDate":"2026-09-01","active":true,"notes":"","createdAt":800000000},
          {"id":"second-sched","person":"\(secondTag)","compound":"MT2","frequency":{"type":"daily","days":[]},
           "startDate":"2026-09-01","active":true,"notes":"","createdAt":800000000}
         ]}
        """
    }

    private func writeVersion2() throws -> URL {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(version2.utf8).write(to: url)
        return url
    }

    private func copies(next url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? [])
            .filter { $0.hasPrefix("peptide_log_v1.pre-v3-") }
    }

    @Test func firstProfileRecordsBecomeTheUsersOwn() throws {
        let url = try writeVersion2()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PeptideLogStore(persistence: .file(url))
        #expect(store.entries.map(\.id) == ["own-1", "own-2"])
        #expect(store.vials.map(\.id) == ["own-vial"])
        #expect(store.schedules.map(\.id) == ["own-sched"])
        #expect(store.entry(id: "own-1")?.vialID == "own-vial")
        #expect(store.entry(id: "own-1")?.dose == 500)
        // Saved as version 3, with no profile tag on anything.
        let saved = try Data(contentsOf: url)
        #expect(PeptideLogSnapshot.savedVersion(of: saved) == PeptideLogStore.fileVersion)
        #expect(!String(decoding: saved, as: UTF8.self).contains("\"person\""))
    }

    @Test func nothingIsLostBeforeTheChoice() throws {
        let url = try writeVersion2()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PeptideLogStore(persistence: .file(url))
        // Not in the log, the Week grid or Home...
        #expect(store.entry(id: "second-1") == nil)
        #expect(store.vial(id: "second-vial") == nil)
        #expect(!store.schedules.contains { $0.id == "second-sched" })
        // ...but held, whole, waiting for the choice.
        #expect(store.heldAsideCount == 3)
        let held = try #require(store.heldAside.entries.first)
        #expect(held.id == "second-1")
        #expect(held.dose == 250)
        #expect(held.vialID == "second-vial")
        #expect(held.drawnVolume == 10)
        #expect(store.heldAside.vials.first?.notes == "Fridge")
        #expect(store.heldAside.schedules.map(\.id) == ["second-sched"])

        // On disk: the untouched version-2 bytes are set aside, and the
        // version-3 save keeps the records under held_aside.
        let names = copies(next: url)
        #expect(names.count == 1)
        let copy = try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(try #require(names.first)))
        #expect(copy == Data(version2.utf8))
        let snapshot = try JSONDecoder().decode(PeptideLogSnapshot.self, from: Data(contentsOf: url))
        #expect(snapshot.heldAside == store.heldAside)

        // In the backup and the export too.
        let archive = try PeptideArchive.decode(try #require(store.backupArchiveData()), complete: true)
        #expect(archive.heldAside.entries.map(\.id) == ["second-1"])
        #expect(archive.heldAside.vials.map(\.id) == ["second-vial"])
        #expect(archive.heldAside.schedules.map(\.id) == ["second-sched"])
    }

    @Test func keepPutsThemInTheLogOnceAndForAll() throws {
        let url = try writeVersion2()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PeptideLogStore(persistence: .file(url))
        store.keepHeldAside()
        #expect(store.heldAsideCount == 0)
        #expect(store.entries.map(\.id) == ["second-1", "own-1", "own-2"])
        #expect(store.entry(id: "second-1")?.vialID == "second-vial")
        #expect(Set(store.vials.map(\.id)) == ["own-vial", "second-vial"])
        #expect(Set(store.schedules.map(\.id)) == ["own-sched", "second-sched"])

        // The choice is saved: a relaunch asks nothing and shows the same log.
        let relaunched = PeptideLogStore(persistence: .file(url))
        #expect(relaunched.heldAsideCount == 0)
        #expect(relaunched.entries == store.entries)
        #expect(relaunched.vials == store.vials)
        #expect(relaunched.schedules == store.schedules)
        #expect(!String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("held_aside"))
    }

    @Test func deleteRemovesThemOnceAndForAll() throws {
        let url = try writeVersion2()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PeptideLogStore(persistence: .file(url))
        store.deleteHeldAside()
        #expect(store.heldAsideCount == 0)
        #expect(store.entries.map(\.id) == ["own-1", "own-2"])
        #expect(store.vial(id: "second-vial") == nil)

        let relaunched = PeptideLogStore(persistence: .file(url))
        #expect(relaunched.heldAsideCount == 0)
        #expect(relaunched.entries.map(\.id) == ["own-1", "own-2"])
        #expect(relaunched.vials.map(\.id) == ["own-vial"])
        #expect(relaunched.schedules.map(\.id) == ["own-sched"])
        // Asking again changes nothing.
        relaunched.keepHeldAside()
        relaunched.deleteHeldAside()
        #expect(relaunched.entries.map(\.id) == ["own-1", "own-2"])
    }

    @Test func relaunchingBeforeChoosingChangesNothing() throws {
        let url = try writeVersion2()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = PeptideLogStore(persistence: .file(url))
        let savedOnce = try Data(contentsOf: url)
        let second = PeptideLogStore(persistence: .file(url))
        let third = PeptideLogStore(persistence: .file(url))
        #expect(second.entries == first.entries)
        #expect(second.vials == first.vials)
        #expect(second.schedules == first.schedules)
        #expect(second.heldAside == first.heldAside)
        #expect(third.heldAside == first.heldAside)
        #expect(third.heldAsideCount == 3)
        // Launches without a change don't rewrite the save or copy it again.
        #expect(try Data(contentsOf: url) == savedOnce)
        #expect(copies(next: url).count == 1)
    }

    @Test func newRecordsCarryNoProfile() throws {
        let url = try writeVersion2()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PeptideLogStore(persistence: .file(url))
        store.saveVial(PeptideVial(id: "new-vial", compound: "TB-500"))
        store.saveSchedule(PeptideUserSchedule(id: "new-sched", compound: "TB-500", frequency: ReconMath.Frequency(type: "daily"), startDate: "2026-10-01"))
        var draft = PeptideLogDraft.new(compound: "TB-500", now: Date(timeIntervalSince1970: 1_790_000_000))
        draft.drawText = "0.2"
        draft.drawUnit = .milliliters
        _ = try #require(store.log(draft, id: "new-entry"))
        let relaunched = PeptideLogStore(persistence: .file(url))
        #expect(relaunched.entry(id: "new-entry") != nil)
        #expect(relaunched.vial(id: "new-vial") != nil)
        #expect(relaunched.heldAsideCount == 3)
        #expect(!String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("\"person\""))
    }

    // MARK: Import

    /// A build 67 export: the first profile's vial and dose, an untagged dose,
    /// the second profile's vial, schedule and dose, and a dose an export
    /// already held aside.
    private var mixedArchive: String {
        """
        {"format":"jl-peptides","format_version":1,
         "vials":[{"id":"imp-own-vial","person":"\(firstTag)","compound":"BPC-157"},
                  {"id":"imp-second-vial","person":"\(secondTag)","compound":"Glow","notes":"Fridge"}],
         "schedules":[{"id":"imp-second-sched","person":"\(secondTag)","compound":"MT2",
                       "frequency":{"type":"daily","days":[]},"start_date":"2026-09-01"}],
         "entries":[{"id":"imp-own-1","person":"\(firstTag)","compound":"BPC-157","dose":500,"units":"mcg",
                     "datetime":"2026-09-20T07:30:00-04:00"},
                    {"id":"imp-own-2","compound":"Tesamorelin","dose":1.4,"units":"mg",
                     "datetime":"2026-09-20T21:30:00-04:00"},
                    {"id":"imp-second-1","person":"\(secondTag)","compound":"MT2","dose":250,"units":"mcg",
                     "vial_id":"imp-second-vial","drawn_volume":10,"drawn_unit":"units",
                     "datetime":"2026-09-20T07:15:00-04:00"}],
         "held_aside":{"vials":[],"schedules":[],
                       "entries":[{"id":"imp-held-1","compound":"MT2","dose":200,"units":"mcg",
                                   "datetime":"2026-09-19T07:15:00-04:00"}]}}
        """
    }

    private func emptyStoreURL() throws -> URL {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }

    private func importMixedArchive(into store: PeptideLogStore) throws -> PeptideImportSummary {
        // A whole-second time: vials without a created_at get it, and the archive keeps seconds.
        store.importArchive(try PeptideArchive.decode(Data(mixedArchive.utf8)), now: Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func importHoldsTheSecondProfileAsideAndLosesNothing() throws {
        let url = try emptyStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PeptideLogStore(persistence: .file(url))
        let preview = store.importSummary(of: try PeptideArchive.decode(Data(mixedArchive.utf8)))
        #expect(preview == PeptideImportSummary(newVials: 1, newEntries: 2, heldAside: 4))
        #expect(try importMixedArchive(into: store) == preview)

        // The user's own records are in the log; nothing from the second profile is.
        #expect(store.entries.map(\.id) == ["imp-own-1", "imp-own-2"])
        #expect(store.vials.map(\.id) == ["imp-own-vial"])
        #expect(store.schedules.isEmpty)
        // The rest is held, whole, for the same one-time choice as an upgrade.
        #expect(store.heldAsideCount == 4)
        #expect(Set(store.heldAside.entries.map(\.id)) == ["imp-second-1", "imp-held-1"])
        let held = try #require(store.heldAside.entries.first { $0.id == "imp-second-1" })
        #expect(held.dose == 250)
        #expect(held.vialID == "imp-second-vial")
        #expect(held.drawnVolume == 10)
        #expect(store.heldAside.vials.first?.notes == "Fridge")
        #expect(store.heldAside.schedules.map(\.id) == ["imp-second-sched"])

        // Saved under held_aside, with no profile tag, and still there after a relaunch.
        let saved = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        #expect(saved.contains("\"held_aside\""))
        #expect(!saved.contains("\"person\""))
        let relaunched = PeptideLogStore(persistence: .file(url))
        #expect(relaunched.heldAside == store.heldAside)
        #expect(relaunched.entries == store.entries)
    }

    @Test func keepingImportedRecordsMergesThemAndIsNotAskedAgain() throws {
        let url = try emptyStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PeptideLogStore(persistence: .file(url))
        _ = try importMixedArchive(into: store)
        store.keepHeldAside()
        #expect(store.heldAsideCount == 0)
        #expect(store.entries.map(\.id) == ["imp-held-1", "imp-second-1", "imp-own-1", "imp-own-2"])
        #expect(Set(store.vials.map(\.id)) == ["imp-own-vial", "imp-second-vial"])
        #expect(store.schedules.map(\.id) == ["imp-second-sched"])

        let relaunched = PeptideLogStore(persistence: .file(url))
        #expect(relaunched.heldAsideCount == 0)
        #expect(relaunched.entries == store.entries)
        // Importing the same file again finds everything here and holds nothing aside.
        let again = try importMixedArchive(into: relaunched)
        #expect(again.total == 0)
        #expect(again.alreadyHere == 7)
        #expect(relaunched.heldAsideCount == 0)
    }

    @Test func deletingImportedRecordsRemovesThemAndIsNotAskedAgain() throws {
        let url = try emptyStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PeptideLogStore(persistence: .file(url))
        _ = try importMixedArchive(into: store)
        store.deleteHeldAside()
        #expect(store.heldAsideCount == 0)
        #expect(store.entries.map(\.id) == ["imp-own-1", "imp-own-2"])
        #expect(store.vial(id: "imp-second-vial") == nil)

        let relaunched = PeptideLogStore(persistence: .file(url))
        #expect(relaunched.heldAsideCount == 0)
        #expect(relaunched.entries.map(\.id) == ["imp-own-1", "imp-own-2"])
        #expect(relaunched.vials.map(\.id) == ["imp-own-vial"])
        #expect(relaunched.schedules.isEmpty)
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        #expect(!text.contains("imp-second"))
        #expect(!text.contains("held_aside"))
    }

    @Test func importingTheSameFileTwiceHoldsNothingTwice() throws {
        let url = try emptyStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PeptideLogStore(persistence: .file(url))
        _ = try importMixedArchive(into: store)
        let savedOnce = try Data(contentsOf: url)
        let again = try importMixedArchive(into: store)
        #expect(again.total == 0)
        #expect(again.alreadyHere == 7)
        #expect(store.heldAsideCount == 4)
        #expect(store.entries.count == 2)
        #expect(try Data(contentsOf: url) == savedOnce)
    }

    /// Records an upgrade already held aside aren't held a second time when an
    /// export of the same profile is imported.
    @Test func importSkipsRecordsAlreadyHeldAsideByTheUpgrade() throws {
        let url = try writeVersion2()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PeptideLogStore(persistence: .file(url))
        let held = store.heldAside
        let file = try PeptideArchive.decode(try #require(store.backupArchiveData()))
        let fresh = PeptideLogStore(persistence: .inMemory)
        _ = fresh.importArchive(file)
        #expect(fresh.heldAside == held)
        let summary = store.importArchive(file)
        #expect(summary.total == 0)
        #expect(store.heldAside == held)
        #expect(store.heldAsideCount == 3)
    }

    @Test func importedHeldRecordsSurviveABackupAndRestore() throws {
        let url = try emptyStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PeptideLogStore(persistence: .file(url))
        _ = try importMixedArchive(into: store)
        let backup = try #require(store.backupArchiveData())

        let otherURL = try emptyStoreURL()
        defer { try? FileManager.default.removeItem(at: otherURL.deletingLastPathComponent()) }
        let restored = PeptideLogStore(persistence: .file(otherURL))
        #expect(restored.restoreArchiveData(backup) == nil)
        #expect(restored.heldAside == store.heldAside)
        #expect(restored.entries == store.entries)
        #expect(restored.vials == store.vials)
        let relaunched = PeptideLogStore(persistence: .file(otherURL))
        #expect(relaunched.heldAside == store.heldAside)
        #expect(relaunched.heldAsideCount == 4)
        // The restored phone gets the same one-time choice.
        relaunched.keepHeldAside()
        #expect(Set(relaunched.entries.map(\.id)) == ["imp-own-1", "imp-own-2", "imp-second-1", "imp-held-1"])
    }

    @Test func legacyTagsAreReadOnlyThroughTheProfile() {
        #expect(PeptideLegacyProfile(raw: nil) == .own)
        #expect(PeptideLegacyProfile(raw: "") == .own)
        #expect(PeptideLegacyProfile(raw: firstTag) == .own)
        #expect(PeptideLegacyProfile(raw: " \(firstTag.uppercased()) ") == .own)
        #expect(PeptideLegacyProfile(raw: secondTag) == .second)
        #expect(PeptideLegacyProfile(raw: secondTag.capitalized) == .second)
    }
}
