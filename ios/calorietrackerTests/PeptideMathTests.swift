import Foundation
import Testing
@testable import calorietracker

/// Peptides arithmetic: only from the user's own vial numbers, never IU <-> mass,
/// never a suggested amount.
///
/// xcodebuild test -project ios/calorietracker.xcodeproj -scheme calorietracker -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:calorietrackerTests/PeptideMathTests CODE_SIGNING_ALLOWED=NO
@MainActor
struct PeptideMathTests {
    // MARK: Helpers

    private func vial(
        id: String = "v1",
        compound: String = "BPC-157",
        amount: Double? = 10,
        unit: String = "mg",
        diluent: Double? = 2,
        confirmed: Bool = true,
        threshold: Double? = nil
    ) -> PeptideVial {
        PeptideVial(
            id: id,
            person: "jonathan",
            compound: compound,
            components: [PeptideVialComponent(name: compound, amount: amount, unit: unit)],
            diluentML: diluent,
            concentrationConfirmed: confirmed,
            lowStockThresholdML: threshold
        )
    }

    private func glowVial(diluent: Double? = 2, confirmed: Bool = true, threshold: Double? = nil) -> PeptideVial {
        PeptideVial(
            id: "glow",
            person: "victoria",
            compound: "Glow",
            isBlend: true,
            components: [
                PeptideVialComponent(name: "GHK-Cu", amount: 50, unit: "mg"),
                PeptideVialComponent(name: "BPC-157", amount: 10, unit: "mg"),
                PeptideVialComponent(name: "TB-500", amount: 10, unit: "mg"),
            ],
            diluentML: diluent,
            concentrationConfirmed: confirmed,
            lowStockThresholdML: threshold
        )
    }

    private func entry(
        _ id: String,
        person: String = "jonathan",
        compound: String = "BPC-157",
        dose: Double? = 500,
        units: String? = "mcg",
        civil: String = "2026-09-20",
        hour: Int = 9,
        vialID: String? = nil,
        drawn: Double? = nil,
        drawnUnit: String? = nil,
        voided: Bool = false,
        status: String = "COMPLETED"
    ) -> PeptideLogEntry {
        PeptideLogEntry(
            id: id,
            rowID: id,
            person: person,
            compound: compound,
            dose: dose,
            units: units,
            date: PeptideMath.date(civil: civil, minutes: hour * 60),
            status: status,
            voided: voided,
            vialID: vialID,
            drawnVolume: drawn,
            drawnUnit: drawnUnit
        )
    }

    private func schedule(
        compound: String = "BPC-157",
        person: String = "jonathan",
        frequency: ReconMath.Frequency,
        start: String = "2026-09-01",
        end: String? = nil
    ) -> PeptideUserSchedule {
        PeptideUserSchedule(id: "s-" + compound, person: person, compound: compound, frequency: frequency, startDate: start, endDate: end)
    }

    // MARK: Compound matching

    @Test func compoundKeyMatchesSpellings() {
        #expect(PeptideMath.compoundKey("BPC-157") == PeptideMath.compoundKey("bpc157"))
        #expect(PeptideMath.compoundKey("BPC 157") == "bpc157")
        for name in ["melanotan-ii", "Melanotan II", "MT2", "MT-2", "mt 2"] {
            #expect(PeptideMath.compoundKey(name) == "mt2", "\(name)")
        }
        #expect(PeptideMath.sameCompound("Glow", "Glow blend"))
        #expect(PeptideMath.sameCompound("TB-500", "tb500"))
        #expect(!PeptideMath.sameCompound("BPC-157", "TB-500"))
        #expect(!PeptideMath.sameCompound("", ""))
    }

    @Test func victoriaDefaultsAreExactlyMT2AndGlow() {
        #expect(PeptideMath.defaultCompounds(person: "victoria") == ["MT2", "Glow"])
        #expect(PeptideMath.compoundOptions(person: "victoria", inventoryCompounds: ["Tesamorelin"], loggedCompounds: []) == ["MT2", "Glow"])
    }

