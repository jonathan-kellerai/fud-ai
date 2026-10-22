import Foundation
import Testing
@testable import calorietracker

/// "Load my schedule": exactly the user's own schedule, saved as records,
/// loaded twice without duplicates, never touching what the user added.
@MainActor
struct PeptideSchedulePresetTests {
    private let now = PeptideMath.date(civil: "2026-12-01", minutes: 9 * 60)!

    @Test func thePresetHoldsExactlyTheSchedule() {
        let preset = PeptideOwnSchedulePreset.own
        let rows = preset.items.map { item in
            [item.slot.label, PeptideMath.frequencyText(item.frequency), item.compound, item.dose.text, item.route ?? ""]
        }
        #expect(rows == [
            ["AM", "Mon/Thu", "Testosterone", "0.3 mL", "SQ"],
            ["AM", "Tue/Fri", "MT2", "250 mcg", ""],
            ["AM", "Wed/Sat", "hCG", "500 IU", ""],
            ["AM", "weekly on Sun", "GLP3", "2 mg", ""],
            ["PM", "daily", "Tesamorelin", "1.4 mg", ""],
            ["PM", "daily", "BPC-157", "500 mcg", ""],
        ])
        #expect(preset.items.first { $0.compound == "GLP3" }?.notes == "identity unverified")
        #expect(preset.items.first { $0.compound == "Testosterone" }?.vial.premixed == true)
        #expect(PeptideCompoundCatalog.isPrescription("Testosterone"))
        #expect(preset.items.filter { PeptideCompoundCatalog.isPrescription($0.compound) }.map(\.compound) == ["Testosterone"])
        #expect(preset.reminder.title == "Labs: draw before testosterone injection")
        #expect(preset.reminder.date == "2026-12-31" && preset.reminder.startMinutes == 480 && preset.reminder.endMinutes == 600)
        #expect(preset.summaryLines().count == 7)
        #expect(preset.summaryLines()[0] == "AM · Mon/Thu · Testosterone · 0.3 mL · SQ (Prescription)")
    }

    @Test func thePresetHasNoTB500() {
        let preset = PeptideOwnSchedulePreset.own
        #expect(!preset.items.contains { PeptideMath.sameCompound($0.compound, "TB-500") })
        #expect(!(preset.summaryLines() + preset.vialLines()).contains { $0.localizedCaseInsensitiveContains("TB-500") })
        let store = PeptideLogStore(persistence: .inMemory)
        store.loadPreset(preset, today: "2026-12-01", now: now)
        #expect(!store.schedules.contains { PeptideMath.sameCompound($0.compound, "TB-500") })
        #expect(!store.vials.contains { PeptideMath.sameCompound($0.compound, "TB-500") })
        #expect(PeptideCompoundCatalog.compound(named: "TB-500") == nil)
    }

    @Test func loadingSavesTheSchedulesVialsAndReminderAsRecords() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        #expect(store.loadPreset(.own, today: "2026-12-01", now: now) == nil)
        #expect(store.schedules.count == 6)
        #expect(store.schedules.allSatisfy { $0.origin == .preset && $0.active && $0.startDate == "2026-12-01" && $0.dose != nil })
        #expect(store.vials.count == 6)
        #expect(store.vials.allSatisfy { $0.mixedOn == "2026-12-01" && $0.status == .active })
        let mixes = store.vials.map { [$0.compound, $0.components.first?.amount.map(PeptideMath.number) ?? "-", $0.components.first?.unit ?? "", $0.diluentML.map(PeptideMath.number) ?? "-"] }
        #expect(mixes == [
            ["Testosterone", "-", "mg", "-"], ["MT2", "10", "mg", "2"], ["hCG", "10000", "IU", "2"],
            ["GLP3", "10", "mg", "1"], ["Tesamorelin", "5", "mg", "0.5"], ["BPC-157", "10", "mg", "3"],
        ])
        #expect(store.reminders.count == 1 && store.reminders[0].origin == .preset)
        // Nothing is logged: these are plans the user taps when taken.
        #expect(store.entries.isEmpty)
    }

    @Test func loadingTwiceDuplicatesNothingAndKeepsTheUsersOwnRecords() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        let mine = PeptideUserSchedule(id: "mine", compound: "TB-500", frequency: ReconMath.Frequency(type: "weekly", days: [3]), startDate: "2026-11-01", dose: PeptideDose(amount: 2, unit: .mg), slot: .pm)
        let myVial = PeptideVial(id: "my-vial", compound: "TB-500", diluentML: 2)
        let myReminder = PeptideReminder(id: "my-r", title: "Dentist", date: "2026-12-10", startMinutes: 600)
        store.saveSchedule(mine)
        store.saveVial(myVial)
        store.saveReminder(myReminder)
        store.loadPreset(.own, today: "2026-12-01", now: now)
        let first = (store.schedules, store.vials, store.reminders)
        // The user edits a preset schedule, then loads again a week later.
        var edited = try #require(store.schedules.first { $0.id == "preset-mt2" })
        edited.dose = PeptideDose(amount: 300, unit: .mcg)
        store.saveSchedule(edited)
        #expect(store.loadPreset(.own, today: "2026-12-08", now: now.addingTimeInterval(7 * 86_400)) == nil)
        #expect(store.schedules == first.0)
        #expect(store.vials == first.1)
        #expect(store.reminders == first.2)
        #expect(store.schedules.filter { $0.id == "mine" } == [mine])
        #expect(store.vials.filter { $0.id == "my-vial" } == [myVial])
        #expect(store.reminders.filter { $0.id == "my-r" } == [myReminder])
        #expect(store.schedules.count == 7 && store.vials.count == 7 && store.reminders.count == 2)
    }

    @Test func aScheduleAnEarlierLoadMadeAndThisOneLacksIsRemoved() {
        let store = PeptideLogStore(persistence: .inMemory)
        store.saveSchedule(PeptideUserSchedule(id: "preset-old", compound: "Old", frequency: ReconMath.Frequency(type: "daily"), startDate: "2026-11-01", origin: .preset))
        store.loadPreset(.own, today: "2026-12-01", now: now)
        #expect(!store.schedules.contains { $0.id == "preset-old" })
    }

    @Test func aLogThatCantChangeRefusesTheLoadAndChangesNothing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("peptide-preset-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("peptide_log_v1.json")
        let directory = url.deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let saved = Data(#"{"version":3,"entries":[],"vials":[],"schedules":[]}"#.utf8)
        try saved.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        let store = PeptideLogStore(persistence: .file(url))
        let refusal = store.loadPreset(.own, today: "2026-12-01", now: now)
        #expect(refusal != nil)
        #expect(store.schedules.isEmpty && store.vials.isEmpty && store.reminders.isEmpty)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        #expect(try Data(contentsOf: url) == saved)
    }
}
