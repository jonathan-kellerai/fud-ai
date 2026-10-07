import Foundation
import Testing
@testable import calorietracker

/// The Peptides log on this phone: what the user typed is saved as typed,
/// corrections keep a trail with a reason, voids keep the entry, and a new
/// store on the same file sees everything. Real files in a temp directory.
@MainActor
struct PeptideLogStoreTests {
    private let takenAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func draft(compound: String = "BPC-157", amount: String = "500", units: String = "mcg") -> PeptideLogDraft {
        var draft = PeptideLogDraft.new(compound: compound, now: takenAt)
        draft.amountText = amount
        draft.units = units
        return draft
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("peptide-log-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("peptide_log_v1.json")
    }

    private func bpcVial(id: String = "v-bpc") -> PeptideVial {
        PeptideVial(
            id: id,
            compound: "BPC-157",
            components: [PeptideVialComponent(name: "BPC-157", amount: 10, unit: "mg")],
            diluentML: 2,
            concentrationConfirmed: true
        )
    }

    @Test func logSavesExactlyWhatWasTyped() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        var typed = draft()
        typed.site = " Abdomen L "
        typed.notes = "Morning"
        let id = try #require(store.log(typed, id: "Dose-1", now: takenAt))
        #expect(id == "dose-1")
        let entry = try #require(store.entry(id: id))
        #expect(entry.compound == "BPC-157")
        #expect(entry.dose == 500)
        #expect(entry.units == "mcg")
        #expect(entry.route == "Abdomen L")
        #expect(entry.notes == "Morning")
        #expect(entry.date == takenAt)
        #expect(entry.datetimeRaw == PeptideMath.iso8601NewYork(takenAt))
        #expect(entry.civilDate == PeptideMath.civilDate(takenAt))
        #expect(!entry.voided)
        #expect(entry.corrections.isEmpty)
    }

    @Test func invalidDraftIsNotSaved() {
        let store = PeptideLogStore(persistence: .inMemory)
        var empty = PeptideLogDraft.new(compound: "BPC-157")
        empty.units = "mcg"
        #expect(store.log(empty) == nil)
        var noUnits = draft()
        noUnits.units = nil
        #expect(store.log(noUnits) == nil)
        #expect(store.entries.isEmpty)
    }

