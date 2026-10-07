import Foundation
import Testing
@testable import calorietracker

/// mg is worked out in one place, `PeptideMath.derivedMilligrams`, only from
/// an entry's save-time snapshot (syringe scale, vial concentration, whether
/// the vial was confirmed). It is never shown on Today, Week or Home, never
/// re-read from today's Settings or vial, and never suggested. The first nine
/// tests are the design's §4 list, in order.
@MainActor
struct PeptideDerivedMilligramsTests {
    private let takenAt = Date(timeIntervalSince1970: 1_790_000_000)

    /// mg for a saved entry, from its snapshot only.
    private func milligrams(_ entry: PeptideLogEntry) -> Double? {
        guard let draw = entry.drawnVolume, let unit = entry.drawnUnit else { return nil }
        return PeptideMath.derivedMilligrams(
            draw: draw,
            unit: unit,
            scale: entry.syringeScaleAtSave,
            concentration: entry.vialConcentrationAtSave,
            confirmed: entry.concentrationConfirmedAtSave
        )
    }

    /// 10 mg BPC-157 in 2 mL: 5 mg/mL once confirmed.
    private func bpcVial(amount: Double = 10, diluent: Double = 2, confirmed: Bool = true) -> PeptideVial {
        PeptideVial(
            id: "v-bpc",
            compound: "BPC-157",
            components: [PeptideVialComponent(id: "c", name: "BPC-157", amount: amount, unit: "mg")],
            diluentML: diluent,
            concentrationConfirmed: confirmed
        )
    }

    private func logFiftyUnits(_ store: PeptideLogStore) throws -> PeptideLogEntry {
        var draft = PeptideLogDraft.new(compound: "BPC-157", now: takenAt)
        draft.drawText = "50"
        draft.drawUnit = .units
        draft.vialID = "v-bpc"
        let id = try #require(store.log(draft, now: takenAt))
        return try #require(store.entry(id: id))
    }

    // MARK: The §4 tests

    @Test func fiftyUnitsOnU100AtFiveMgPerMLIs2Point5Mg() {
        #expect(PeptideMath.derivedMilligrams(draw: 50, unit: .units, scale: .u100, concentration: 5, confirmed: true) == 2.5)
    }

    @Test func fiftyUnitsOnU50AtFiveMgPerMLIs5Mg() {
        #expect(PeptideMath.derivedMilligrams(draw: 50, unit: .units, scale: .u50, concentration: 5, confirmed: true) == 5)
    }

    @Test func fiftyUnitsOnU40AtFiveMgPerMLIs6Point25Mg() {
        #expect(PeptideMath.derivedMilligrams(draw: 50, unit: .units, scale: .u40, concentration: 5, confirmed: true) == 6.25)
    }

    @Test func unconfirmedVialGivesNil() {
        #expect(PeptideMath.derivedMilligrams(draw: 50, unit: .units, scale: .u100, concentration: 5, confirmed: false) == nil)
    }

    @Test func missingSyringeScaleGivesNil() {
        #expect(PeptideMath.derivedMilligrams(draw: 50, unit: .units, scale: nil, concentration: 5, confirmed: true) == nil)
    }

    @Test func reconstituting10MgIn2MLIs5MgPerML() {
        #expect(PeptideMath.reconstitutedConcentration(amount: 10, diluentML: 2) == 5)
    }

