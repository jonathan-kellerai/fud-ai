import Foundation
import Testing
@testable import calorietracker

/// The one-time move from the bridge-era log (version 1) to on-device
/// records: what the Peptides screens showed is kept exactly, the assistant's
/// plans are dropped, the untouched old file is set aside first, and nothing
/// is written if that copy can't be made. Version-1 files are JSON literals
/// in the shape the old store saved. Synthetic data only.
@MainActor
struct PeptideLegacyMigrationTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("peptide-migration-\(UUID().uuidString)", isDirectory: true)
    }

    private func write(_ json: String, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("peptide_log_v1.json")
        try Data(json.utf8).write(to: url)
        return url
    }

    private func copies(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasPrefix("peptide_log_v1.pre-local-") }
    }

    /// Build 67's raw profile tags, as its saves carry them.
    private static let firstTag = PeptideLegacyProfile.firstProfileRawValue
    private static let secondTag = PeptideLegacyProfile.secondProfileRawValue

    /// Two synced app rows, an assistant COMPLETED row with badges, a PLANNED
    /// row, a voided row with a trail, a queued correction, a refused void,
    /// a queued create with a vial link, a cancelled uncertain create, and a
    /// create whose row already arrived. Plus one row with no id and one
    /// element that isn't a row. The corrected row, the refused void and the
    /// local schedule were tagged with the second profile.
    private var version1: String { """
    {"version":1,"historyComplete":true,"lastSync":800000000,
     "rows":[
      {"id":"row-app","datetime":"2026-09-20T07:30:00-04:00","compound":"BPC-157","dose":500,"units":"mcg",
       "status":"COMPLETED","recorded_via":"app","client_request_id":"crid-app","voided":false,
       "route":"Abdomen L","source_vial":"VIAL-A","created_at":"2026-09-20T11:31:00Z","correction_history":[]},
      {"id":"row-agent","datetime":"2026-09-19T21:30:00-04:00","compound":"Tesamorelin","dose":1.4,"units":"mg",
       "status":"COMPLETED","recorded_via":"peptide-agent","planned_id":"plan-0","schedule_id":"sched-1",
       "badges":["LABEL"],"voided":false},
      {"id":"plan-1","datetime":"2026-09-21T21:00:00-04:00","compound":"Tesamorelin","dose":1.4,"units":"mg",
       "status":"PLANNED","recorded_via":"peptide-agent","voided":false},
      {"id":"row-voided","datetime":"2026-09-18T07:40:00-04:00","compound":"BPC-157","dose":500,"units":"mcg",
       "status":"COMPLETED","recorded_via":"app","voided":true,"void_reason":"Logged twice",
       "correction_history":[{"at":"2026-09-18T12:00:00Z","field":"dose","old":250,"new":500,"reason":"Typo","by":"app"}]},
      {"id":"row-corrected","datetime":"2026-09-17T08:00:00-04:00","compound":"MT2","dose":250,"units":"mcg",
       "status":"COMPLETED","recorded_via":"app","person":"\(Self.secondTag)","voided":false},
      {"id":"row-refused-void","datetime":"2026-09-16T08:00:00-04:00","compound":"MT2","dose":250,"units":"mcg",
       "status":"COMPLETED","recorded_via":"app","person":"\(Self.secondTag)","voided":false},
      {"id":"row-synced-create","datetime":"2026-09-15T08:00:00-04:00","compound":"BPC-157","dose":500,"units":"mcg",
       "status":"COMPLETED","recorded_via":"app","client_request_id":"crid-synced","voided":false},
      {"datetime":"2026-09-14T08:00:00-04:00","compound":"No id"},
      "not a row"
     ],
     "pendingOps":[
      {"id":"op-correct","kind":"correct","rowID":"row-corrected","reason":"Wrong amount",
       "changes":{"dose":300,"notes":"Corrected on the phone"},"attempts":1,"failed":false,"createdAt":800000000},
      {"id":"op-void","kind":"void","rowID":"row-refused-void","reason":"Duplicate","attempts":2,
       "lastError":"refused","failed":true,"createdAt":800000000},
      {"id":"crid-queued","kind":"create","create":{"clientRequestID":"crid-queued","datetime":"2026-09-21T07:00:00-04:00",
       "dose":0.25,"units":"mL","compound":"BPC-157","route":"Thigh R","person":"\(Self.firstTag)"},
       "attempts":3,"failed":false,"createdAt":800000000,"outcomeUncertain":false},
      {"id":"crid-cancelled","kind":"create","create":{"clientRequestID":"crid-cancelled","datetime":"2026-09-21T06:00:00-04:00",
       "dose":500,"units":"mcg","compound":"BPC-157"},
       "attempts":1,"failed":false,"createdAt":800000000,"outcomeUncertain":true,"cancelReason":"Removed in the app before it synced."},
      {"id":"crid-synced","kind":"create","create":{"clientRequestID":"crid-synced","datetime":"2026-09-15T08:00:00-04:00",
       "dose":500,"units":"mcg","compound":"BPC-157"},"attempts":1,"failed":false,"createdAt":800000000,"outcomeUncertain":true}
     ],
     "meta":[
      {"key":"crid-queued","vialID":"vial-1","drawnVolume":25,"drawnUnit":"units"},
      {"key":"crid-app","vialID":"vial-1"}
     ],
     "vials":[
      {"id":"vial-1","person":"\(Self.firstTag)","compound":"BPC-157","isBlend":false,
       "components":[{"id":"c1","name":"BPC-157","amount":10,"unit":"mg"}],"diluentML":2,"mixedOn":"2026-09-10",
       "concentrationConfirmed":true,"bridgeInventoryID":"INV-SYNTH-001","status":"active","notes":"","createdAt":800000000}
     ],
     "schedules":[
      {"id":"sched-local","person":"\(Self.secondTag)","compound":"MT2","frequency":{"type":"daily","days":[]},
       "startDate":"2026-09-01","active":true,"notes":"","createdAt":800000000}
     ]}
    """ }

    private func heldEntry(_ store: PeptideLogStore, _ id: String) -> PeptideLogEntry? {
        store.heldAside.entries.first { $0.id == id }
    }

    @Test func everyRowTheScreensShowedBecomesALocalEntry() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try write(version1, in: directory)
        let store = PeptideLogStore(persistence: .file(url))

        // PLANNED dropped; the create whose row arrived stays one entry. The
        // first profile's rows (tagged or not) are the user's own; the second
        // profile's are held aside, not dropped.
        #expect(Set(store.entries.map(\.id)) == [
            "row-app", "row-agent", "row-voided",
            "row-synced-create", "crid-queued", "crid-cancelled",
        ])
        #expect(Set(store.heldAside.entries.map(\.id)) == ["row-corrected", "row-refused-void"])
        #expect(store.entry(id: "plan-1") == nil)

        let app = try #require(store.entry(id: "row-app"))
        #expect(app.dose == 500)
        #expect(app.units == "mcg")
        #expect(app.route == "Abdomen L")
        #expect(app.sourceVial == "VIAL-A")
        #expect(app.vialID == "vial-1")
        #expect(app.createdAt == "2026-09-20T11:31:00Z")
        #expect(app.datetimeRaw == "2026-09-20T07:30:00-04:00")
        #expect(app.civilDate == "2026-09-20")

        // The assistant's completed dose is a plain record now.
        let agent = try #require(store.entry(id: "row-agent"))
        #expect(agent.compound == "Tesamorelin")
        #expect(agent.dose == 1.4)
        #expect(!agent.voided)

        let voided = try #require(store.entry(id: "row-voided"))
        #expect(voided.voided)
        #expect(voided.voidReason == "Logged twice")
        #expect(voided.corrections.count == 1)
        #expect(voided.corrections.first?.old == "250")
        #expect(voided.corrections.first?.reason == "Typo")
    }

    @Test func queuedWritesAreApplied() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PeptideLogStore(persistence: .file(try write(version1, in: directory)))

        let corrected = try #require(heldEntry(store, "row-corrected"))
        #expect(corrected.dose == 300)
        #expect(corrected.notes == "Corrected on the phone")

        // Refused by the bridge, but the user voided it.
        let refused = try #require(heldEntry(store, "row-refused-void"))
        #expect(refused.voided)
        #expect(refused.voidReason == "Duplicate")

        let queued = try #require(store.entry(id: "crid-queued"))
        #expect(queued.compound == "BPC-157")
        #expect(queued.dose == 0.25)
        #expect(queued.units == "mL")
        #expect(queued.route == "Thigh R")
        #expect(queued.vialID == "vial-1")
        #expect(queued.drawnVolume == 25)
        #expect(queued.drawnUnit == "units")

        let cancelled = try #require(store.entry(id: "crid-cancelled"))
        #expect(cancelled.voided)
        #expect(cancelled.voidReason == "Removed in the app before it synced.")
    }

    /// The queue saved `createdAt` as seconds since 2001 (JSONEncoder's default).
    private let queuedAt = PeptideMath.iso8601NewYork(Date(timeIntervalSinceReferenceDate: 800_000_000))

    @Test func queuedCorrectionsAndVoidsKeepTheirReasonInTheTrail() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PeptideLogStore(persistence: .file(try write(version1, in: directory)))

        let corrected = try #require(heldEntry(store, "row-corrected"))
        #expect(corrected.corrections == [
            PeptideCorrection(at: queuedAt, field: "dose", old: "250", new: "300", reason: "Wrong amount", by: "app"),
            PeptideCorrection(at: queuedAt, field: "notes", old: "—", new: "Corrected on the phone", reason: "Wrong amount", by: "app"),
        ])

        let refused = try #require(heldEntry(store, "row-refused-void"))
        #expect(refused.corrections == [
            PeptideCorrection(at: queuedAt, field: "voided", old: "false", new: "true", reason: "Duplicate", by: "app"),
        ])

        // Survives the save: a relaunch reads the same trail.
        let reopened = PeptideLogStore(persistence: .file(directory.appendingPathComponent("peptide_log_v1.json")))
        #expect(heldEntry(reopened, "row-corrected")?.corrections == corrected.corrections)
        #expect(heldEntry(reopened, "row-refused-void")?.corrections == refused.corrections)
    }

    @Test func queuedChangesAddToTheExistingTrailInOrder() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = """
        {"version":1,
         "rows":[
          {"id":"row-1","datetime":"2026-09-17T08:00:00-04:00","compound":"MT2","dose":250,"units":"mcg",
           "status":"COMPLETED","recorded_via":"app","voided":false,
           "correction_history":[{"at":"2026-09-17T13:00:00Z","field":"units","old":"mg","new":"mcg","reason":"Typo","by":"app"}]},
          {"id":"row-2","datetime":"2026-09-16T08:00:00-04:00","compound":"MT2","dose":250,"units":"mcg",
           "status":"COMPLETED","recorded_via":"app","voided":true,"void_reason":"Already removed"}
         ],
         "pendingOps":[
          {"id":"op-1","kind":"correct","rowID":"row-1","reason":"Wrong site","changes":{"route":"Thigh L"},
           "attempts":0,"failed":false,"createdAt":800000000},
          {"id":"op-2","kind":"void","rowID":"row-1","reason":"Never taken","attempts":1,"failed":true,"createdAt":800000060},
          {"id":"op-3","kind":"void","rowID":"row-2","reason":"Again","attempts":0,"failed":false,"createdAt":800000000}
         ],
         "meta":[],"vials":[],"schedules":[]}
        """
        let store = PeptideLogStore(persistence: .file(try write(json, in: directory)))
        let entry = try #require(store.entry(id: "row-1"))
        #expect(entry.voided)
        #expect(entry.voidReason == "Never taken")
        #expect(entry.route == "Thigh L")
        #expect(entry.corrections == [
            PeptideCorrection(at: "2026-09-17T13:00:00Z", field: "units", old: "mg", new: "mcg", reason: "Typo", by: "app"),
            PeptideCorrection(at: queuedAt, field: "route", old: "—", new: "Thigh L", reason: "Wrong site", by: "app"),
            PeptideCorrection(
                at: PeptideMath.iso8601NewYork(Date(timeIntervalSinceReferenceDate: 800_000_060)),
                field: "voided", old: "false", new: "true", reason: "Never taken", by: "app"
            ),
        ])
        // Already voided: the queued void changes nothing, so the trail gains nothing.
        #expect(store.entry(id: "row-2")?.corrections.isEmpty == true)
    }

    @Test func vialsAndSchedulesComeAcross() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PeptideLogStore(persistence: .file(try write(version1, in: directory)))
        let vial = try #require(store.vial(id: "vial-1"))
        #expect(vial.diluentML == 2)
        #expect(vial.mixedOn == "2026-09-10")
        #expect(vial.concentrationConfirmed)
        #expect(store.schedules.isEmpty)
        #expect(store.heldAside.schedules.map(\.id) == ["sched-local"])
        // row-app (no draw, mcg from a 10 mg / 2 mL vial = 0.1 mL) and
        // crid-queued (25 units = 0.25 mL) come out of the vial.
        #expect(store.remaining(for: vial).remainingML == 1.65)
    }

    @Test func malformedElementsAreSkippedAndCounted() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PeptideLogStore(persistence: .file(try write(version1, in: directory)))
        #expect(store.storageNote?.hasPrefix("2 saved peptide records") == true)
        #expect(store.persistError == nil)
    }

    @Test func omittedRecordsWarningSurvivesARelaunch() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try write(version1, in: directory)
        let first = PeptideLogStore(persistence: .file(url))
        let note = try #require(first.storageNote)
        #expect(note.hasPrefix("2 saved peptide records"))

        // The saved log holds only what was read; the count is saved with it.
        let second = PeptideLogStore(persistence: .file(url))
        #expect(second.storageNote == note)
        second.saveVial(PeptideVial(id: "vial-2", compound: "MT2", diluentML: 1))
        let third = PeptideLogStore(persistence: .file(url))
        #expect(third.storageNote == note)
        #expect(third.vial(id: "vial-2") != nil)

        // Delete Everything clears it.
        third.deleteAll()
        #expect(PeptideLogStore(persistence: .file(url)).storageNote == nil)
    }

    @Test func untouchedCopyIsWrittenFirstAndASecondLaunchIsANoOp() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try write(version1, in: directory)
        let first = PeptideLogStore(persistence: .file(url))
        let names = copies(in: directory)
        #expect(names.count == 1)
        let copy = try Data(contentsOf: directory.appendingPathComponent(try #require(names.first)))
        #expect(copy == Data(version1.utf8))
        #expect(PeptideLogSnapshot.savedVersion(of: try Data(contentsOf: url)) == PeptideLogStore.fileVersion)

        let second = PeptideLogStore(persistence: .file(url))
        #expect(second.entries == first.entries)
        #expect(second.vials == first.vials)
        #expect(second.schedules == first.schedules)
        #expect(second.heldAside == first.heldAside)
        #expect(copies(in: directory).count == 1)
    }

    @Test func defaultsOnlyLogIsMigratedAndTheDefaultsCopyCleared() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "peptide-migration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(version1.utf8), forKey: PeptideLogStore.defaultsKey)
        let url = directory.appendingPathComponent("peptide_log_v1.json")

        let store = PeptideLogStore(persistence: .file(url, defaults: defaults))
        #expect(store.entries.count == 6)
        #expect(store.heldAside.entries.count == 2)
        #expect(copies(in: directory).count == 1)
        #expect(PeptideLogSnapshot.savedVersion(of: try Data(contentsOf: url)) == PeptideLogStore.fileVersion)
        #expect(defaults.data(forKey: PeptideLogStore.defaultsKey) == nil)
    }

    @Test func copyFailureLeavesTheOldLogUntouched() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // A regular file where the log's folder should be: nothing can be written there.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appendingPathComponent("blocked")
        try Data().write(to: blocker)
        let url = blocker.appendingPathComponent("peptide_log_v1.json")
        let suite = "peptide-migration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(version1.utf8), forKey: PeptideLogStore.defaultsKey)

        let store = PeptideLogStore(persistence: .file(url, defaults: defaults))
        // Shown from memory, never saved over.
        #expect(store.entries.count == 6)
        #expect(store.persistError != nil)
        _ = store.log({
            var draft = PeptideLogDraft.new(compound: "BPC-157")
            draft.amountText = "500"
            draft.units = "mcg"
            return draft
        }())
        #expect(defaults.data(forKey: PeptideLogStore.defaultsKey) == Data(version1.utf8))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func unsupportedVersionIsLeftAlone() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let newer = #"{"version":7,"rows":[],"entries":[]}"#
        let url = try write(newer, in: directory)
        let store = PeptideLogStore(persistence: .file(url))
        #expect(store.entries.isEmpty)
        #expect(store.storageNote != nil)
        store.saveSchedule(PeptideUserSchedule(compound: "BPC-157", frequency: ReconMath.Frequency(type: "daily"), startDate: "2026-09-01"))
        #expect(try Data(contentsOf: url) == Data(newer.utf8))
        #expect(copies(in: directory).isEmpty)
    }

    @Test func savesWithoutAVersionReadAsVersion1() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = #"{"rows":[{"id":"r1","datetime":"2026-09-20T07:30:00-04:00","compound":"BPC-157","status":"COMPLETED","recorded_via":"app"}],"pendingOps":[],"meta":[],"vials":[],"schedules":[]}"#
        let store = PeptideLogStore(persistence: .file(try write(old, in: directory)))
        #expect(store.entries.map(\.id) == ["r1"])
        #expect(copies(in: directory).count == 1)
    }

    @Test func bridgeRowsDecodeFieldByField() throws {
        let rows = """
        [{"id":42,"datetime":"2026-09-20T13:00:00Z","compound":"BPC-157","dose":"500","units":5,
          "voided":"1","recorded_via":"app","badges":["LABEL",3],"person":null,
          "correction_history":"oops","planned_id":7,"dose_deviates_from_planned":0},
         {"datetime":"2026-09-21T13:00:00Z","compound":"MT2"},
         "not a row",
         {"id":"ok-1","datetime":"2026-09-22T13:00:00Z","compound":"MT2","dose":250,"units":"mcg","status":"COMPLETED"}]
        """
        let decoded = try JSONDecoder().decode([PeptideLossy<PeptideAdministration>].self, from: Data(rows.utf8))
        let kept = decoded.compactMap(\.value).filter { !$0.id.isEmpty }
        #expect(kept.map(\.id) == ["42", "ok-1"])
        let odd = try #require(kept.first)
        #expect(odd.dose == 500)
        #expect(odd.units == "5")
        #expect(odd.voided)
        #expect(odd.recordedVia == "app")
        #expect(odd.badges == ["LABEL", "3"])
        #expect(odd.plannedId == "7")
        #expect(odd.correctionHistory.isEmpty)
    }
}
