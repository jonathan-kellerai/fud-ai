import Foundation
import Testing
@testable import calorietracker

/// Port of recon-bench.html `runSelfTest()`. Expected numbers and display strings match that file.
///
/// Xcode 26:
/// xcodebuild test -project ios/calorietracker.xcodeproj -scheme calorietracker -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:calorietrackerTests/ReconMathTests CODE_SIGNING_ALLOWED=NO
struct ReconMathTests {
    @Test func runSelfTest() {
        let rows = ReconBenchSelfTest.rows()
        #expect(rows.count == 42)
        for row in rows {
            #expect(row.pass, "\(row.name) | expected \(row.expected) | got \(row.got)")
        }
    }

    @Test func scheduleEntryDoesNotStoreSyringeUnits() throws {
        let entry = ReconMath.ScheduleEntry(
            id: "st1",
            person: "jonathan",
            compound: "retatrutide",
            dose: 2,
            doseUnit: "mg",
            draw: nil,
            freq: ReconMath.Frequency(type: "weekly"),
            start: "2026-01-05",
            weeks: 8
        )
        let data = try JSONEncoder().encode(entry)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["units"] == nil)
        #expect(object["unitsText"] == nil)
        #expect(object["dose"] as? Double == 2)
        #expect(object["doseUnit"] as? String == "mg")
    }

    @Test func bridgeSyncStaysOffUnlessMarkedTaken() {
        #expect(ReconMath.shouldSyncTakenToBridge(syncEnabled: false, markingTaken: true) == false)
        #expect(ReconMath.shouldSyncTakenToBridge(syncEnabled: true, markingTaken: false) == false)
        #expect(ReconMath.shouldSyncTakenToBridge(syncEnabled: true, markingTaken: true) == true)
    }

    @Test func footerTextMatchesTheBench() {
        #expect(ReconMath.footerText == "This app converts doses to syringe units and tracks supply. It sets no doses and recommends no protocol. Research compounds; not medical advice.")
    }
}

private struct ReconBenchRow {
    var name: String
    var pass: Bool
    var expected: String
    var got: String
}

