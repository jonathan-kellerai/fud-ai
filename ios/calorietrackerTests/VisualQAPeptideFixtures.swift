import Foundation
@testable import calorietracker

/// Peptides log fixtures for Visual QA. Amounts reuse the existing peptide
/// fixtures and Recon Bench presets only (BPC-157 500 mcg, Tesamorelin 1.4 mg
/// LABEL, MT2 250 mcg, Glow 10-unit draw; vials 10 mg BPC-157, 5 mg
/// Tesamorelin, Glow 50/10/10 mg in 2 mL). "Today" is the America/New_York
/// civil date, the same one the Peptides screens use.
extension VisualQAFixtures {
    static var seedsPeptides = false
    /// Seed everything except doses taken today (Home card with only due items and low stock).
    static var skipsTodaysPeptideDoses = false
    static let peptideVoidedRowID = "qa-adm-j-voided"
    static let peptideBPCVialID = "qa-vial-bpc"
    static let peptideTesaVialID = "qa-vial-tesa"
    static let peptideGlowVialID = "qa-vial-glow"

    private static let bpcOffsets = [0, 1, 2, 4, 6, 8, 11, 14, 18]
    private static let tesaOffsets = [1, 3, 5, 9]
    private static let mt2Offsets = [0, 2, 4, 7, 9, 11, 14, 16]
    private static let glowOffsets = [1, 3, 5, 8]

    /// The one fixed instant every Peptides fixture and screen uses as "now":
    /// 9:00 AM New York time on the day the run starts, captured once (same
    /// convention as `trainingDate`: today's date, a fixed time of day).
    static let peptideReferenceDate: Date = {
        let civil = PeptideMath.civilDate(.now)
        return PeptideMath.date(civil: civil, minutes: 9 * 60) ?? .now
    }()

    static var peptideToday: String { PeptideMath.civilDate(peptideReferenceDate) }

    static func peptideBPCVial() -> PeptideVial {
        PeptideVial(
            id: peptideBPCVialID,
            person: "jonathan",
            compound: "BPC-157",
            components: [PeptideVialComponent(id: "qa-c-bpc", name: "BPC-157", amount: 10, unit: "mg")],
            diluentML: 2,
            mixedOn: ReconMath.addDays(peptideToday, -5),
            concentrationConfirmed: true,
            createdAt: Date(timeIntervalSince1970: 1_790_000_000)
        )
    }

    static func peptideTesaVial() -> PeptideVial {
        PeptideVial(
            id: peptideTesaVialID,
            person: "jonathan",
            compound: "Tesamorelin",
            components: [PeptideVialComponent(id: "qa-c-tesa", name: "Tesamorelin", amount: 5, unit: "mg")],
            diluentML: 0.5,
            mixedOn: ReconMath.addDays(peptideToday, -9),
            concentrationConfirmed: false,
            createdAt: Date(timeIntervalSince1970: 1_790_000_000)
        )
    }

    static func peptideGlowVial() -> PeptideVial {
        PeptideVial(
            id: peptideGlowVialID,
            person: "victoria",
            compound: "Glow",
            isBlend: true,
            components: [
                PeptideVialComponent(id: "qa-c-ghk", name: "GHK-Cu", amount: 50, unit: "mg"),
                PeptideVialComponent(id: "qa-c-gbpc", name: "BPC-157", amount: 10, unit: "mg"),
                PeptideVialComponent(id: "qa-c-gtb", name: "TB-500", amount: 10, unit: "mg"),
            ],
            diluentML: 2,
            mixedOn: ReconMath.addDays(peptideToday, -10),
            concentrationConfirmed: true,
            lowStockThresholdML: 1.6,
            notes: "Reorder before the next one runs out.",
            createdAt: Date(timeIntervalSince1970: 1_790_000_000)
        )
    }

    /// Values the Visual QA test "typed" for the confirm step.
    static func peptideReviewDraft() -> PeptideLogDraft {
        var draft = PeptideLogDraft.new(
            person: "jonathan",
            compound: "BPC-157",
            now: PeptideMath.date(civil: peptideToday, minutes: 7 * 60 + 30) ?? peptideReferenceDate
        )
        draft.amountText = "500"
        draft.units = "mcg"
        draft.site = "Abdomen L"
        draft.vialID = peptideBPCVialID
        return draft
    }

