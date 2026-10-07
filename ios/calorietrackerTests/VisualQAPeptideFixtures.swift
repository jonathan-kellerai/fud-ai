import Foundation
@testable import calorietracker

/// Peptides log fixtures for Visual QA. Synthetic draws only (BPC-157 50
/// units, Tesamorelin 0.1 mL, MT2 25 units, Glow 10 units, on a U-100 scale
/// in Settings; vials 10 mg BPC-157 in 2 mL, 5 mg Tesamorelin in 0.5 mL,
/// Glow 50/10/10 mg in 2 mL). "Today" is the America/New_York civil date,
/// the same one the Peptides screens use.
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

    /// The one fixed instant every Peptides fixture and screen (Home included)
    /// uses as "now": `referenceNow`, Wed 2026-10-07 09:00 New York, so the
    /// shots don't change from one day to the next.
    static var peptideReferenceDate: Date { referenceNow }

    static var peptideToday: String { PeptideMath.civilDate(peptideReferenceDate) }

    static func peptideBPCVial() -> PeptideVial {
        PeptideVial(
            id: peptideBPCVialID,
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
            compound: "BPC-157",
            now: PeptideMath.date(civil: peptideToday, minutes: 7 * 60 + 30) ?? peptideReferenceDate
        )
        draft.drawText = "50"
        draft.drawUnit = .units
        draft.site = "Abdomen L"
        draft.vialID = peptideBPCVialID
        return draft
    }

    static func seedPeptides(_ store: PeptideLogStore) {
        store.setSyringeScale(.u100)
        store.saveVial(peptideBPCVial())
        store.saveVial(peptideTesaVial())
        store.saveVial(peptideGlowVial())
        store.saveSchedule(PeptideUserSchedule(
            id: "qa-sched-bpc",
            compound: "BPC-157",
            frequency: ReconMath.Frequency(type: "daily"),
            startDate: ReconMath.addDays(peptideToday, -20),
            timeOfDay: 7 * 60 + 30,
            createdAt: Date(timeIntervalSince1970: 1_790_000_000)
        ))
        store.saveSchedule(PeptideUserSchedule(
            id: "qa-sched-mt2",
            compound: "MT2",
            frequency: ReconMath.Frequency(type: "weekdays", days: [1, 3, 5]),
            startDate: ReconMath.addDays(peptideToday, -20),
            createdAt: Date(timeIntervalSince1970: 1_790_000_000)
        ))
        for offset in bpcOffsets {
            seedDose(
                "qa-adm-bpc-\(offset)", store: store, compound: "BPC-157", draw: "50", unit: .units,
                offset: offset, minutes: 7 * 60 + 30, site: offset % 2 == 0 ? "Abdomen L" : "Abdomen R",
                vialID: offset <= 4 ? peptideBPCVialID : nil
            )
        }
        for offset in tesaOffsets {
            seedDose(
                "qa-adm-tesa-\(offset)", store: store, compound: "Tesamorelin", draw: "0.1", unit: .milliliters,
                offset: offset, minutes: 21 * 60 + 30, site: "Thigh L", vialID: peptideTesaVialID
            )
        }
        seedDose("qa-adm-agent-1", store: store, compound: "Tesamorelin", draw: "0.1", unit: .milliliters, offset: 2, minutes: 21 * 60 + 30)
        for offset in mt2Offsets {
            seedDose(
                "qa-adm-mt2-\(offset)", store: store, compound: "MT2", draw: "25", unit: .units,
                offset: offset, minutes: 7 * 60 + 15, site: "Abdomen R"
            )
        }
        for offset in glowOffsets {
            seedDose(
                "qa-adm-glow-\(offset)", store: store, compound: "Glow", draw: "10", unit: .units,
                offset: offset, minutes: 20 * 60, site: "Thigh R", vialID: peptideGlowVialID
            )
        }
        seedDose("qa-adm-tesa-today", store: store, compound: "Tesamorelin", draw: "0.1", unit: .milliliters, offset: 0, minutes: 6 * 60 + 45, site: "Abdomen R", vialID: peptideTesaVialID)
        // Corrected, then voided: the detail screen shows the reason and the trail.
        seedDose(
            peptideVoidedRowID, store: store, compound: "BPC-157", draw: "20", unit: .units,
            offset: 3, minutes: 7 * 60 + 40, site: "Abdomen L", notes: "Same draw as the 7:30 entry."
        )
        if let entry = store.entry(id: peptideVoidedRowID) {
            store.correct(entry, reason: "Typed the wrong draw", changes: PeptideCorrectionChanges(draw: 25), now: peptideDate(offset: 3, minutes: 7 * 60 + 50))
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
        compound: String,
        draw: String,
        unit: PeptideDrawUnit,
        offset: Int,
        minutes: Int,
        site: String = "",
        vialID: String? = nil,
        notes: String = ""
    ) {
        if offset == 0 && skipsTodaysPeptideDoses { return }
        let takenAt = peptideDate(offset: offset, minutes: minutes)
        var draft = PeptideLogDraft.new(compound: compound, now: takenAt)
        draft.drawText = draw
        draft.drawUnit = unit
        draft.site = site
        draft.vialID = vialID
        draft.notes = notes
        store.log(draft, id: id, now: takenAt)
    }
}

extension VisualQAFixtures {
    /// A synthetic peptides file for the import preview: two new vials, one
    /// vial already on the phone, and one dose. Made-up records only.
    static func peptideImportArchive() -> PeptideArchive {
        let json = """
        {"format":"jl-peptides","format_version":1,"exported_at":"2026-10-06T18:00:00-04:00",
         "vials":[
          {"id":"qa-import-vial-1","compound":"Tesamorelin","components":[],
           "concentration_confirmed":false,"status":"active","notes":"labeled_amount: 5 mg\\nsource: QA-SYNTHETIC"},
          {"id":"qa-import-vial-2","compound":"MT2","components":[],
           "concentration_confirmed":false,"status":"active","notes":"source: QA-SYNTHETIC"},
          {"id":"\(peptideBPCVialID)","compound":"BPC-157","components":[],"status":"active"}
         ],
         "schedules":[],
         "entries":[
          {"id":"qa-import-dose-1","compound":"MT2","dose":250,"units":"mcg",
           "datetime":"2026-10-05T07:15:00-04:00","voided":false,"corrections":[]}
         ]}
        """
        return (try? PeptideArchive.decode(Data(json.utf8))) ?? PeptideArchive(exportedAt: nil, vials: [], schedules: [], entries: [])
    }
}
