import Foundation
@testable import calorietracker

/// Peptides log fixtures for Visual QA. Amounts reuse the existing peptide
/// fixtures and Recon Bench presets only (BPC-157 500 mcg, Tesamorelin 1.4 mg
/// LABEL, MT2 250 mcg, Glow 10-unit draw; vials 10 mg BPC-157, 5 mg
/// Tesamorelin, Glow 50/10/10 mg in 2 mL). "Today" is the America/New_York
/// civil date, the same one the Peptides screens use.
extension VisualQAFixtures {
    static var seedsPeptides = false
    static let peptideVoidedRowID = "qa-adm-j-voided"
    static let peptideBPCVialID = "qa-vial-bpc"
    static let peptideTesaVialID = "qa-vial-tesa"
    static let peptideGlowVialID = "qa-vial-glow"

    private static let bpcOffsets = [0, 1, 2, 4, 6, 8, 11, 14, 18]
    private static let tesaOffsets = [1, 3, 5, 9]
    private static let mt2Offsets = [0, 2, 4, 7, 9, 11, 14, 16]
    private static let glowOffsets = [1, 3, 5, 8]

    static var peptideToday: String { PeptideMath.civilDate(Date()) }

    static func peptideISO(offset: Int, minutes: Int) -> String {
        let civil = ReconMath.addDays(peptideToday, -offset)
        let date = PeptideMath.date(civil: civil, minutes: minutes) ?? Date()
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

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
            now: PeptideMath.date(civil: peptideToday, minutes: 7 * 60 + 30) ?? Date()
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
        link(prefix: "qa-crid-bpc-", offsets: bpcOffsets.filter { $0 <= 4 }, person: "jonathan", compound: "BPC-157", vialID: peptideBPCVialID, store: store)
        link(prefix: "qa-crid-tesa-", offsets: tesaOffsets, person: "jonathan", compound: "Tesamorelin", vialID: peptideTesaVialID, store: store)
        link(prefix: "qa-crid-glow-", offsets: glowOffsets, person: "victoria", compound: "Glow", vialID: peptideGlowVialID, store: store)
        // One dose still waiting for the bridge (writes fail in Visual QA).
        var pending = PeptideLogDraft.new(
            person: "jonathan",
            compound: "Tesamorelin",
            now: PeptideMath.date(civil: peptideToday, minutes: 6 * 60 + 45) ?? Date()
        )
        pending.amountText = "1.4"
        pending.units = "mg"
        pending.site = "Abdomen R"
        pending.vialID = peptideTesaVialID
        store.log(pending, clientRequestID: "qa-crid-pending-1")
    }

    private static func link(prefix: String, offsets: [Int], person: String, compound: String, vialID: String, store: PeptideLogStore) {
        for offset in offsets {
            let crid = prefix + String(offset)
            let key = PeptideLogEntry(id: crid, clientRequestID: crid, person: person, compound: compound)
            store.updateLocalDetails(for: key, vialID: vialID, drawnVolume: nil, drawnUnit: nil)
        }
    }