private enum ReconBenchSelfTest {
    static func rows() -> [ReconBenchRow] {
        var rows: [ReconBenchRow] = []
        func record(_ name: String, _ pass: Bool, _ expected: String, _ got: String) {
            rows.append(ReconBenchRow(name: name, pass: pass, expected: expected, got: got))
        }

        let cases: [(Double, String, Double, Double, String, Double, String)] = [
            (5000, "IU", 1.0, 250, "IU", 5, "5"),
            (5000, "IU", 1.0, 500, "IU", 10, "10"),
            (5, "mg", 2.0, 200, "mcg", 8, "8"),
            (5, "mg", 0.5, 2, "mg", 20, "20"),
            (5, "mg", 0.5, 1.4, "mg", 14, "14"),
            (10, "mg", 1.0, 2, "mg", 20, "20"),
            (10, "mg", 1.0, 4, "mg", 40, "40"),
            (10, "mg", 3.0, 500, "mcg", 15, "15"),
            (10, "mg", 2.0, 250, "mcg", 5, "5"),
            (100, "mg", 0.5, 100, "mg", 50, "50")
        ]
        for sample in cases {
            let result = ReconMath.compute(vialAmount: sample.0, vialUnit: sample.1, waterML: sample.2, dose: sample.3, doseUnit: sample.4)
            let pass = result.ok && abs(result.units - sample.5) < 1e-9 && ReconMath.fmtUnits(result.units) == sample.6
            let got = result.ok ? ReconMath.fmtUnits(result.units) + " units (raw \(result.units))" : (result.error ?? "")
            let water = String(format: "%.1f", sample.2)
            record("\(js(sample.0)) \(sample.1) + \(water) mL, dose \(js(sample.3)) \(sample.4)", pass, sample.6 + " units", got)
        }

        let twenty = ReconMath.compute(vialAmount: 5, vialUnit: "mg", waterML: 0.5, dose: 2, doseUnit: "mg")
        record("5 mg + 0.5 mL, 2 mg is NOT 40", twenty.units != 40 && abs(twenty.units - 40) > 1, "not 40", ReconMath.fmtUnits(twenty.units))

        let mixed = ReconMath.compute(vialAmount: 5, vialUnit: "mg", waterML: 2.0, dose: 0.2, doseUnit: "mg")
        record("mg/mcg mix: 0.2 mg == 200 mcg at 5 mg + 2.0 mL", mixed.ok && abs(mixed.units - 8) < 1e-9, "8 units", ReconMath.fmtUnits(mixed.units))
        record("Volume display 5 mg/0.5 mL, 2 mg", ReconMath.fmtML(twenty.volumeML) == "0.200", "0.200 mL", ReconMath.fmtML(twenty.volumeML) + " mL")

        let glow = ReconMath.compounds["glow"]
        let breakdown = ReconMath.blendBreakdown(blend: glow?.blend ?? [], blendVialNominal: glow?.vial ?? 70, vialAmount: 70, waterML: 2.0, units: 10)
        let want = ["GHK-Cu": (2500.0, "2.5 mg"), "BPC-157": (500.0, "500 mcg"), "TB-500": (500.0, "500 mcg")]
        for component in breakdown.components {
            let expected = want[component.name]
            let shown = ReconMath.fmtAmountN(component.deliveredN, "mass")
            let pass = expected != nil && abs(component.deliveredN - (expected?.0 ?? 0)) < 1e-9 && shown == expected?.1
            record("Glow 70 mg + 2.0 mL, 10-unit draw: \(component.name)", pass, expected?.1 ?? "", shown)
        }
        let totalCheck = breakdown.totalCheck
        record(
            "Glow total round-trips through compute() to 10 units",
            (totalCheck?.ok ?? false) && abs((totalCheck?.units ?? .nan) - 10) < 1e-9,
            "10",
            ReconMath.fmtUnits(totalCheck?.units ?? .nan)
        )
        record(
            "Glow default draw raises GHK-Cu > 2 mg flag (expected per spec)",
            breakdown.flags.contains { $0.code == "blend-GHK-Cu" },
            "flag present",
            breakdown.flags.map(\.code).joined(separator: ",").isEmpty ? "none" : breakdown.flags.map(\.code).joined(separator: ",")
        )

        let twelve = ReconMath.compute(vialAmount: 10, vialUnit: "mg", waterML: 1.0, dose: 12, doseUnit: "mg")
        record("12 mg from 10 mg vial at 1.0 mL -> 120 units", twelve.ok && abs(twelve.units - 120) < 1e-9 && ReconMath.fmtUnits(twelve.units) == "120", "120 units", ReconMath.fmtUnits(twelve.units))
        record("12 mg: exceeds-syringe AND exceeds-vial flags", ReconMath.hasFlag(twelve, "exceeds-syringe") && ReconMath.hasFlag(twelve, "exceeds-vial"), "both", twelve.flags.map(\.code).joined(separator: ","))

        let iuMass = ReconMath.compute(vialAmount: 5000, vialUnit: "IU", waterML: 1.0, dose: 1, doseUnit: "mg")
        record("IU vial with mg dose rejected", !iuMass.ok && iuMass.error == "IU_MISMATCH" && iuMass.units.isNaN, "IU_MISMATCH", iuMass.error ?? "")
        let massIU = ReconMath.compute(vialAmount: 10, vialUnit: "mg", waterML: 1.0, dose: 500, doseUnit: "IU")
        record("mg vial with IU dose rejected", !massIU.ok && massIU.error == "IU_MISMATCH", "IU_MISMATCH", massIU.error ?? "")

        let reversed = ReconMath.reverseCompute(vialAmount: 5, vialUnit: "mg", waterML: 0.5, units: twenty.units)
        record("Reverse check: 20 units at 5 mg/0.5 mL = 2 mg", reversed.ok && abs(reversed.amountN - 2000) < 1e-9 && ReconMath.fmtAmountIn(reversed.amountN, unit: "mg") == "2 mg", "2 mg", ReconMath.fmtAmountIn(reversed.amountN, unit: "mg"))

        let emptyDose = ["nad", "kisspeptin", "aod9604", "cjc1295"].allSatisfy { ReconMath.defaultCard(person: "jonathan", key: $0).dose == nil }
        record("NONE / no-preset compounds ship with empty dose", emptyDose, "empty", emptyDose ? "empty" : "NOT EMPTY")

        let roster = (ReconMath.roster["jonathan"] ?? []) + (ReconMath.roster["victoria"] ?? [])
        let absent = ReconMath.compounds["aod9604"]?.water == nil && ReconMath.compounds["cjc1295"]?.water == nil && roster.allSatisfy { $0 != "aod9604" && $0 != "cjc1295" }
        record("AOD-9604 / CJC-1295 have no water volume and are not on any roster", absent, "true", "checked")
        record("Victoria roster is exactly Glow + MT2", (ReconMath.roster["victoria"] ?? []).joined(separator: ",") == "glow,mt2", "glow,mt2", (ReconMath.roster["victoria"] ?? []).joined(separator: ","))

        var roundTrip = true
        var roundTripGot: [String] = []
        for key in ReconMath.calculatorOrder {
            guard let compound = ReconMath.compounds[key] else { continue }
            for preset in compound.presets {
                guard let dose = preset.dose, let unit = preset.unit else { continue }
                let result = ReconMath.compute(vialAmount: compound.vial, vialUnit: compound.vialUnit, waterML: compound.water ?? .nan, dose: dose, doseUnit: unit)
                let back = ReconMath.reverseCompute(vialAmount: compound.vial, vialUnit: compound.vialUnit, waterML: compound.water ?? .nan, units: result.units)
                if !(result.ok && back.ok && abs(back.amountN - result.doseN) < 1e-9) { roundTrip = false }
                roundTripGot.append("\(compound.abbreviation) \(js(dose)) \(unit) = \(ReconMath.fmtUnits(result.units))")
            }
        }
        let roundTripText = roundTripGot.joined(separator: "; ")
        let roundTripOracle = "Tesa 1.4 mg = 14; Tesa 1.28 mg = 12.8; Reta 2 mg = 20; Reta 4 mg = 40; Reta 6 mg = 60; Reta 8 mg = 80; HCG 500 IU = 10; HCG 250 IU = 5; HCG 1500 IU = 30; MT2 250 mcg = 5; MT2 500 mcg = 10; BPC 500 mcg = 15; TB 2 mg = 40"
        record("Every preset round-trips through compute()/reverse", roundTrip && roundTripText == roundTripOracle, "all ok", roundTripText)

        let pairs: [(String, Double, String)] = [
            ("tesamorelin", 2, "mg"), ("tesamorelin", 1.4, "mg"), ("retatrutide", 2, "mg"), ("retatrutide", 4, "mg"),
            ("hcg", 500, "IU"), ("hcg", 250, "IU"), ("mt2", 250, "mcg"), ("bpc157", 500, "mcg"), ("tb500", 2, "mg")
        ]
        for pair in pairs {
            let compound = ReconMath.compounds[pair.0]
            let calculatorText = ReconMath.fmtUnits(ReconMath.compute(vialAmount: compound?.vial ?? .nan, vialUnit: compound?.vialUnit ?? "", waterML: compound?.water ?? .nan, dose: pair.1, doseUnit: pair.2).units)
            let entry = ReconMath.ScheduleEntry(id: "cal", person: "jonathan", compound: pair.0, dose: pair.1, doseUnit: pair.2, draw: nil, freq: ReconMath.Frequency(type: "weekly"), start: "2026-01-05", weeks: 1)
            let calendarText = ReconMath.entryUnitsText(entry: entry, config: defaultConfig)
            record("Calendar = calculator: \(compound?.name ?? pair.0) \(js(pair.1)) \(pair.2)", calculatorText == calendarText && calculatorText != "—", calculatorText, calendarText)
        }
        let glowEntry = ReconMath.ScheduleEntry(id: "glow", person: "victoria", compound: "glow", dose: nil, doseUnit: nil, draw: 10, freq: ReconMath.Frequency(type: "weekly"), start: "2026-01-05", weeks: 1)
        let glowCalendar = ReconMath.entryUnitsText(entry: glowEntry, config: defaultConfig)
        record("Calendar = calculator: Glow 10-unit draw", glowCalendar == "10", "10", glowCalendar)

        let retatrutide = [ReconMath.ScheduleEntry(id: "st1", person: "jonathan", compound: "retatrutide", dose: 2, doseUnit: "mg", draw: nil, freq: ReconMath.Frequency(type: "weekly"), start: "2026-01-05", weeks: 8)]
        let simulation = ReconMath.simulateSupply(entries: retatrutide, config: defaultConfig, onHand: defaultOnHand)
        let statuses = simulation.occurrences.map(\.status).joined(separator: ",")
        record("Retatrutide 2 mg weekly x 8 wk, 10 mg on hand: doses 1–5 ok, 6–8 red", statuses == "ok,ok,ok,ok,ok,short,short,short", "ok×5, short×3", statuses)
        let pool = simulation.pools["jonathan|retatrutide"]
        record("Retatrutide run-out date = 6th dose", pool?.runOut == "2026-02-09" && pool?.lastCovered == "2026-02-02", "2026-02-09", pool?.runOut ?? "")

        let coveredTwo = ReconMath.coverage(entry: retatrutide[0], config: defaultConfig("jonathan", "retatrutide"), onHand: 10)
        let four = ReconMath.ScheduleEntry(id: "st4", person: "jonathan", compound: "retatrutide", dose: 4, doseUnit: "mg", draw: nil, freq: ReconMath.Frequency(type: "weekly"), start: "2026-01-05", weeks: 8)
        let coveredFour = ReconMath.coverage(entry: four, config: defaultConfig("jonathan", "retatrutide"), onHand: 10)
        let coverageGot = js(coveredTwo.weeksCovered) + " / " + js(coveredFour.weeksCovered)
        record("Retatrutide coverage: 2 mg/wk -> 5 weeks; 4 mg/wk -> 2.5 weeks", coveredTwo.weeksCovered == 5 && coveredFour.weeksCovered == 2.5 && coverageGot == "5 / 2.5", "5 / 2.5", coverageGot)

        let victoria = [ReconMath.ScheduleEntry(id: "st2", person: "victoria", compound: "mt2", dose: 250, doseUnit: "mcg", draw: nil, freq: ReconMath.Frequency(type: "daily"), start: "2026-01-05", weeks: 1)]
        let victoriaSimulation = ReconMath.simulateSupply(entries: victoria, config: defaultConfig, onHand: defaultOnHand)
        let flagged = victoriaSimulation.occurrences.filter { $0.status == "noonhand" }.count
        record("Unknown on-hand: every dose flagged \"on-hand not set\"", victoriaSimulation.occurrences.count == 7 && victoriaSimulation.occurrences.allSatisfy { $0.status == "noonhand" }, "7 flagged", "\(flagged) flagged")

        let duplicates = ReconMath.simulateSupply(entries: [
            ReconMath.ScheduleEntry(id: "a", person: "jonathan", compound: "bpc157", dose: 500, doseUnit: "mcg", draw: nil, freq: ReconMath.Frequency(type: "daily"), start: "2026-01-05", weeks: 1),
            ReconMath.ScheduleEntry(id: "b", person: "jonathan", compound: "bpc157", dose: 250, doseUnit: "mcg", draw: nil, freq: ReconMath.Frequency(type: "weekly"), start: "2026-01-07", weeks: 1)
        ], config: defaultConfig, onHand: defaultOnHand)
        record("Same compound twice on one day is warned", duplicates.duplicates.count == 1 && duplicates.duplicates.first?.date == "2026-01-07", "1 dup on 2026-01-07", "\(duplicates.duplicates.count) dup(s)")
        return rows
    }

    private static func defaultConfig(_ person: String, _ key: String) -> ReconMath.VialConfig {
        ReconMath.config(for: ReconMath.defaultCard(person: person, key: key), key: key)
    }

    private static func defaultOnHand(_ person: String, _ key: String) -> Double? {
        ReconMath.onHandDefault[person]?[key]
    }

    private static func js(_ value: Double) -> String {
        ReconMath.jsNumber(value)
    }
}