    @Test func jonathanOptionsUseInventoryStringsAndDeduplicate() {
        let options = PeptideMath.compoundOptions(
            person: "jonathan",
            inventoryCompounds: ["BPC 157 (Vial A)", "bpc157", "AOD-9604"],
            loggedCompounds: ["bpc-157", "Melanotan II", "Ipamorelin"]
        )
        // "bpc157" from the inventory replaces the roster's BPC-157 exactly.
        #expect(options.contains("bpc157"))
        #expect(!options.contains("BPC-157"))
        #expect(options.contains("AOD-9604"))
        #expect(options.contains("Ipamorelin"))
        #expect(options.filter { PeptideMath.compoundKey($0) == "mt2" }.count == 1)
        #expect(options.filter { PeptideMath.compoundKey($0) == "bpc157" }.count == 1)
    }

    @Test func logDraftsNeverPrefillAnAmount() {
        for person in PeptidePerson.order {
            let names = PeptideMath.compoundOptions(person: person, inventoryCompounds: ["Tesamorelin"], loggedCompounds: ["BPC-157"]) + [""]
            for name in names {
                let draft = PeptideLogDraft.new(person: person, compound: name)
                #expect(draft.amount == nil, "\(person) \(name)")
                #expect(draft.amountText.isEmpty)
                #expect(draft.units == nil)
                #expect(draft.drawnVolume == nil)
                #expect(PeptideMath.validate(draft)[.amount] != nil)
            }
        }
    }

    @Test func validationNeedsPositiveAmountAndUnits() {
        var draft = PeptideLogDraft.new(person: "jonathan", compound: "BPC-157")
        draft.amountText = "0"
        draft.units = "mcg"
        #expect(PeptideMath.validate(draft)[.amount] != nil)
        draft.amountText = "500"
        #expect(PeptideMath.validate(draft).isEmpty)
        draft.units = nil
        #expect(PeptideMath.validate(draft)[.units] != nil)
        draft.units = "mcg"
        draft.drawnText = "abc"
        #expect(PeptideMath.validate(draft)[.drawn] != nil)
    }

    // MARK: Concentration

    @Test func concentrationNeedsConfirmationAndEveryNumber() {
        #expect(PeptideMath.concentration(vial(confirmed: false)).reason != nil)
        #expect(PeptideMath.concentration(vial(diluent: nil)).reason != nil)
        #expect(PeptideMath.concentration(vial(diluent: 0)).reason != nil)
        #expect(PeptideMath.concentration(vial(amount: nil)).reason != nil)
        var blend = glowVial()
        blend.components[1].amount = nil
        #expect(PeptideMath.concentration(blend).reason?.contains("BPC-157") == true)
        let confirmed = PeptideMath.concentration(vial())
        #expect(confirmed.components.count == 1)
        #expect(confirmed.components.first?.perML == 5)
        #expect(confirmed.components.first?.unit == "mg")
    }

    // MARK: Drawn volume and remaining

    @Test func remainingForMcgDoseFromMgVial() {
        let bpc = vial()
        // 10 mg / 2 mL = 5000 mcg/mL. 500 mcg -> 0.1 mL.
        #expect(PeptideMath.drawnML(dose: 500, units: "mcg", drawnVolume: nil, drawnUnit: nil, vial: bpc) == 0.1)
        let entries = [
            entry("a", vialID: "v1"),
            entry("b", civil: "2026-09-21", vialID: "v1"),
            entry("c", civil: "2026-09-22", vialID: "v1", voided: true),
        ]
        let remaining = PeptideMath.remaining(vial: bpc, entries: entries)
        #expect(remaining.calculable)
        #expect(remaining.remainingML == 1.8)
        #expect(remaining.totalML == 2)
        #expect(remaining.linkedCount == 2)
        #expect(!remaining.isLow)
    }

    @Test func iuDoseFromIUVial() {
        let hcg = vial(compound: "HCG", amount: 5000, unit: "IU", diluent: 1)
        #expect(PeptideMath.drawnML(dose: 500, units: "IU", drawnVolume: nil, drawnUnit: nil, vial: hcg) == 0.1)
        let remaining = PeptideMath.remaining(vial: hcg, entries: [entry("h", compound: "HCG", dose: 500, units: "IU", vialID: "v1")])
        #expect(remaining.remainingML == 0.9)
    }

    @Test func neverConvertsBetweenIUAndMass() {
        let mass = vial()
        let iu = vial(compound: "HCG", amount: 5000, unit: "IU", diluent: 1)
        #expect(PeptideMath.drawnML(dose: 500, units: "IU", drawnVolume: nil, drawnUnit: nil, vial: mass) == nil)
        #expect(PeptideMath.drawnML(dose: 1, units: "mg", drawnVolume: nil, drawnUnit: nil, vial: iu) == nil)
        let remaining = PeptideMath.remaining(vial: mass, entries: [entry("x", dose: 500, units: "IU", vialID: "v1")])
        #expect(!remaining.calculable)
        #expect(remaining.remainingML == nil)
    }

