import Foundation
import Testing
@testable import calorietracker

/// Recon Bench (build 67) folded into Reconstitute in build 68. The mixes the
/// user typed there (vial amount and diluent) move into Vials once, never
/// confirmed and with no dose or plan field; the second profile's are held
/// aside for the one-time choice. The old save's bytes are kept next to the
/// peptide log, and Delete Everything removes them. A save with only plans and
/// calculator figures is left as it is. Real files in a temp directory and a
/// throwaway UserDefaults suite; synthetic data only.
@MainActor
struct ReconBenchMigrationTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    /// Build 67's raw profile tags, as its Recon Bench save carries them.
    private let firstTag = PeptideLegacyProfile.firstProfileRawValue
    private let secondTag = PeptideLegacyProfile.secondProfileRawValue

    /// The first profile: Tesamorelin as the catalog has it (5 mg / 0.5 mL),
    /// BPC-157 with the diluent changed, HCG with the amount changed,
    /// Retatrutide with only the dose changed. The second profile: MT2 with the
    /// diluent changed, Glow as the catalog has it. One dose plan and one tick.
    private var benchSave: String {
        """
        {"cards":{
          "\(firstTag)":{
            "tesamorelin":{"vial":5,"water":0.5,"dose":1.4,"doseUnit":"mg","perWeek":7,"onHand":35},
            "bpc157":{"vial":10,"water":2,"dose":250,"doseUnit":"mcg","perWeek":7,"onHand":50},
            "hcg":{"vial":10000,"water":1,"dose":500,"doseUnit":"IU","perWeek":2},
            "retatrutide":{"vial":10,"water":1,"dose":4,"doseUnit":"mg","perWeek":1}},
          "\(secondTag)":{
            "mt2":{"vial":10,"water":1,"dose":250,"doseUnit":"mcg","draw":null},
            "glow":{"vial":70,"water":2,"doseUnit":"mg"}}},
         "entries":[{"id":"plan-1","person":"\(firstTag)","compound":"bpc157","dose":250,"doseUnit":"mcg",
                     "freq":{"type":"daily","days":[]},"start":"2026-09-01","weeks":8}],
         "taken":{"plan-1|2026-09-02":true}}
        """
    }

    /// Only catalog cards, a dose plan and a tick: nothing the user typed as a mix.
    private var plansOnlySave: String {
        """
        {"cards":{"\(firstTag)":{"tesamorelin":{"vial":5,"water":0.5,"dose":2,"doseUnit":"mg","perWeek":7,"onHand":20}}},
         "entries":[{"id":"plan-1","person":"\(firstTag)","compound":"tesamorelin","dose":2,"doseUnit":"mg",
                     "freq":{"type":"daily","days":[]},"start":"2026-09-01","weeks":8}],
         "taken":{"plan-1|2026-09-02":true}}
        """
    }

    private struct Phone {
        let directory: URL
        let logURL: URL
        let benchURL: URL
        let suite: String
        let defaults: UserDefaults

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("recon-bench-migration-\(UUID().uuidString)", isDirectory: true)
            logURL = directory.appendingPathComponent("PeptideLog/peptide_log_v1.json")
            benchURL = directory.appendingPathComponent("ReconBench/recon_bench_v1.json")
            suite = "recon-bench-migration-\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suite))
            try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: benchURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        func store() -> PeptideLogStore {
            PeptideLogStore(persistence: .file(logURL))
        }

        func moveMixes(into store: PeptideLogStore, now: Date) {
            ReconBenchStore.moveMixes(into: store, file: benchURL, defaults: defaults, now: now)
        }

        func copies() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: logURL.deletingLastPathComponent().path)) ?? [])
                .filter { $0.hasPrefix("peptide_log_v1.recon-bench-pre-v3-") }
        }

        func clean() {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    @Test func onlyMixesTheUserTypedMoveAndNeverConfirmed() throws {
        let found = try #require(ReconBenchMigration.vials(from: Data(benchSave.utf8), now: now))
        #expect(found.own.vials.map(\.id) == ["recon-bench-bpc157", "recon-bench-hcg"])
        #expect(found.heldAside.vials.map(\.id) == ["recon-bench-second-mt2"])
        #expect(found.own.entries.isEmpty && found.own.schedules.isEmpty)
        #expect(found.heldAside.entries.isEmpty && found.heldAside.schedules.isEmpty)

        let bpc = try #require(found.own.vials.first)
        #expect(bpc.compound == "BPC-157")
        #expect(bpc.components.map(\.amount) == [10])
        #expect(bpc.components.map(\.unit) == ["mg"])
        #expect(bpc.diluentML == 2)
        #expect(bpc.mixedOn == nil)
        #expect(!bpc.concentrationConfirmed)
        #expect(bpc.concentrationConfirmedAt == nil)
        #expect(bpc.lowStockThresholdML == nil)
        #expect(bpc.status == .active)
        #expect(bpc.notes == ReconBenchMigration.note)
        #expect(bpc.createdAt == now)
        // Unconfirmed: a draw from it shows no mg until the user confirms the mix.
        #expect(PeptideMath.derivedMilligrams(
            draw: 0.1, unit: .milliliters, scale: nil,
            concentration: PeptideMath.milligramsPerML(bpc), confirmed: bpc.concentrationConfirmed
        ) == nil)

        let hcg = try #require(found.own.vials.last)
        #expect(hcg.components.map(\.amount) == [10000])
        #expect(hcg.components.map(\.unit) == ["IU"])
        #expect(hcg.diluentML == 1)
        #expect(found.heldAside.vials.first?.diluentML == 1)
        #expect(found.heldAside.vials.first?.components.map(\.amount) == [10])
        #expect(found.heldAside.vials.allSatisfy { !$0.concentrationConfirmed })
    }

    @Test func movingKeepsTheOldSaveBesideTheLogAndRemovesTheOriginal() throws {
        let phone = try Phone()
        defer { phone.clean() }
        let bytes = Data(benchSave.utf8)
        try bytes.write(to: phone.benchURL)
        phone.defaults.set(bytes, forKey: ReconBenchStore.defaultsKey)

        let store = phone.store()
        phone.moveMixes(into: store, now: now)
        #expect(store.vials.map(\.id) == ["recon-bench-bpc157", "recon-bench-hcg"])
        #expect(store.vials.allSatisfy { !$0.concentrationConfirmed })
        #expect(store.heldAside.vials.map(\.id) == ["recon-bench-second-mt2"])
        #expect(store.heldAsideCount == 1)
        #expect(store.entries.isEmpty && store.schedules.isEmpty)

        // The untouched bytes sit next to the log; the original save is gone.
        let names = phone.copies()
        #expect(names.count == 1)
        let copy = try Data(contentsOf: phone.logURL.deletingLastPathComponent().appendingPathComponent(try #require(names.first)))
        #expect(copy == bytes)
        #expect(!FileManager.default.fileExists(atPath: phone.benchURL.path))
        #expect(phone.defaults.data(forKey: ReconBenchStore.defaultsKey) == nil)

        // Saved: a relaunch shows the same vials and moves nothing again.
        let relaunched = phone.store()
        phone.moveMixes(into: relaunched, now: now)
        #expect(relaunched.vials == store.vials)
        #expect(relaunched.heldAside == store.heldAside)
        #expect(phone.copies().count == 1)
        #expect(!String(decoding: try Data(contentsOf: phone.logURL), as: UTF8.self).contains("\"person\""))
    }

    @Test func movingTwiceAddsEachVialOnce() throws {
        let phone = try Phone()
        defer { phone.clean() }
        let store = phone.store()
        // As if the app stopped after saving the vials but before removing the old save.
        #expect(store.adoptReconBench(Data(benchSave.utf8), now: now))
        #expect(store.adoptReconBench(Data(benchSave.utf8), now: now.addingTimeInterval(1)))
        #expect(store.vials.map(\.id) == ["recon-bench-bpc157", "recon-bench-hcg"])
        #expect(store.heldAsideCount == 1)
    }

    @Test func aSaveWithOnlyPlansIsLeftUntouched() throws {
        let phone = try Phone()
        defer { phone.clean() }
        let bytes = Data(plansOnlySave.utf8)
        try bytes.write(to: phone.benchURL)
        phone.defaults.set(bytes, forKey: ReconBenchStore.defaultsKey)
        #expect(ReconBenchMigration.vials(from: bytes, now: now) == PeptideRecordsByProfile())

        let store = phone.store()
        phone.moveMixes(into: store, now: now)
        #expect(store.vials.isEmpty && store.entries.isEmpty && store.schedules.isEmpty)
        #expect(store.heldAsideCount == 0)
        #expect(try Data(contentsOf: phone.benchURL) == bytes)
        #expect(phone.defaults.data(forKey: ReconBenchStore.defaultsKey) == bytes)
        #expect(phone.copies().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: phone.logURL.path))
    }

    @Test func unreadableBytesAreLeftUntouched() throws {
        let phone = try Phone()
        defer { phone.clean() }
        let bytes = Data("not json".utf8)
        try bytes.write(to: phone.benchURL)
        #expect(ReconBenchMigration.vials(from: bytes, now: now) == nil)
        let store = phone.store()
        phone.moveMixes(into: store, now: now)
        #expect(store.vials.isEmpty)
        #expect(try Data(contentsOf: phone.benchURL) == bytes)
        #expect(phone.copies().isEmpty)
    }

    /// With nowhere to keep a copy, nothing moves and the old save stays.
    @Test func aStoreThatCantSaveLeavesTheOldSave() throws {
        let phone = try Phone()
        defer { phone.clean() }
        let bytes = Data(benchSave.utf8)
        try bytes.write(to: phone.benchURL)
        let store = PeptideLogStore(persistence: .inMemory)
        phone.moveMixes(into: store, now: now)
        #expect(store.vials.isEmpty)
        #expect(try Data(contentsOf: phone.benchURL) == bytes)
    }

    @Test func theSecondProfilesMixesWaitForTheSameChoice() throws {
        let phone = try Phone()
        defer { phone.clean() }
        try Data(benchSave.utf8).write(to: phone.benchURL)
        let store = phone.store()
        phone.moveMixes(into: store, now: now)
        store.keepHeldAside()
        #expect(store.vials.map(\.id) == ["recon-bench-bpc157", "recon-bench-hcg", "recon-bench-second-mt2"])
        #expect(store.vials.allSatisfy { !$0.concentrationConfirmed })

        let other = try Phone()
        defer { other.clean() }
        try Data(benchSave.utf8).write(to: other.benchURL)
        let deleting = other.store()
        other.moveMixes(into: deleting, now: now)
        deleting.deleteHeldAside()
        let relaunched = other.store()
        #expect(relaunched.heldAsideCount == 0)
        #expect(relaunched.vials.map(\.id) == ["recon-bench-bpc157", "recon-bench-hcg"])
    }

    @Test func movedVialsAndHeldMixesSurviveABackupAndRestore() throws {
        let phone = try Phone()
        defer { phone.clean() }
        try Data(benchSave.utf8).write(to: phone.benchURL)
        let store = phone.store()
        phone.moveMixes(into: store, now: now)
        let restored = PeptideLogStore(persistence: .inMemory)
        #expect(restored.restoreArchiveData(try #require(store.backupArchiveData())) == nil)
        #expect(restored.vials == store.vials)
        #expect(restored.heldAside == store.heldAside)
    }

    @Test func deleteEverythingRemovesTheKeptCopy() throws {
        let phone = try Phone()
        defer { phone.clean() }
        try Data(benchSave.utf8).write(to: phone.benchURL)
        let store = phone.store()
        phone.moveMixes(into: store, now: now)
        #expect(phone.copies().count == 1)
        store.deleteAll()
        ReconBenchStore.deleteSavedData(file: phone.benchURL, defaults: phone.defaults)
        #expect(phone.copies().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: phone.logURL.path))
        #expect(!FileManager.default.fileExists(atPath: phone.benchURL.path))
    }
}
