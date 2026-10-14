import Foundation
import Testing
@testable import calorietracker

/// Planned doses and U-100 syringe units: a dose is saved with its unit as
/// typed (never converted), and its units are arithmetic on the vial the user
/// recorded (amount ÷ water = concentration; units = dose ÷ concentration ×
/// 100; an mL dose is mL × 100). No concentration, no units; never mg from a
/// concentration nobody entered.
@MainActor
struct PeptideDoseUnitTests {
    /// Tue 2026-12-01 09:00 New York.
    private let now = PeptideMath.date(civil: "2026-12-01", minutes: 9 * 60)!

    private func loaded() -> PeptideLogStore {
        let store = PeptideLogStore(persistence: .inMemory)
        #expect(store.loadPreset(.own, today: "2026-12-01", now: now) == nil)
        return store
    }

    private func schedule(_ store: PeptideLogStore, _ compound: String) throws -> PeptideUserSchedule {
        try #require(store.schedules.first { $0.compound == compound })
    }

    @Test func unitsComeFromTheStoredVialAndWater() throws {
        let store = loaded()
        let expected: [(String, Double)] = [
            ("Testosterone", 30), ("MT2", 5), ("hCG", 10), ("GLP3", 20), ("Tesamorelin", 14), ("BPC-157", 15),
        ]
        for (compound, units) in expected {
            let planned = try schedule(store, compound)
            let id = try #require(store.logPlanned(scheduleID: planned.id, now: now))
            let entry = try #require(store.entry(id: id))
            #expect(entry.syringeUnitsAtSave == units, "\(compound)")
            // The same arithmetic, straight from the vial record.
            let vial = try #require(store.plannedVial(for: compound))
            #expect(PeptideMath.syringeUnits(try #require(planned.dose), vial: vial) == units, "\(compound)")
            // Saved as planned: amount and unit, never converted.
            #expect(entry.dose == planned.dose?.amount && entry.units == planned.dose?.unit.rawValue, "\(compound)")
            #expect(entry.vialID == vial.id && entry.scheduleID == planned.id, "\(compound)")
        }
        let bpc = try #require(store.plannedVial(for: "BPC-157"))
        #expect(bpc.components.first?.amount == 10 && bpc.diluentML == 3)
        #expect(PeptideMath.reconstitutedConcentration(amount: 10, diluentML: 3).map { ReconMath.fmtTrim($0, 2) } == "3.33")
    }

