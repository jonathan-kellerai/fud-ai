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

    @Test func legacyTagsAreReadOnlyThroughTheProfile() {
        #expect(PeptideLegacyProfile(raw: nil) == .own)
        #expect(PeptideLegacyProfile(raw: "") == .own)
        #expect(PeptideLegacyProfile(raw: firstTag) == .own)
        #expect(PeptideLegacyProfile(raw: " \(firstTag.uppercased()) ") == .own)
        #expect(PeptideLegacyProfile(raw: secondTag) == .second)
        #expect(PeptideLegacyProfile(raw: secondTag.capitalized) == .second)
    }
}
