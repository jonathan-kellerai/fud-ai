import Foundation
import Testing
@testable import calorietracker

/// Build 72's log version 4 and archive version 2: saves from earlier builds
/// still load, their schedules get a slot from their time and no planned dose,
/// and the new fields survive a save and a reload. Real temp files.
@MainActor
struct PeptideScheduleMigrationTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("peptide-migration-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("peptide_log_v1.json")
    }

    private func write(_ json: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    /// Three schedules as build 70 saved them: no slot, dose, route or origin.
    private let version3 = """
    {"version":3,"entries":[
      {"id":"e1","compound":"MT2","drawn_volume":25,"drawn_unit":"units","datetime":"2026-09-20T07:15:00-04:00","voided":false,"corrections":[]}
    ],"vials":[],"schedules":[
      {"id":"s-morning","compound":"BPC-157","amount":250,"units":"mcg","frequency":{"type":"daily","days":[]},"startDate":"2026-09-01","timeOfDay":450,"active":true,"notes":"","createdAt":800000000},
      {"id":"s-evening","compound":"Tesamorelin","frequency":{"type":"weekdays","days":[1,4]},"startDate":"2026-09-01","timeOfDay":1290,"active":true,"notes":"","createdAt":800000000},
      {"id":"s-untimed","compound":"MT2","frequency":{"type":"weekly","days":[]},"startDate":"2026-09-02","active":true,"notes":"","createdAt":800000000}
    ]}
    """

    @Test func aVersion3LogLoadsWithSlotsFromItsTimesAndNoPlannedDose() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try write(version3, to: url)
        let store = PeptideLogStore(persistence: .file(url))
        #expect(store.storageNote == nil)
        #expect(store.changeRefusal == nil)
        #expect(store.schedules.map(\.id) == ["s-morning", "s-evening", "s-untimed"])
        #expect(store.schedules.map(\.daySlot) == [.am, .pm, .am])
        #expect(store.schedules.allSatisfy { $0.slot == nil && $0.dose == nil && $0.route == nil && $0.origin == nil })
        // The legacy amount is kept, never turned into a planned dose.
        #expect(store.schedules[0].amount == 250 && store.schedules[0].units == "mcg")
        #expect(store.reminders.isEmpty)
        #expect(store.entries.map(\.id) == ["e1"])
        #expect(store.entries[0].scheduleID == nil)
        // Opening it rewrites nothing.
        #expect(PeptideLogSnapshot.savedVersion(of: try Data(contentsOf: url)) == 3)
    }

    @Test func theNextChangeSavesVersion4AndEverythingReadsBack() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try write(version3, to: url)
        let store = PeptideLogStore(persistence: .file(url))
        var planned = PeptideUserSchedule(
            id: "s-planned",
            compound: "hCG",
            frequency: ReconMath.Frequency(type: "weekdays", days: [3, 6]),
            startDate: "2026-10-01",
            createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            dose: PeptideDose(amount: 500, unit: .iu),
            slot: .am,
            route: "SQ"
        )
        #expect(store.saveSchedule(planned) == nil)
        planned.origin = .preset
        #expect(store.saveSchedule(planned) == nil)
        let reminder = PeptideReminder(
            id: "r1", title: "Labs", date: "2026-12-31", startMinutes: 8 * 60, endMinutes: 10 * 60,
            origin: .preset, createdAt: Date(timeIntervalSince1970: 1_790_000_000)
        )
        #expect(store.saveReminder(reminder) == nil)
        #expect(PeptideLogSnapshot.savedVersion(of: try Data(contentsOf: url)) == 4)
        #expect(PeptideLogStore.fileVersion == 4)

        let reopened = PeptideLogStore(persistence: .file(url))
        #expect(reopened.schedules == store.schedules)
        #expect(reopened.schedules.last?.dose == PeptideDose(amount: 500, unit: .iu))
        #expect(reopened.schedules.last?.origin == .preset)
        #expect(reopened.reminders == [reminder])
        #expect(reopened.entries == store.entries)
    }

    @Test func weeklyWithADayFallsOnThatWeekdayAndOldWeeklyIsUnchanged() {
        // 2026-10-05 is a Monday; 2026-10-11 a Sunday.
        let onSunday = PeptideUserSchedule(compound: "GLP3", frequency: ReconMath.Frequency(type: "weekly", days: [0]), startDate: "2026-10-01")
        let fromStart = PeptideUserSchedule(compound: "MT2", frequency: ReconMath.Frequency(type: "weekly"), startDate: "2026-10-01")
        #expect(PeptideMath.occurrences(onSunday, from: "2026-10-01", to: "2026-10-31") == ["2026-10-04", "2026-10-11", "2026-10-18", "2026-10-25"])
        #expect(PeptideMath.occurrences(fromStart, from: "2026-10-01", to: "2026-10-31") == ["2026-10-01", "2026-10-08", "2026-10-15", "2026-10-22", "2026-10-29"])
        #expect(PeptideMath.frequencyText(onSunday.frequency) == "weekly on Sun")
        #expect(PeptideMath.frequencyText(fromStart.frequency) == "weekly")
    }

    @Test func entriesKeepTheScheduleTheyLoggedThroughACorrection() throws {
        let entry = PeptideLogEntry(id: "e", compound: "hCG", dose: 500, units: "IU", date: Date(timeIntervalSince1970: 1_790_000_000), scheduleID: "s1")
        let data = try JSONEncoder().encode(entry)
        #expect(String(decoding: data, as: UTF8.self).contains("\"schedule_id\":\"s1\""))
        let decoded = try JSONDecoder().decode(PeptideLogEntry.self, from: data)
        #expect(decoded.scheduleID == "s1")
        let corrected = decoded.corrected(PeptideCorrectionChanges(dose: 450), reason: "Typo", at: "2026-10-01T08:00:00-04:00")
        #expect(corrected.scheduleID == "s1")
        #expect(corrected.dose == 450)
    }

    @Test func aVersion1ArchiveStillRestoresAndAVersion2OneNeedsItsReminders() throws {
        let v1 = #"{"format":"jl-peptides","format_version":1,"vials":[],"schedules":[],"entries":[]}"#
        let archive = try PeptideArchive.decode(Data(v1.utf8), complete: true)
        #expect(archive.reminders.isEmpty)
        let v2Missing = #"{"format":"jl-peptides","format_version":2,"vials":[],"schedules":[],"entries":[]}"#
        #expect(throws: PeptideArchiveError.incomplete) { try PeptideArchive.decode(Data(v2Missing.utf8), complete: true) }
    }

    @Test func reminderAndPlannedScheduleRoundTripThroughTheArchive() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        let schedule = PeptideUserSchedule(
            id: "s", compound: "Testosterone", frequency: ReconMath.Frequency(type: "weekdays", days: [1, 4]),
            startDate: "2026-10-01", createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            dose: PeptideDose(amount: 0.3, unit: .milliliters), slot: .am, route: "SQ", origin: .preset
        )
        store.saveSchedule(schedule)
        store.saveReminder(PeptideReminder(id: "r", title: "Labs", date: "2026-12-31", startMinutes: 480, endMinutes: 600, createdAt: Date(timeIntervalSince1970: 1_790_000_000)))
        let data = try store.archive(exportedAt: nil).encoded()
        let text = String(decoding: data, as: UTF8.self)
        for key in ["\"format_version\" : 2", "\"reminders\"", "\"start_minutes\" : 480", "\"end_minutes\" : 600", "\"slot\" : \"am\"", "\"unit\" : \"mL\"", "\"route\" : \"SQ\"", "\"origin\" : \"preset\""] {
            #expect(text.contains(key), "\(key)")
        }
        let restored = PeptideLogStore(persistence: .inMemory)
        #expect(restored.replaceAll(with: try PeptideArchive.decode(data, complete: true)) == nil)
        #expect(restored.schedules == store.schedules)
        #expect(restored.reminders == store.reminders)
        // Importing it again adds nothing.
        #expect(restored.importSummary(of: try PeptideArchive.decode(data)).added == 0)
    }

    @Test func anUnreadableReminderIsSkippedAndCounted() throws {
        let json = #"{"version":4,"entries":[],"vials":[],"schedules":[],"reminders":[{"id":"ok","title":"Labs","date":"2026-12-31","startMinutes":480},{"id":"","title":"x","date":"2026-12-31","startMinutes":480},{"id":"bad-date","title":"x","date":"31/12","startMinutes":480}]}"#
        let snapshot = try JSONDecoder().decode(PeptideLogSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.reminders.map(\.id) == ["ok"])
        #expect(snapshot.skipped == 2)
    }
}
