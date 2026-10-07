import Foundation
import Testing
@testable import calorietracker

/// Peptides arithmetic: only from the user's own vial numbers and the syringe
/// scale they recorded, never IU <-> mass, never a suggested amount.
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
        compound: String = "BPC-157",
        dose: Double? = 500,
        units: String? = "mcg",
        civil: String = "2026-09-20",
        hour: Int = 9,
        vialID: String? = nil,
        drawn: Double? = nil,
        drawnUnit: PeptideDrawUnit? = nil,
        scale: PeptideSyringeScale? = nil,
        voided: Bool = false
    ) -> PeptideLogEntry {
        PeptideLogEntry(
            id: id,
            compound: compound,
            dose: dose,
            units: units,
            date: PeptideMath.date(civil: civil, minutes: hour * 60),
            voided: voided,
            vialID: vialID,
            drawnVolume: drawn,
            drawnUnit: drawnUnit,
            syringeScaleAtSave: scale
        )
    }

    private func schedule(
        compound: String = "BPC-157",
        frequency: ReconMath.Frequency,
        start: String = "2026-09-01",
        end: String? = nil
    ) -> PeptideUserSchedule {
        PeptideUserSchedule(id: "s-" + compound, compound: compound, frequency: frequency, startDate: start, endDate: end)
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

    @Test func compoundOptionsAreOnlyTheUsersOwn() {
        #expect(PeptideMath.compoundOptions(vialCompounds: [], loggedCompounds: []).isEmpty)
        #expect(PeptideMath.compoundOptions(vialCompounds: ["MT2"], loggedCompounds: ["BPC-157"]) == ["MT2", "BPC-157"])
    }

    @Test func loggedCompoundsAreAddedOncePerKey() {
        let options = PeptideMath.compoundOptions(
            vialCompounds: ["BPC-157", "MT2"],
            loggedCompounds: ["bpc-157", "Melanotan II", "Ipamorelin", "ipamorelin"]
        )
        #expect(Array(options.prefix(2)) == ["BPC-157", "MT2"])
        #expect(options.contains("Ipamorelin"))
        #expect(!options.contains("ipamorelin"))
        #expect(options.filter { PeptideMath.compoundKey($0) == "mt2" }.count == 1)
        #expect(options.filter { PeptideMath.compoundKey($0) == "bpc157" }.count == 1)
    }

    @Test func logDraftsNeverPrefillADraw() {
        let names = PeptideMath.compoundOptions(vialCompounds: ["MT2"], loggedCompounds: ["BPC-157", "Tesamorelin"]) + [""]
        for name in names {
            let draft = PeptideLogDraft.new(compound: name)
            #expect(draft.draw == nil, "\(name)")
            #expect(draft.drawText.isEmpty)
            #expect(draft.drawUnit == nil)
            #expect(draft.scaleOverride == nil)
            #expect(PeptideMath.validate(draft)[.draw] != nil)
            #expect(PeptideMath.validate(draft)[.unit] != nil)
        }
    }

    @Test func validationNeedsAPositiveDrawAndAUnit() {
        var draft = PeptideLogDraft.new(compound: "BPC-157")
        draft.drawText = "0"
        draft.drawUnit = .units
        #expect(PeptideMath.validate(draft)[.draw] != nil)
        draft.drawText = "abc"
        #expect(PeptideMath.validate(draft)[.draw] != nil)
        draft.drawText = "50"
        #expect(PeptideMath.validate(draft).isEmpty)
        // A typed draw needs its unit picked; none is preselected.
        draft.drawUnit = nil
        #expect(PeptideMath.validate(draft)[.unit] != nil)
        draft.drawUnit = .milliliters
        draft.drawText = "0,1"
        #expect(PeptideMath.validate(draft).isEmpty)
        #expect(draft.draw == 0.1)
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
        #expect(PeptideMath.drawnML(dose: 500, units: "mcg", drawnVolume: nil, drawnUnit: nil, scale: nil, vial: bpc) == 0.1)
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
        #expect(PeptideMath.drawnML(dose: 500, units: "IU", drawnVolume: nil, drawnUnit: nil, scale: nil, vial: hcg) == 0.1)
        let remaining = PeptideMath.remaining(vial: hcg, entries: [entry("h", compound: "HCG", dose: 500, units: "IU", vialID: "v1")])
        #expect(remaining.remainingML == 0.9)
    }

    @Test func neverConvertsBetweenIUAndMass() {
        let mass = vial()
        let iu = vial(compound: "HCG", amount: 5000, unit: "IU", diluent: 1)
        #expect(PeptideMath.drawnML(dose: 500, units: "IU", drawnVolume: nil, drawnUnit: nil, scale: nil, vial: mass) == nil)
        #expect(PeptideMath.drawnML(dose: 1, units: "mg", drawnVolume: nil, drawnUnit: nil, scale: nil, vial: iu) == nil)
        let remaining = PeptideMath.remaining(vial: mass, entries: [entry("x", dose: 500, units: "IU", vialID: "v1")])
        #expect(!remaining.calculable)
        #expect(remaining.remainingML == nil)
    }

    @Test func blendNeedsADrawWithItsScale() {
        let glow = glowVial()
        let byUnits = entry("g1", compound: "Glow", dose: nil, units: nil, vialID: "glow", drawn: 10, drawnUnit: .units, scale: .u100)
        let byML = entry("g2", compound: "Glow", dose: nil, units: nil, civil: "2026-09-21", vialID: "glow", drawn: 0.1, drawnUnit: .milliliters)
        let ok = PeptideMath.remaining(vial: glow, entries: [byUnits, byML])
        #expect(ok.calculable)
        #expect(ok.remainingML == 1.8)
        // 20 units on a U-50 syringe is 0.4 mL.
        let onU50 = entry("g3", compound: "Glow", dose: nil, units: nil, civil: "2026-09-22", vialID: "glow", drawn: 20, drawnUnit: .units, scale: .u50)
        #expect(PeptideMath.remaining(vial: glow, entries: [onU50]).remainingML == 1.6)
        // A units draw with no recorded scale is never assumed to be U-100.
        let noScale = entry("g4", compound: "Glow", dose: nil, units: nil, civil: "2026-09-23", vialID: "glow", drawn: 10, drawnUnit: .units)
        let unknown = PeptideMath.remaining(vial: glow, entries: [byUnits, noScale])
        #expect(!unknown.calculable)
        #expect(unknown.reason?.contains("no syringe scale") == true)
        let mcgOnly = entry("g5", compound: "Glow", dose: 500, units: "mcg", civil: "2026-09-24", vialID: "glow")
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

    @Test func adherenceMatchesCompoundKey() {
        let mt2 = schedule(compound: "MT2", frequency: ReconMath.Frequency(type: "daily"), start: "2026-09-20")
        let entries = [
            entry("a", compound: "Melanotan II", civil: "2026-09-20"),
            entry("b", compound: "TB-500", civil: "2026-09-21"),
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

    @Test func perWeekCountsEveryAdministrationCappedPerWeek() {
        // 3× per week from Monday 2026-09-07. Today is Wednesday 2026-09-30.
        let threeAWeek = schedule(frequency: ReconMath.Frequency(type: "perWeek", n: 3), start: "2026-09-07")
        let entries = [
            entry("a", civil: "2026-09-15", hour: 7),
            entry("b", civil: "2026-09-15", hour: 20),
            entry("c", civil: "2026-09-17"),
            entry("d", civil: "2026-09-17", hour: 21),
            entry("e", civil: "2026-09-22"),
            entry("f", civil: "2026-09-28", hour: 7),
            entry("g", civil: "2026-09-28", hour: 20),
            entry("x", civil: "2026-09-29", voided: true),
        ]
        // Two on one day count as two; four in a week are capped at three.
        #expect(PeptideMath.perWeekCount(threeAWeek, entries: entries, weekStart: "2026-09-14", from: "2026-09-07", to: "2026-09-30") == 3)
        let result = PeptideMath.adherence(threeAWeek, entries: entries, from: "2026-09-14", to: "2026-09-30", today: "2026-09-30")
        // Week of 14th: 3 of 3. Week of 21st: 1 of 3. This week: only what's logged (2).
        #expect(result.due == 8)
        #expect(result.taken == 6)
        #expect(result.missedDates == ["2026-09-21"])
        #expect(result.todayDue)
        #expect(!result.todayTaken)
        // The due list uses the same counter.
        let due = PeptideMath.dueItems(date: "2026-09-30", schedules: [threeAWeek], entries: entries)
        #expect(due.first?.weekCount == 2)
        #expect(due.first?.taken == false)
    }

    @Test func perWeekPartialBoundaryWeeks() {
        let threeAWeek = schedule(frequency: ReconMath.Frequency(type: "perWeek", n: 3), start: "2026-09-07")
        let entries = [
            entry("a", civil: "2026-09-15"),
            entry("b", civil: "2026-09-17"),
            entry("c", civil: "2026-09-20"),
            entry("d", civil: "2026-09-22"),
        ]
        // Window starts Saturday 19th: only Sat + Sun of that week are in it,
        // so it is due 2 and only the Sunday dose counts.
        #expect(PeptideMath.perWeekDue(threeAWeek, weekStart: "2026-09-14", from: "2026-09-19", to: "2026-09-30") == 2)
        let result = PeptideMath.adherence(threeAWeek, entries: entries, from: "2026-09-19", to: "2026-09-27", today: "2026-09-30")
        #expect(result.due == 5)
        #expect(result.taken == 2)
        #expect(result.missedDates == ["2026-09-14", "2026-09-21"])

        // A schedule starting Thursday 24th: doses before the start don't count.
        let lateStart = schedule(frequency: ReconMath.Frequency(type: "perWeek", n: 3), start: "2026-09-24")
        #expect(PeptideMath.perWeekCount(lateStart, entries: entries, weekStart: "2026-09-21", from: "2026-09-01", to: "2026-09-30") == 0)
        #expect(PeptideMath.perWeekDue(lateStart, weekStart: "2026-09-21", from: "2026-09-01", to: "2026-09-30") == 3)
        // Ends Tuesday 15th: only Mon + Tue of that week.
        let ended = schedule(frequency: ReconMath.Frequency(type: "perWeek", n: 3), start: "2026-09-07", end: "2026-09-15")
        #expect(PeptideMath.perWeekDue(ended, weekStart: "2026-09-14", from: "2026-09-01", to: "2026-09-30") == 2)
        #expect(PeptideMath.perWeekCount(ended, entries: entries, weekStart: "2026-09-14", from: "2026-09-01", to: "2026-09-30") == 1)
    }

    @Test func streakIsIndependentOfTheReportWindow() {
        let daily = schedule(frequency: ReconMath.Frequency(type: "daily"), start: "2026-01-01")
        var entries: [PeptideLogEntry] = []
        var day = "2026-08-01"
        while day <= "2026-09-29" {
            entries.append(entry("d-" + day, civil: day))
            day = ReconMath.addDays(day, 1)
        }
        // 60 days logged in a row; today (30th) not yet logged doesn't break it.
        let week = PeptideMath.adherence(daily, entries: entries, from: "2026-09-24", to: "2026-09-30", today: "2026-09-30")
        #expect(week.streak == 60)
        #expect(PeptideMath.currentStreak(daily, entries: entries, today: "2026-09-30") == 60)

        let twiceAWeek = schedule(frequency: ReconMath.Frequency(type: "perWeek", n: 2), start: "2026-08-31")
        let weekly = ["2026-08-31", "2026-09-02", "2026-09-07", "2026-09-07", "2026-09-15", "2026-09-18", "2026-09-21", "2026-09-26", "2026-09-29"]
            .enumerated().map { entry("w\($0.offset)", civil: $0.element, hour: 7 + $0.offset) }
        // Four full weeks; the current week (1 of 2 so far) neither adds nor breaks.
        let recent = PeptideMath.adherence(twiceAWeek, entries: weekly, from: "2026-09-24", to: "2026-09-30", today: "2026-09-30")
        #expect(recent.streak == 4)
    }

    // MARK: Summaries

    @Test func dailySummaryNeverSumsAcrossUnits() {
        let entries = [
            entry("1", compound: "Tesamorelin", dose: 1, units: "mg", hour: 7),
            entry("2", compound: "Tesamorelin", dose: 400, units: "mcg", hour: 9),
            entry("3", compound: "tesamorelin", dose: 0.5, units: "mg", hour: 20),
            entry("4", compound: "Tesamorelin", dose: 9, units: "mg", hour: 21, voided: true),
            entry("5", compound: "MT2", dose: 250, units: "mcg", civil: "2026-09-21"),
        ]
        let summary = PeptideMath.dailySummary(entries: entries, date: "2026-09-20")
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
        let all = PeptideMath.weeklyCounts(entries: entries, compound: nil, weeks: 3, today: "2026-09-30")
        #expect(all.map(\.weekStart) == ["2026-09-14", "2026-09-21", "2026-09-28"])
        #expect(all.map(\.count) == [0, 2, 2])
        let bpc = PeptideMath.weeklyCounts(entries: entries, compound: "bpc 157", weeks: 3, today: "2026-09-30")
        #expect(bpc.map(\.count) == [0, 2, 1])
    }

    @Test func civilDatesUseNewYork() {
        // 03:30 UTC on Sep 21 is still Sep 20 in New York.
        let date = PeptideMath.parseISO8601("2026-09-21T03:30:00Z")
        #expect(date.map(PeptideMath.civilDate) == "2026-09-20")
        #expect(PeptideMath.iso8601NewYork(date ?? Date()).hasSuffix("-04:00"))
    }
}