    @Test func testosteroneInMLWithNoConcentrationShowsNoMilligrams() throws {
        let store = loaded()
        let vial = try #require(store.plannedVial(for: "Testosterone"))
        #expect(vial.isPremixed)
        #expect(vial.components.first?.amount == nil)
        #expect(PeptideMath.milligramsPerML(vial) == nil)
        #expect(PeptideMath.concentration(vial).components.isEmpty)
        let id = try #require(store.logPlanned(scheduleID: try schedule(store, "Testosterone").id, now: now))
        let entry = try #require(store.entry(id: id))
        #expect(entry.dose == 0.3 && entry.units == "mL")
        #expect(entry.vialConcentrationAtSave == nil)
        #expect(PeptideMath.derivedMilligrams(
            draw: 0.3, unit: .milliliters, scale: nil,
            concentration: entry.vialConcentrationAtSave, confirmed: entry.concentrationConfirmedAtSave
        ) == nil)
        if case .steps = PeptideMath.milligramDerivation(for: entry) { Issue.record("mg worked out without a concentration") }
        // The mL is recorded as entered, and its units need no concentration.
        #expect(entry.syringeUnitsAtSave == 30)
        #expect(PeptideMath.drawnML(for: entry, vial: vial) == 0.3)
    }

    @Test func noConcentrationMeansNoUnitsForANonMLDose() {
        let unmixed = PeptideVial(compound: "MT2", components: [PeptideVialComponent(name: "MT2", amount: 10, unit: "mg")], diluentML: 2)
        let noWater = PeptideVial(compound: "MT2", components: [PeptideVialComponent(name: "MT2", amount: 10, unit: "mg")], concentrationConfirmed: true)
        let dose = PeptideDose(amount: 250, unit: .mcg)
        #expect(PeptideMath.syringeUnits(dose, vial: nil) == nil)
        #expect(PeptideMath.syringeUnits(dose, vial: unmixed) == nil)
        #expect(PeptideMath.syringeUnits(dose, vial: noWater) == nil)
        // IU never becomes mass.
        let iuVial = PeptideVial(compound: "hCG", components: [PeptideVialComponent(name: "hCG", amount: 10_000, unit: "IU")], diluentML: 2, concentrationConfirmed: true)
        #expect(PeptideMath.syringeUnits(PeptideDose(amount: 1, unit: .mg), vial: iuVial) == nil)
        #expect(PeptideMath.syringeUnits(PeptideDose(amount: 500, unit: .iu), vial: iuVial) == 10)
        // An mL dose is its own volume.
        #expect(PeptideMath.syringeUnits(PeptideDose(amount: 0.25, unit: .milliliters), vial: nil) == 25)
    }

    @Test func aTypedDrawRecordsItsU100Units() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        store.setSyringeScale(.u50)
        var draft = PeptideLogDraft.new(compound: "BPC-157", now: now)
        draft.drawText = "10"
        draft.drawUnit = .units
        // 10 units on a U-50 syringe is 0.2 mL: 20 units on U-100.
        #expect(store.entry(from: draft, id: "a").syringeUnitsAtSave == 20)
        draft.drawText = "0.15"
        draft.drawUnit = .milliliters
        #expect(store.entry(from: draft, id: "b").syringeUnitsAtSave == 15)
        store.setSyringeScale(nil)
        draft.drawUnit = .units
        #expect(store.entry(from: draft, id: "c").syringeUnitsAtSave == nil)
    }

    @Test func tesamorelinShowsDosesLeftAndAsksToRemixUnderOneDose() throws {
        let store = loaded()
        let vial = try #require(store.plannedVial(for: "Tesamorelin"))
        let fresh = try #require(store.supply(for: vial))
        #expect(fresh.totalML == 0.5 && fresh.doseML == 0.14)
        #expect(ReconMath.fmtTrim(fresh.dosesLeft, 2) == "3.57")
        #expect(fresh.text == "3.6 doses left (1.4 mg each)")
        #expect(!fresh.remixSoon)
        let tesa = try schedule(store, "Tesamorelin")
        for day in 0..<2 {
            store.logPlanned(scheduleID: tesa.id, now: now.addingTimeInterval(Double(day) * 86_400))
        }
        let two = try #require(store.supply(for: vial))
        #expect(two.remainingML == 0.22 && !two.remixSoon)
        store.logPlanned(scheduleID: tesa.id, now: now.addingTimeInterval(2 * 86_400))
        let three = try #require(store.supply(for: vial))
        #expect(three.remainingML == 0.08)
        #expect(three.dosesLeft < 1 && three.remixSoon)
        // Tapping twice on one day logs one dose.
        store.logPlanned(scheduleID: tesa.id, now: now.addingTimeInterval(2 * 86_400 + 60))
        #expect(store.supply(for: vial) == three)
        // A voided dose goes back in the vial.
        let last = try #require(store.entries.last { $0.scheduleID == tesa.id })
        store.void(last, reason: "Not taken", now: now.addingTimeInterval(3 * 86_400))
        #expect(store.supply(for: vial)?.remainingML == 0.22)
    }

    @Test func dosesBeforeTheVialWasMixedDontCount() throws {
        var vial = PeptideVial(
            id: "v", compound: "Tesamorelin", components: [PeptideVialComponent(name: "Tesamorelin", amount: 5, unit: "mg")],
            diluentML: 0.5, mixedOn: "2026-12-02", concentrationConfirmed: true
        )
        let dose = PeptideDose(amount: 1.4, unit: .mg)
        let before = PeptideLogEntry(id: "b", compound: "Tesamorelin", dose: 1.4, units: "mg", date: now, vialID: "v")
        let after = PeptideLogEntry(id: "a", compound: "Tesamorelin", dose: 1.4, units: "mg", date: now.addingTimeInterval(86_400), vialID: "v")
        #expect(PeptideMath.supply(vial: vial, entries: [before, after], dose: dose)?.remainingML == 0.36)
        vial.mixedOn = nil
        #expect(PeptideMath.supply(vial: vial, entries: [before, after], dose: dose)?.remainingML == 0.22)
    }

    @Test func oldVialsWithoutMixingDataStillLoad() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("peptide-units-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("peptide_log_v1.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
        {"version":3,"entries":[],"schedules":[
          {"id":"s","compound":"MT2","frequency":{"type":"daily","days":[]},"startDate":"2026-09-01","active":true,"notes":"","createdAt":800000000}
        ],"vials":[
          {"id":"bare","compound":"MT2","isBlend":false,"components":[],"concentrationConfirmed":false,"status":"active","notes":"","createdAt":800000000},
          {"id":"mixed","compound":"BPC-157","isBlend":false,"components":[{"id":"c","name":"BPC-157","amount":10,"unit":"mg"}],"diluentML":2,"concentrationConfirmed":true,"status":"active","notes":"","createdAt":800000000}
        ]}
        """
        try Data(json.utf8).write(to: url)
        let store = PeptideLogStore(persistence: .file(url))
        #expect(store.storageNote == nil)
        #expect(store.vials.map(\.id) == ["bare", "mixed"])
        #expect(store.vials.allSatisfy { $0.premixed == nil && !$0.isPremixed })
        let bare = store.vials[0]
        // No planned dose and no numbers: nothing is worked out.
        #expect(store.supply(for: bare) == nil)
        #expect(PeptideMath.syringeUnits(PeptideDose(amount: 250, unit: .mcg), vial: bare) == nil)
        #expect(PeptideMath.syringeUnits(PeptideDose(amount: 250, unit: .mcg), vial: store.vials[1]) == 5)
        // Still the same after a save as version 4.
        store.setScheduleActive(id: "s", active: false)
        #expect(PeptideLogStore(persistence: .file(url)).vials == store.vials)
    }

    @Test func dosesRoundTripWithTheirUnitsThroughTheLogAndTheArchive() throws {
        for unit in PeptideDoseUnit.allCases {
            let dose = PeptideDose(amount: 1.25, unit: unit)
            let decoded = try JSONDecoder().decode(PeptideDose.self, from: try JSONEncoder().encode(dose))
            #expect(decoded == dose)
        }
        #expect(PeptideDoseUnit.allCases.map(\.rawValue) == ["mL", "IU", "mg", "mcg"])
        let store = loaded()
        for item in PeptideOwnSchedulePreset.own.items {
            store.logPlanned(scheduleID: item.id, now: now)
        }
        let archive = try PeptideArchive.decode(store.archive(exportedAt: nil).encoded(), complete: true)
        let restored = PeptideLogStore(persistence: .inMemory)
        #expect(restored.replaceAll(with: archive) == nil)
        #expect(restored.schedules.map(\.dose) == store.schedules.map(\.dose))
        #expect(restored.entries.map(\.units) == store.entries.map(\.units))
        #expect(restored.entries.map(\.dose) == store.entries.map(\.dose))
        #expect(restored.entries.map(\.syringeUnitsAtSave) == store.entries.map(\.syringeUnitsAtSave))
        #expect(restored.vials.map(\.premixed) == store.vials.map(\.premixed))
        #expect(PeptideDose.typed("0,3", unit: .milliliters) == PeptideDose(amount: 0.3, unit: .milliliters))
        #expect(PeptideDose.typed("0", unit: .mg) == nil)
        #expect(PeptideDose.typed("2", unit: nil) == nil)
    }
}