    @Test func savingTheSameIDAgainReplacesTheDose() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        _ = try #require(store.log(draft(amount: "500"), id: "same"))
        _ = try #require(store.log(draft(amount: "250"), id: "same"))
        #expect(store.entries.count == 1)
        #expect(store.entries.first?.dose == 250)
    }

    @Test func correctionNeedsAReasonAndKeepsATrail() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        let id = try #require(store.log(draft(), now: takenAt))
        let entry = try #require(store.entry(id: id))

        #expect(store.correct(entry, reason: "  ", changes: PeptideCorrectionChanges(dose: 250)) == "A reason is required.")
        #expect(store.correct(entry, reason: "Typo", changes: PeptideCorrectionChanges()) == "Nothing changed.")
        #expect(store.entry(id: id)?.dose == 500)

        let later = takenAt.addingTimeInterval(3_600)
        let newTime = PeptideMath.iso8601NewYork(takenAt.addingTimeInterval(-1_800))
        let changes = PeptideCorrectionChanges(datetime: newTime, dose: 250, route: "Thigh L")
        #expect(store.correct(entry, reason: " Typed the wrong amount ", changes: changes, now: later) == nil)
        let corrected = try #require(store.entry(id: id))
        #expect(corrected.dose == 250)
        #expect(corrected.route == "Thigh L")
        #expect(corrected.datetimeRaw == newTime)
        #expect(corrected.date == takenAt.addingTimeInterval(-1_800))
        #expect(corrected.corrections.map(\.field) == ["datetime", "dose", "route"])
        let dose = try #require(corrected.corrections.first { $0.field == "dose" })
        #expect(dose.old == "500")
        #expect(dose.new == "250")
        #expect(dose.reason == "Typed the wrong amount")
        #expect(dose.by == "app")
        #expect(dose.at == PeptideMath.iso8601NewYork(later))
        #expect(corrected.corrections.first { $0.field == "route" }?.old == "—")
    }

    @Test func clearingNotesRemovesThem() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        var typed = draft()
        typed.notes = "Left side"
        let id = try #require(store.log(typed))
        let entry = try #require(store.entry(id: id))
        #expect(store.correct(entry, reason: "Not needed", changes: PeptideCorrectionChanges(notes: "")) == nil)
        #expect(store.entry(id: id)?.notes == nil)
        #expect(store.entry(id: id)?.corrections.last?.new == "—")
    }

    @Test func voidKeepsTheEntryWithItsReason() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        let vial = bpcVial()
        store.saveVial(vial)
        var typed = draft(amount: "0.5", units: "mL")
        typed.vialID = vial.id
        let id = try #require(store.log(typed))
        let entry = try #require(store.entry(id: id))
        #expect(store.remaining(for: vial).remainingML == 1.5)

        #expect(store.void(entry, reason: "") == "A reason is required.")
        #expect(store.void(entry, reason: "Logged twice") == nil)
        let voided = try #require(store.entry(id: id))
        #expect(voided.voided)
        #expect(voided.voidReason == "Logged twice")
        #expect(voided.corrections.last?.field == "voided")
        #expect(store.void(voided, reason: "Again") == "This entry is already voided.")
        #expect(store.correct(voided, reason: "Fix", changes: PeptideCorrectionChanges(dose: 1)) == "This entry is voided.")
        // Still listed when voided entries are shown; never counted.
        let day = PeptideMath.civilDate(takenAt)
        #expect(store.dayEntries(day, includeVoided: true).count == 1)
        #expect(store.dayEntries(day, includeVoided: false).isEmpty)
        #expect(store.remaining(for: vial).remainingML == 2)
    }

    @Test func vialLinkAndDrawNeedNoReason() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        let vial = bpcVial()
        store.saveVial(vial)
        let id = try #require(store.log(draft()))
        let entry = try #require(store.entry(id: id))
        store.updateLocalDetails(for: entry, vialID: vial.id, drawnVolume: 10, drawnUnit: "units")
        let linked = try #require(store.entry(id: id))
        #expect(linked.vialID == vial.id)
        #expect(linked.drawnVolume == 10)
        #expect(linked.drawnUnit == "units")
        #expect(linked.corrections.isEmpty)
        #expect(store.remaining(for: vial).remainingML == 1.9)
        store.updateLocalDetails(for: linked, vialID: nil, drawnVolume: nil, drawnUnit: "units")
        #expect(store.entry(id: id)?.drawnUnit == nil)
    }

    @Test func remainingIsAlwaysCalculableFromTheUsersNumbers() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        let vial = bpcVial()
        store.saveVial(vial)
        for amount in ["0.4", "0.4", "0.4", "0.4"] {
            var typed = draft(amount: amount, units: "mL")
            typed.vialID = vial.id
            _ = try #require(store.log(typed))
        }
        let remaining = store.remaining(for: vial)
        #expect(remaining.calculable)
        #expect(remaining.remainingML == 0.4)
        #expect(remaining.isLow)
        #expect(store.lowStockVials().map(\.id) == [vial.id])
    }

    @Test func vialsAndSchedulesAreSavedAndFiltered() {
        let store = PeptideLogStore(persistence: .inMemory)
        let vial = bpcVial()
        store.saveVial(vial)
        var renamed = vial
        renamed.compound = "BPC-157 (new)"
        store.saveVial(renamed)
        #expect(store.vials.count == 1)
        #expect(store.vial(id: vial.id)?.compound == "BPC-157 (new)")
        store.finishVial(id: vial.id)
        #expect(store.vialList().isEmpty)
        #expect(store.vialList(includeFinished: true).count == 1)
        store.deleteVial(id: vial.id)
        #expect(store.vials.isEmpty)

        let schedule = PeptideUserSchedule(id: "s1", compound: "MT2", frequency: ReconMath.Frequency(type: "daily"), startDate: "2026-09-01")
        store.saveSchedule(schedule)
        #expect(store.schedules.map(\.id) == ["s1"])
        store.setScheduleActive(id: "s1", active: false)
        #expect(store.schedules.first?.active == false)
        store.deleteSchedule(id: "s1")
        #expect(store.schedules.isEmpty)
    }

    @Test func dueItemsComeFromTheUsersOwnSchedules() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        let day = PeptideMath.civilDate(takenAt)
        store.saveSchedule(PeptideUserSchedule(id: "s1", compound: "BPC-157", frequency: ReconMath.Frequency(type: "daily"), startDate: ReconMath.addDays(day, -3)))
        let before = PeptideMath.dueItems(date: day, schedules: store.schedules, entries: store.entries)
        #expect(before.map(\.taken) == [false])
        _ = try #require(store.log(draft(compound: "bpc 157")))
        let after = PeptideMath.dueItems(date: day, schedules: store.schedules, entries: store.entries)
        #expect(after.map(\.taken) == [true])
    }

    /// One person per phone: every dose is in the one log, nothing is filtered by a profile.
    @Test func everyDoseIsInTheOneLog() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        _ = try #require(store.log(draft(compound: "MT2", amount: "250"), id: "a"))
        _ = try #require(store.log(draft(compound: "BPC-157"), id: "b"))
        let day = PeptideMath.civilDate(takenAt)
        #expect(store.dayEntries(day, includeVoided: false).map(\.compound) == ["MT2", "BPC-157"])
        #expect(store.loggedCompounds() == ["BPC-157", "MT2"])
        #expect(store.takenEntries(on: day).count == 2)
        let saved = try JSONEncoder().encode(try #require(store.entry(id: "a")))
        #expect(!String(decoding: saved, as: UTF8.self).contains("person"))
    }

    @Test func homeActivityIsLocalOnly() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        let day = PeptideMath.civilDate(takenAt)
        #expect(!store.hasLocalActivity(today: day))
        let id = try #require(store.log(draft()))
        #expect(store.hasLocalActivity(today: day))
        #expect(!store.hasLocalActivity(today: ReconMath.addDays(day, 1)))
        let entry = try #require(store.entry(id: id))
        _ = store.void(entry, reason: "Wrong day")
        #expect(!store.hasLocalActivity(today: day))
        store.saveVial(bpcVial())
        #expect(store.hasLocalActivity(today: ReconMath.addDays(day, 1)))
    }

    @Test func relaunchSeesEverything() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PeptideLogStore(persistence: .file(url))
        let vial = bpcVial()
        store.saveVial(vial)
        store.saveSchedule(PeptideUserSchedule(id: "s1", compound: "BPC-157", frequency: ReconMath.Frequency(type: "everyN", n: 2), startDate: "2026-09-01"))
        var typed = draft(amount: "0.25", units: "mL")
        typed.vialID = vial.id
        typed.notes = "After training"
        let id = try #require(store.log(typed))
        let entry = try #require(store.entry(id: id))
        _ = store.correct(entry, reason: "Typo", changes: PeptideCorrectionChanges(dose: 0.3))
        #expect(store.persistError == nil)

        let reopened = PeptideLogStore(persistence: .file(url))
        #expect(reopened.entries == store.entries)
        #expect(reopened.vials == store.vials)
        #expect(reopened.schedules == store.schedules)
        #expect(reopened.entry(id: id)?.corrections.count == 1)
        #expect(reopened.remaining(for: vial).remainingML == 1.7)
        #expect(reopened.storageNote == nil)
        let saved = try #require(PeptideLogSnapshot.savedVersion(of: Data(contentsOf: url)))
        #expect(saved == PeptideLogStore.fileVersion)
    }

    @Test func unreadableRecordIsSkippedAndCounted() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
        {"version":3,"entries":[
          {"id":"ok","compound":"MT2","dose":250,"units":"mcg","datetime":"2026-09-20T07:15:00-04:00","voided":false,"corrections":[]},
          {"id":"","compound":"MT2"},
          {"compound":"no id"},
          "not a record"
        ],"vials":[],"schedules":[]}
        """
        try Data(json.utf8).write(to: url)
        let store = PeptideLogStore(persistence: .file(url))
        #expect(store.entries.map(\.id) == ["ok"])
        #expect(store.entries.first?.civilDate == "2026-09-20")
        #expect(store.storageNote?.hasPrefix("3 saved peptide records") == true)

        // A save drops the unreadable records but keeps their count, so the
        // warning is still there after a relaunch.
        _ = store.log(draft())
        let reopened = PeptideLogStore(persistence: .file(url))
        #expect(reopened.entries.count == 2)
        #expect(reopened.storageNote == store.storageNote)
    }

    @Test func savesWithoutAnOmittedCountReadAsNone() throws {
        let plain = #"{"version":3,"entries":[],"vials":[],"schedules":[]}"#
        let snapshot = try JSONDecoder().decode(PeptideLogSnapshot.self, from: Data(plain.utf8))
        #expect(snapshot.omitted == 0 && snapshot.skipped == 0)
        // Nothing omitted: the key isn't written, so the bytes stay as before.
        let encoded = try JSONEncoder().encode(PeptideLogSnapshot(version: 3, entries: [], vials: [], schedules: []))
        #expect(!String(decoding: encoded, as: UTF8.self).contains("omitted"))
        #expect(!String(decoding: encoded, as: UTF8.self).contains("held_aside"))
        let counted = try JSONEncoder().encode(PeptideLogSnapshot(version: 3, entries: [], vials: [], schedules: [], omitted: 4))
        #expect(try JSONDecoder().decode(PeptideLogSnapshot.self, from: counted).omitted == 4)
    }

    @Test func unreadableFileIsKeptAside() throws {
        let url = tempURL()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let store = PeptideLogStore(persistence: .file(url))
        #expect(store.entries.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names.contains { $0.hasPrefix("peptide_log_v1.unreadable-") })
    }

    @Test func newerSaveIsNeverOverwritten() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let newer = Data(#"{"version":4,"entries":[],"doses":[{"id":"x"}]}"#.utf8)
        try newer.write(to: url)
        let store = PeptideLogStore(persistence: .file(url))
        #expect(store.storageNote != nil)
        #expect(store.persistError != nil)
        _ = store.log(draft())
        store.saveVial(bpcVial())
        #expect(try Data(contentsOf: url) == newer)
    }
}