    @Test func savedOnU100StaysAt2Point5MgAfterTheSettingChangesToU50() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        store.saveVial(bpcVial())
        store.setSyringeScale(.u100)
        let entry = try logFiftyUnits(store)
        #expect(milligrams(entry) == 2.5)
        store.setSyringeScale(.u50)
        let later = try #require(store.entry(id: entry.id))
        #expect(later.syringeScaleAtSave == .u100)
        #expect(milligrams(later) == 2.5)
    }

    @Test func savedAt5MgPerMLStaysAt2Point5MgAfterTheVialIsEditedTo10MgPerML() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        store.saveVial(bpcVial())
        store.setSyringeScale(.u100)
        let entry = try logFiftyUnits(store)
        store.saveVial(bpcVial(amount: 20))
        #expect(store.vial(id: "v-bpc").flatMap(PeptideMath.milligramsPerML) == 10)
        let later = try #require(store.entry(id: entry.id))
        #expect(later.vialConcentrationAtSave == 5)
        #expect(milligrams(later) == 2.5)
    }

    @Test func savedWhileUnconfirmedStaysNilAfterTheVialIsConfirmed() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        store.saveVial(bpcVial(confirmed: false))
        store.setSyringeScale(.u100)
        let entry = try logFiftyUnits(store)
        #expect(milligrams(entry) == nil)
        store.saveVial(bpcVial(confirmed: true))
        let later = try #require(store.entry(id: entry.id))
        #expect(!later.concentrationConfirmedAtSave)
        #expect(milligrams(later) == nil)
    }

    // MARK: Beyond §4

    /// An mL draw's mL is the draw itself, so it needs no syringe scale. Still nil unless confirmed.
    @Test func millilitreDrawsNeedNoScale() {
        #expect(PeptideMath.derivedMilligrams(draw: 0.1, unit: .milliliters, scale: nil, concentration: 5, confirmed: true) == 0.5)
        #expect(PeptideMath.derivedMilligrams(draw: 0.1, unit: .milliliters, scale: nil, concentration: 5, confirmed: false) == nil)
        #expect(PeptideMath.derivedMilligrams(draw: 0.1, unit: .milliliters, scale: .u40, concentration: nil, confirmed: true) == nil)
        #expect(PeptideMath.drawMilliliters(draw: 50, unit: .units, scale: .u100) == 0.5)
        #expect(PeptideMath.drawMilliliters(draw: 50, unit: .units, scale: nil) == nil)
        #expect(PeptideMath.drawMilliliters(draw: 0, unit: .milliliters, scale: nil) == nil)
    }

    @Test func reconstitutingNeedsBothNumbers() {
        #expect(PeptideMath.reconstitutedConcentration(amount: 0, diluentML: 2) == nil)
        #expect(PeptideMath.reconstitutedConcentration(amount: 10, diluentML: 0) == nil)
        #expect(PeptideMath.reconstitutedConcentration(amount: .nan, diluentML: 2) == nil)
        // mcg vials convert to mg/mL; IU and blends never become mg.
        let mcg = PeptideVial(compound: "BPC-157", components: [PeptideVialComponent(name: "BPC-157", amount: 5000, unit: "mcg")], diluentML: 2)
        #expect(PeptideMath.milligramsPerML(mcg) == 2.5)
        let iu = PeptideVial(compound: "HCG", components: [PeptideVialComponent(name: "HCG", amount: 5000, unit: "IU")], diluentML: 1)
        #expect(PeptideMath.milligramsPerML(iu) == nil)
    }

    /// The entry detail's lines, one step per line, exactly as the design shows them.
    @Test func detailShowsOneStepPerLine() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        store.saveVial(bpcVial())
        store.setSyringeScale(.u100)
        let entry = try logFiftyUnits(store)
        guard case .steps(let steps) = PeptideMath.milligramDerivation(for: entry) else {
            Issue.record("Expected the mg steps")
            return
        }
        #expect(steps.map(\.text) == [
            "50 units → 0.5 mL (U-100 syringe)",
            "0.5 mL × 5 mg/mL = 2.5 mg",
            "As recorded at save. Arithmetic on your numbers, not advice.",
        ])
        #expect(steps[1].spoken == "0.5 millilitres times 5 milligrams per millilitre equals 2.5 milligrams.")
    }

    @Test func detailSaysWhyThereIsNoMg() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        store.saveVial(bpcVial(confirmed: false))
        let neither = try logFiftyUnits(store)
        #expect(PeptideMath.milligramDerivation(for: neither) == .unavailable(["Concentration not confirmed", "Syringe scale not recorded"]))

        store.saveVial(bpcVial())
        let noScale = try logFiftyUnits(store)
        #expect(PeptideMath.milligramDerivation(for: noScale) == .unavailable(["Syringe scale not recorded"]))

        var draft = PeptideLogDraft.new(compound: "BPC-157", now: takenAt)
        draft.drawText = "0.1"
        draft.drawUnit = .milliliters
        let unlinkedID = try #require(store.log(draft))
        let unlinked = try #require(store.entry(id: unlinkedID))
        #expect(PeptideMath.milligramDerivation(for: unlinked) == .unavailable(["Concentration not confirmed"]))

        let legacy = PeptideLogEntry(id: "old", compound: "BPC-157", dose: 500, units: "mcg", date: takenAt)
        #expect(PeptideMath.milligramDerivation(for: legacy) == .noDraw)
    }
}