    @Test func blendNeedsUnitsOrTypedDraw() {
        let glow = glowVial()
        let byUnits = entry("g1", person: "victoria", compound: "Glow", dose: 10, units: "units", vialID: "glow")
        let byML = entry("g2", person: "victoria", compound: "Glow", dose: 0.1, units: "mL", civil: "2026-09-21", vialID: "glow")
        let ok = PeptideMath.remaining(vial: glow, entries: [byUnits, byML])
        #expect(ok.calculable)
        #expect(ok.remainingML == 1.8)
        let typedDraw = entry("g3", person: "victoria", compound: "Glow", dose: 500, units: "mcg", civil: "2026-09-22", vialID: "glow", drawn: 20, drawnUnit: "units")
        #expect(PeptideMath.remaining(vial: glow, entries: [typedDraw]).remainingML == 1.8)
        let mcgOnly = entry("g4", person: "victoria", compound: "Glow", dose: 500, units: "mcg", civil: "2026-09-23", vialID: "glow")
        let blocked = PeptideMath.remaining(vial: glow, entries: [byUnits, mcgOnly])
        #expect(!blocked.calculable)
        #expect(blocked.reason != nil)
    }

    @Test func unconfirmedVialCannotCalculateRemaining() {
        let tesa = vial(compound: "Tesamorelin", amount: 5, diluent: 0.5, confirmed: false)
        let remaining = PeptideMath.remaining(vial: tesa, entries: [entry("t", compound: "Tesamorelin", dose: 0.1, units: "mL", vialID: "v1")])
        #expect(!remaining.calculable)
        #expect(remaining.remainingML == nil)
        #expect(!remaining.isLow)
    }

    @Test func lowStockByThresholdAndDefaultTwentyPercent() {
        // 2 mL, 1.7 mL drawn -> 0.3 mL left (15%): low by the 20% default.
        let drawn = [entry("d", dose: 1.7, units: "mL", vialID: "v1")]
        #expect(PeptideMath.remaining(vial: vial(), entries: drawn).isLow)
        // 1.5 mL drawn -> 0.5 mL (25%): not low by default, low with a 0.5 mL threshold.
        let lighter = [entry("e", dose: 1.5, units: "mL", vialID: "v1")]
        #expect(!PeptideMath.remaining(vial: vial(), entries: lighter).isLow)
        #expect(PeptideMath.remaining(vial: vial(threshold: 0.5), entries: lighter).isLow)
        #expect(!PeptideMath.remaining(vial: vial(threshold: 0.25), entries: lighter).isLow)
    }

    // MARK: Adherence

    @Test func dailyAdherenceCountsMissedAndToday() {
        let daily = schedule(frequency: ReconMath.Frequency(type: "daily"), start: "2026-09-20")
        let entries = [
            entry("1", civil: "2026-09-20"),
            entry("2", civil: "2026-09-21"),
            entry("3", civil: "2026-09-23"),
            entry("4", civil: "2026-09-22", voided: true),
        ]
        let result = PeptideMath.adherence(daily, entries: entries, from: "2026-09-20", to: "2026-09-24", today: "2026-09-24")
        #expect(result.missedDates == ["2026-09-22"])
        #expect(result.taken == 3)
        #expect(result.due == 4)
        #expect(result.todayDue)
        #expect(!result.todayTaken)
        #expect(result.streak == 1)
    }

    @Test func weekdayAndEveryNSchedules() {
        // 2026-09-21 is a Monday.
        #expect(ReconMath.weekday("2026-09-21") == 1)
        let monWedFri = schedule(frequency: ReconMath.Frequency(type: "weekdays", days: [1, 3, 5]), start: "2026-09-21")
        #expect(PeptideMath.occurrences(monWedFri, from: "2026-09-21", to: "2026-09-27") == ["2026-09-21", "2026-09-23", "2026-09-25"])
        let everyThird = schedule(frequency: ReconMath.Frequency(type: "everyN", n: 3), start: "2026-09-20")
        #expect(PeptideMath.occurrences(everyThird, from: "2026-09-20", to: "2026-09-29") == ["2026-09-20", "2026-09-23", "2026-09-26", "2026-09-29"])
        let result = PeptideMath.adherence(
            everyThird,
            entries: [entry("a", civil: "2026-09-20"), entry("b", civil: "2026-09-26")],
            from: "2026-09-20",
            to: "2026-09-29",
            today: "2026-09-29"
        )
        #expect(result.missedDates == ["2026-09-23"])
        #expect(result.due == 3)
        #expect(result.taken == 2)
        #expect(result.todayDue && !result.todayTaken)
    }

