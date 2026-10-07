import Foundation
import Testing
@testable import calorietracker

/// The peptide archive: one JSON format for export, import and the iCloud
/// backup. Import adds by id only when absent, never parses amounts out of
/// notes, never asks for a person, and refuses files that aren't this app's.
/// Synthetic data only.
@MainActor
struct PeptideArchiveTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    /// Build 67's raw profile tags, as old files carry them.
    private let firstTag = PeptideLegacyProfile.firstProfileRawValue
    private let secondTag = PeptideLegacyProfile.secondProfileRawValue

    private func filledStore() throws -> PeptideLogStore {
        let store = PeptideLogStore(persistence: .inMemory)
        store.saveVial(PeptideVial(
            id: "v1",
            compound: "Glow",
            isBlend: true,
            components: [
                PeptideVialComponent(id: "c1", name: "GHK-Cu", amount: 50, unit: "mg"),
                PeptideVialComponent(id: "c2", name: "BPC-157", amount: 10, unit: "mg"),
            ],
            diluentML: 2,
            mixedOn: "2026-09-10",
            concentrationConfirmed: true,
            lowStockThresholdML: 0.4,
            notes: "Fridge door",
            createdAt: now
        ))
        store.saveSchedule(PeptideUserSchedule(
            id: "s1", compound: "BPC-157", amount: 500, units: "mcg",
            frequency: ReconMath.Frequency(type: "weekdays", days: [1, 3, 5]), startDate: "2026-09-01",
            endDate: "2026-12-01", timeOfDay: 450, active: true, notes: "AM", createdAt: now
        ))
        var draft = PeptideLogDraft.new(compound: "Glow", now: now)
        draft.amountText = "10"
        draft.units = "units"
        draft.vialID = "v1"
        draft.site = "Thigh R"
        let id = try #require(store.log(draft, id: "e1", now: now))
        _ = store.correct(try #require(store.entry(id: id)), reason: "Typo", changes: PeptideCorrectionChanges(dose: 12), now: now)
        var next = PeptideLogDraft.new(compound: "BPC-157", now: now.addingTimeInterval(60))
        next.amountText = "500"
        next.units = "mcg"
        let other = try #require(store.log(next, id: "e2", now: now))
        _ = store.void(try #require(store.entry(id: other)), reason: "Twice", now: now)
        return store
    }

    @Test func exportThenImportRoundTrips() throws {
        let store = try filledStore()
        let data = try store.archive(exportedAt: now).encoded()
        let archive = try PeptideArchive.decode(data)
        #expect(archive.exportedAt == PeptideMath.iso8601NewYork(now))
        #expect(archive.skipped == 0)

        let restored = PeptideLogStore(persistence: .inMemory)
        let summary = restored.importArchive(archive, now: now)
        #expect(summary == PeptideImportSummary(newVials: 1, newSchedules: 1, newEntries: 2))
        #expect(restored.vials == store.vials)
        #expect(restored.schedules == store.schedules)
        #expect(restored.entries == store.entries)
        #expect(restored.entry(id: "e1")?.corrections.count == 1)
        #expect(restored.entry(id: "e2")?.voided == true)
    }

    @Test func encodingIsStableAndSnakeCase() throws {
        let store = try filledStore()
        let first = try store.archive(exportedAt: now).encoded()
        let second = try store.archive(exportedAt: now).encoded()
        #expect(first == second)
        let text = String(decoding: first, as: UTF8.self)
        for key in ["\"format\" : \"jl-peptides\"", "\"format_version\" : 1", "\"exported_at\"", "\"diluent_ml\"",
                    "\"concentration_confirmed\"", "\"start_date\"", "\"vial_id\"", "\"void_reason\""] {
            #expect(text.contains(key), "\(key)")
        }
    }

    @Test func importingTwiceAddsNothing() throws {
        let archive = try PeptideArchive.decode(try filledStore().archive(exportedAt: now).encoded())
        let store = PeptideLogStore(persistence: .inMemory)
        _ = store.importArchive(archive)
        let again = store.importSummary(of: archive)
        #expect(again.added == 0)
        #expect(again.alreadyHere == 4)
        let applied = store.importArchive(archive)
        #expect(applied.added == 0)
        #expect(store.vials.count == 1)
        #expect(store.entries.count == 2)
    }

    @Test func existingRecordsAreNeverChanged() throws {
        let store = try filledStore()
        let json = """
        {"format":"jl-peptides","format_version":1,"vials":[
          {"id":"v1","person":"\(firstTag)","compound":"Changed","notes":"other"},
          {"id":"v2","compound":"MT2"},
          {"id":"v2","compound":"MT2 duplicate"}
        ],"schedules":[],"entries":[]}
        """
        let archive = try PeptideArchive.decode(Data(json.utf8))
        let preview = store.importSummary(of: archive)
        #expect(preview.newVials == 1)
        #expect(preview.alreadyHere == 2)
        store.importArchive(archive)
        #expect(store.vial(id: "v1")?.compound == "Glow")
        #expect(store.vial(id: "v2")?.compound == "MT2")
    }

    /// The shape the one-time import file uses for records kept elsewhere:
    /// no owner, labeled facts in notes, no amounts the app could calculate from.
    /// Every vial goes into this phone's log; nobody is asked who it belongs to.
    @Test func vialsImportIntoTheLogWithNotesVerbatim() throws {
        let notes = "labeled_amount: 10 mg\nconcentration: 5 mg/mL\nsource: SYNTHETIC-TEST\nuncertainties: [\"label faded\"]"
        let json = """
        {"format":"jl-peptides","format_version":1,"exported_at":"2026-10-06T12:00:00-04:00",
         "vials":[{"id":"INV-SYNTH-001","person":null,"compound":"Synthetic-1","is_blend":false,"components":[],
                   "diluent_ml":null,"mixed_on":"2026-09-22","concentration_confirmed":false,"status":"active",
                   "notes":\(String(decoding: try JSONEncoder().encode(notes), as: UTF8.self)),"created_at":"2026-09-22T00:00:00Z"},
                  {"id":"INV-SYNTH-002","compound":"Synthetic-2","mixed_on":"09/22/2026","status":"finished"},
                  {"id":"INV-SYNTH-003","compound":"Synthetic-3","person":"\(secondTag.capitalized)","status":"unknown"}],
         "schedules":[],"entries":[]}
        """
        let archive = try PeptideArchive.decode(Data(json.utf8))
        let store = PeptideLogStore(persistence: .inMemory)
        #expect(store.importSummary(of: archive).newVials == 3)
        store.importArchive(archive, now: now)

        let synthetic = try #require(store.vial(id: "INV-SYNTH-001"))
        #expect(synthetic.notes == notes)
        #expect(synthetic.components.isEmpty)
        #expect(synthetic.diluentML == nil)
        #expect(!synthetic.concentrationConfirmed)
        #expect(synthetic.mixedOn == "2026-09-22")
        #expect(synthetic.status == .active)
        #expect(!store.remaining(for: synthetic).calculable)

        let second = try #require(store.vial(id: "INV-SYNTH-002"))
        #expect(second.mixedOn == nil)
        #expect(second.status == .finished)
        #expect(second.createdAt == now)
        #expect(store.vial(id: "INV-SYNTH-003")?.status == .active)
        #expect(store.heldAsideCount == 0)
    }

    /// A build 67 export tagged every record with a profile. Importing it
    /// adds them all to this phone's log, without asking for a person.
    @Test func oldArchiveWithPeopleImportsEverythingIntoTheLog() throws {
        let json = """
        {"format":"jl-peptides","format_version":1,
         "vials":[{"id":"va","person":"\(firstTag)","compound":"BPC-157"},{"id":"vb","person":"\(secondTag)","compound":"MT2"}],
         "schedules":[{"id":"sb","person":"\(secondTag)","compound":"MT2","frequency":{"type":"daily","days":[]},"start_date":"2026-09-01"}],
         "entries":[{"id":"ea","person":"\(firstTag)","compound":"BPC-157","dose":500,"units":"mcg","datetime":"2026-09-20T07:00:00-04:00"},
                    {"id":"eb","person":"\(secondTag)","compound":"MT2","dose":250,"units":"mcg","datetime":"2026-09-20T07:15:00-04:00"}]}
        """
        let archive = try PeptideArchive.decode(Data(json.utf8))
        let store = PeptideLogStore(persistence: .inMemory)
        #expect(store.importSummary(of: archive) == PeptideImportSummary(newVials: 2, newSchedules: 1, newEntries: 2))
        store.importArchive(archive, now: now)
        #expect(Set(store.vials.map(\.id)) == ["va", "vb"])
        #expect(store.schedules.map(\.id) == ["sb"])
        #expect(store.entries.map(\.id) == ["ea", "eb"])
        #expect(store.heldAsideCount == 0)
    }

    /// Records still held aside travel in `held_aside`, so a backup or export
    /// made before the user chooses loses nothing, and a restore keeps them aside.
    @Test func heldAsideRecordsRoundTripAndARestoreKeepsThemAside() throws {
        let json = """
        {"format":"jl-peptides","format_version":1,
         "vials":[{"id":"own-v","compound":"BPC-157"}],
         "schedules":[],
         "entries":[{"id":"own-e","compound":"BPC-157","datetime":"2026-09-20T07:00:00-04:00"},
                    {"id":"old-e","person":"\(secondTag)","compound":"MT2","dose":250,"units":"mcg","datetime":"2026-09-20T07:15:00-04:00"}]}
        """
        let backup = try PeptideArchive.decode(Data(json.utf8), complete: true)
        #expect(backup.entries.map(\.id) == ["own-e"])
        #expect(backup.heldAside.entries.map(\.id) == ["old-e"])

        let store = PeptideLogStore(persistence: .inMemory)
        #expect(store.replaceAll(with: backup, now: now) == nil)
        #expect(store.entries.map(\.id) == ["own-e"])
        #expect(store.heldAside.entries.map(\.id) == ["old-e"])

        let exported = try store.archive(exportedAt: nil).encoded()
        let text = String(decoding: exported, as: UTF8.self)
        #expect(text.contains("\"held_aside\""))
        #expect(!text.contains("\"person\""))
        let again = PeptideLogStore(persistence: .inMemory)
        #expect(again.replaceAll(with: try PeptideArchive.decode(exported, complete: true), now: now) == nil)
        #expect(again.entries == store.entries)
        #expect(again.vials == store.vials)
        #expect(again.heldAside == store.heldAside)
    }

    @Test func unreadableRecordsAreSkippedAndCounted() throws {
        let json = """
        {"format":"jl-peptides","format_version":1,
         "vials":[{"compound":"no id"},{"id":"ok","compound":"MT2"}],
         "schedules":[{"id":"s","compound":"MT2","frequency":{"type":"daily","days":[]},"start_date":"someday"}],
         "entries":[{"id":"e","compound":"MT2","datetime":"2026-09-20T07:00:00-04:00"},{"id":""}]}
        """
        let archive = try PeptideArchive.decode(Data(json.utf8))
        #expect(archive.vials.map(\.id) == ["ok"])
        #expect(archive.schedules.isEmpty)
        #expect(archive.entries.map(\.id) == ["e"])
        #expect(archive.skipped == 3)
        // A restore needs every record, so the same file is refused there.
        #expect(throws: PeptideArchiveError.incomplete) { try PeptideArchive.decode(Data(json.utf8), complete: true) }
    }

    @Test func listsThatArentArraysImportNothingButRefuseARestore() throws {
        let json = #"{"format":"jl-peptides","format_version":1,"vials":[],"schedules":{},"entries":"bad"}"#
        let archive = try PeptideArchive.decode(Data(json.utf8))
        #expect(archive.vials.isEmpty && archive.schedules.isEmpty && archive.entries.isEmpty)
        #expect(throws: PeptideArchiveError.incomplete) { try PeptideArchive.decode(Data(json.utf8), complete: true) }
        let missing = #"{"format":"jl-peptides","format_version":1,"vials":[],"schedules":[]}"#
        #expect(throws: PeptideArchiveError.incomplete) { try PeptideArchive.decode(Data(missing.utf8), complete: true) }
        let whole = #"{"format":"jl-peptides","format_version":1,"vials":[],"schedules":[],"entries":[]}"#
        #expect(try PeptideArchive.decode(Data(whole.utf8), complete: true).skipped == 0)
    }

    @Test func otherFilesAreRefused() throws {
        #expect(throws: PeptideArchiveError.unreadable) { try PeptideArchive.decode(Data("not json".utf8)) }
        #expect(throws: PeptideArchiveError.wrongFormat) {
            try PeptideArchive.decode(Data(#"{"format":"fudai-diary","format_version":1}"#.utf8))
        }
        #expect(throws: PeptideArchiveError.wrongFormat) {
            try PeptideArchive.decode(Data(#"{"format":"jl-peptides"}"#.utf8))
        }
        #expect(throws: PeptideArchiveError.newerVersion) {
            try PeptideArchive.decode(Data(#"{"format":"jl-peptides","format_version":2,"vials":[]}"#.utf8))
        }
        let padding = String(repeating: " ", count: PeptideArchive.maxBytes)
        #expect(throws: PeptideArchiveError.tooLarge) {
            try PeptideArchive.decode(Data((#"{"format":"jl-peptides","format_version":1}"# + padding).utf8))
        }
        #expect(PeptideArchive.fileName(exportedOn: now).hasPrefix("jl-peptides-"))
    }
}