    static func seedPeptides(_ store: PeptideLogStore) {
        store.saveVial(peptideBPCVial())
        store.saveVial(peptideTesaVial())
        store.saveVial(peptideGlowVial())
        store.saveSchedule(PeptideUserSchedule(
            id: "qa-sched-bpc",
            person: "jonathan",
            compound: "BPC-157",
            frequency: ReconMath.Frequency(type: "daily"),
            startDate: ReconMath.addDays(peptideToday, -20),
            timeOfDay: 7 * 60 + 30,
            createdAt: Date(timeIntervalSince1970: 1_790_000_000)
        ))
        store.saveSchedule(PeptideUserSchedule(
            id: "qa-sched-mt2",
            person: "victoria",
            compound: "MT2",
            frequency: ReconMath.Frequency(type: "weekdays", days: [1, 3, 5]),
            startDate: ReconMath.addDays(peptideToday, -20),
            createdAt: Date(timeIntervalSince1970: 1_790_000_000)
        ))
        for offset in bpcOffsets {
            seedDose(
                "qa-adm-bpc-\(offset)", store: store, person: "jonathan", compound: "BPC-157", amount: "500", units: "mcg",
                offset: offset, minutes: 7 * 60 + 30, site: offset % 2 == 0 ? "Abdomen L" : "Abdomen R",
                vialID: offset <= 4 ? peptideBPCVialID : nil
            )
        }
        for offset in tesaOffsets {
            seedDose(
                "qa-adm-tesa-\(offset)", store: store, person: "jonathan", compound: "Tesamorelin", amount: "1.4", units: "mg",
                offset: offset, minutes: 21 * 60 + 30, site: "Thigh L", vialID: peptideTesaVialID
            )
        }
        seedDose("qa-adm-agent-1", store: store, person: "jonathan", compound: "Tesamorelin", amount: "1.4", units: "mg", offset: 2, minutes: 21 * 60 + 30)
        for offset in mt2Offsets {
            seedDose(
                "qa-adm-mt2-\(offset)", store: store, person: "victoria", compound: "MT2", amount: "250", units: "mcg",
                offset: offset, minutes: 7 * 60 + 15, site: "Abdomen R"
            )
        }
        for offset in glowOffsets {
            seedDose(
                "qa-adm-glow-\(offset)", store: store, person: "victoria", compound: "Glow", amount: "10", units: "units",
                offset: offset, minutes: 20 * 60, site: "Thigh R", vialID: peptideGlowVialID
            )
        }
        seedDose("qa-adm-tesa-today", store: store, person: "jonathan", compound: "Tesamorelin", amount: "1.4", units: "mg", offset: 0, minutes: 6 * 60 + 45, site: "Abdomen R", vialID: peptideTesaVialID)
        // Corrected, then voided: the detail screen shows the reason and the trail.
        seedDose(
            peptideVoidedRowID, store: store, person: "jonathan", compound: "BPC-157", amount: "250", units: "mcg",
            offset: 3, minutes: 7 * 60 + 40, site: "Abdomen L", notes: "Same dose as the 7:30 entry."
        )
        if let entry = store.entry(id: peptideVoidedRowID) {
            store.correct(entry, reason: "Typed the wrong amount", changes: PeptideCorrectionChanges(dose: 500), now: peptideDate(offset: 3, minutes: 7 * 60 + 50))
        }
        if let entry = store.entry(id: peptideVoidedRowID) {
            store.void(entry, reason: "Logged twice by mistake", now: peptideDate(offset: 3, minutes: 8 * 60 + 5))
        }
    }

    static func peptideDate(offset: Int, minutes: Int) -> Date {
        PeptideMath.date(civil: ReconMath.addDays(peptideToday, -offset), minutes: minutes) ?? peptideReferenceDate
    }

    private static func seedDose(
        _ id: String,
        store: PeptideLogStore,
        person: String,
        compound: String,
        amount: String,
        units: String,
        offset: Int,
        minutes: Int,
        site: String = "",
        vialID: String? = nil,
        notes: String = ""
    ) {
        if offset == 0 && skipsTodaysPeptideDoses { return }
        let takenAt = peptideDate(offset: offset, minutes: minutes)
        var draft = PeptideLogDraft.new(person: person, compound: compound, now: takenAt)
        draft.amountText = amount
        draft.units = units
        draft.site = site
        draft.vialID = vialID
        draft.notes = notes
        store.log(draft, id: id, now: takenAt)
    }
}