    @Test func adherenceMatchesPersonAndCompoundKey() {
        let mt2 = schedule(compound: "MT2", person: "victoria", frequency: ReconMath.Frequency(type: "daily"), start: "2026-09-20")
        let entries = [
            entry("v", person: "victoria", compound: "Melanotan II", civil: "2026-09-20"),
            entry("j", person: "jonathan", compound: "MT2", civil: "2026-09-21"),
        ]
        let result = PeptideMath.adherence(mt2, entries: entries, from: "2026-09-20", to: "2026-09-21", today: "2026-09-22")
        #expect(result.taken == 1)
        #expect(result.missedDates == ["2026-09-21"])
    }

    @Test func endDateAndInactiveStopOccurrences() {
        var ended = schedule(frequency: ReconMath.Frequency(type: "daily"), start: "2026-09-20", end: "2026-09-21")
        #expect(PeptideMath.occurrences(ended, from: "2026-09-01", to: "2026-09-30") == ["2026-09-20", "2026-09-21"])
        ended.active = false
        #expect(PeptideMath.occurrences(ended, from: "2026-09-01", to: "2026-09-30").isEmpty)
    }

    @Test func plannedAdherenceUsesCompletedID() {
        var taken = entry("p1", status: "PLANNED")
        taken.completedID = "c1"
        let open = entry("p2", civil: "2026-09-21", status: "PLANNED")
        let future = entry("p3", civil: "2026-09-30", status: "PLANNED")
        let result = PeptideMath.plannedAdherence([taken, open, future], person: "jonathan", through: "2026-09-22")
        #expect(result.due == 2)
        #expect(result.taken == 1)
    }

    // MARK: Summaries

    @Test func dailySummaryNeverSumsAcrossUnits() {
        let entries = [
            entry("1", compound: "Tesamorelin", dose: 1, units: "mg", hour: 7),
            entry("2", compound: "Tesamorelin", dose: 400, units: "mcg", hour: 9),
            entry("3", compound: "tesamorelin", dose: 0.5, units: "mg", hour: 20),
            entry("4", compound: "Tesamorelin", dose: 9, units: "mg", hour: 21, voided: true),
            entry("5", person: "victoria", compound: "MT2", dose: 250, units: "mcg"),
        ]
        let summary = PeptideMath.dailySummary(entries: entries, date: "2026-09-20", person: "jonathan")
        #expect(summary.count == 3)
        #expect(summary.totals.count == 2)
        let mg = summary.totals.first { $0.units == "mg" }
        let mcg = summary.totals.first { $0.units == "mcg" }
        #expect(mg?.total == 1.5)
        #expect(mg?.count == 2)
        #expect(mcg?.total == 400)
        #expect(summary.first != nil && summary.last != nil && summary.first! < summary.last!)
    }

    @Test func weeklyCountsBucketByMonday() {
        let entries = [
            entry("1", civil: "2026-09-21"),
            entry("2", civil: "2026-09-27"),
            entry("3", civil: "2026-09-28"),
            entry("4", compound: "TB-500", civil: "2026-09-28"),
        ]
        let all = PeptideMath.weeklyCounts(entries: entries, compound: nil, person: "jonathan", weeks: 3, today: "2026-09-30")
        #expect(all.map(\.weekStart) == ["2026-09-14", "2026-09-21", "2026-09-28"])
        #expect(all.map(\.count) == [0, 2, 2])
        let bpc = PeptideMath.weeklyCounts(entries: entries, compound: "bpc 157", person: "jonathan", weeks: 3, today: "2026-09-30")
        #expect(bpc.map(\.count) == [0, 2, 1])
    }

    @Test func civilDatesUseNewYork() {
        // 03:30 UTC on Sep 21 is still Sep 20 in New York.
        let date = PeptideMath.parseISO8601("2026-09-21T03:30:00Z")
        #expect(date.map(PeptideMath.civilDate) == "2026-09-20")
        #expect(PeptideMath.iso8601NewYork(date ?? Date()).hasSuffix("-04:00"))
    }
}