    /// `GET /api/peptides/administrations` for both people, ~3 weeks.
    static func peptideAdministrationsJSON() -> Data {
        var rows: [[String: Any]] = []
        func row(
            id: String,
            person: String?,
            compound: String,
            dose: Double,
            units: String,
            offset: Int,
            minutes: Int,
            via: String,
            crid: String?,
            route: String? = nil,
            status: String = "COMPLETED"
        ) -> [String: Any] {
            var item: [String: Any] = [
                "id": id,
                "datetime": peptideISO(offset: offset, minutes: minutes),
                "compound": compound,
                "dose": dose,
                "units": units,
                "status": status,
                "recorded_via": via,
                "voided": false,
                "dose_deviates_from_planned": false,
                "correction_history": [Any](),
                "created_at": peptideISO(offset: offset, minutes: minutes),
                "updated_at": peptideISO(offset: offset, minutes: minutes),
                "volume": NSNull(),
                "volume_units": NSNull(),
                "volume_basis": "NOT_CALCULATED",
            ]
            let null: Any = NSNull()
            item["person"] = person.map { $0 as Any } ?? null
            item["client_request_id"] = crid.map { $0 as Any } ?? null
            item["route"] = route.map { $0 as Any } ?? null
            return item
        }
        for offset in bpcOffsets {
            rows.append(row(
                id: "qa-adm-bpc-\(offset)", person: offset % 3 == 0 ? nil : "jonathan", compound: "BPC-157",
                dose: 500, units: "mcg", offset: offset, minutes: 7 * 60 + 30, via: "app",
                crid: "qa-crid-bpc-\(offset)", route: offset % 2 == 0 ? "Abdomen L" : "Abdomen R"
            ))
        }
        for offset in tesaOffsets {
            rows.append(row(
                id: "qa-adm-tesa-\(offset)", person: "jonathan", compound: "Tesamorelin",
                dose: 1.4, units: "mg", offset: offset, minutes: 21 * 60 + 30, via: "app",
                crid: "qa-crid-tesa-\(offset)", route: "Thigh L"
            ))
        }
        var agent = row(
            id: "qa-adm-agent-1", person: "jonathan", compound: "Tesamorelin",
            dose: 1.4, units: "mg", offset: 2, minutes: 21 * 60 + 30, via: "peptide-agent", crid: nil
        )
        agent["schedule_id"] = "qa-schedule-1"
        agent["planned_id"] = "qa-planned-0"
        agent["badges"] = ["LABEL"]
        rows.append(agent)
        var planned = row(
            id: "qa-planned-1", person: "jonathan", compound: "Tesamorelin",
            dose: 1.4, units: "mg", offset: 0, minutes: 21 * 60, via: "peptide-agent", crid: nil, status: "PLANNED"
        )
        planned["schedule_id"] = "qa-schedule-1"
        planned["completed_id"] = NSNull()
        rows.append(planned)
        var voided = row(
            id: peptideVoidedRowID, person: "jonathan", compound: "BPC-157",
            dose: 500, units: "mcg", offset: 3, minutes: 7 * 60 + 40, via: "app",
            crid: "qa-crid-bpc-void", route: "Abdomen L"
        )
        voided["voided"] = true
        voided["void_reason"] = "Logged twice by mistake"
        voided["notes"] = "Same dose as the 7:30 entry."
        voided["correction_history"] = [
            [
                "at": peptideISO(offset: 3, minutes: 7 * 60 + 50),
                "field": "dose",
                "old": 250,
                "new": 500,
                "reason": "Typed the wrong amount",
                "by": "app",
            ] as [String: Any],
            [
                "at": peptideISO(offset: 3, minutes: 8 * 60 + 5),
                "field": "voided",
                "old": false,
                "new": true,
                "reason": "Logged twice by mistake",
                "by": "app",
            ] as [String: Any],
        ]
        rows.append(voided)
        for offset in mt2Offsets {
            rows.append(row(
                id: "qa-adm-mt2-\(offset)", person: "victoria", compound: "MT2",
                dose: 250, units: "mcg", offset: offset, minutes: 7 * 60 + 15, via: "app",
                crid: "qa-crid-mt2-\(offset)", route: "Abdomen R"
            ))
        }
        for offset in glowOffsets {
            rows.append(row(
                id: "qa-adm-glow-\(offset)", person: "victoria", compound: "Glow",
                dose: 10, units: "units", offset: offset, minutes: 20 * 60, via: "app",
                crid: "qa-crid-glow-\(offset)", route: "Thigh R"
            ))
        }
        let body: [String: Any] = [
            "from": ReconMath.addDays(peptideToday, -392),
            "to": ReconMath.addDays(peptideToday, 7),
            "timezone": "America/New_York",
            "administrations": rows,
        ]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }
}

/// Reads go to the stubbed bridge; writes fail like a phone with no signal,
/// so queued doses stay pending and nothing is posted.
@MainActor
final class VisualQAPeptideClient: PeptideBridgeClient {
    private let reads = NeonPeptideBridgeClient()

    nonisolated deinit {}

    func fetchAdministrations(from: String, to: String) async throws -> [PeptideAdministration] {
        try await reads.fetchAdministrations(from: from, to: to)
    }

    func fetchToday(date: String) async throws -> PeptideTodayResponse {
        try await reads.fetchToday(date: date)
    }

    func fetchInventory() async throws -> [PeptideInventoryItem] {
        try await reads.fetchInventory()
    }

    func create(_ payload: PeptideCreatePayload) async throws -> PeptideAdministration {
        throw URLError(.notConnectedToInternet)
    }

    func correct(rowID: String, reason: String, changes: PeptideCorrectionChanges) async throws -> PeptideAdministration {
        throw URLError(.notConnectedToInternet)
    }

    func voidRow(rowID: String, reason: String) async throws -> PeptideAdministration {
        throw URLError(.notConnectedToInternet)
    }
}
