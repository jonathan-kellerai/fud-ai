//
//  PeptideLegacyLog.swift
//  calorietracker
//
//  The version-1 peptide log: cached bridge rows plus queued writes and
//  device-only details, merged into what the Peptides screens list.
//

import Foundation

enum PeptideLegacyLog {
    /// Bridge rows merged with queued creates, oldest first.
    static func entries(
        rows: [String: PeptideAdministration],
        pendingOps: [PeptidePendingOp],
        meta: [String: PeptideLocalMeta]
    ) -> [PeptideLogEntry] {
        var opsByRow: [String: [PeptidePendingOp]] = [:]
        for op in pendingOps where op.kind != .create {
            if let rowID = op.rowID { opsByRow[rowID, default: []].append(op) }
        }
        // Creates still queued although the bridge row is known (a removal or
        // edit waiting to be queued, or one that couldn't be sent).
        var createOps: [String: PeptidePendingOp] = [:]
        for op in pendingOps where op.kind == .create {
            if let crid = op.create?.clientRequestID { createOps[crid.lowercased()] = op }
        }
        var synced = Set<String>()
        var result: [PeptideLogEntry] = []
        for row in rows.values {
            if let crid = row.clientRequestID { synced.insert(crid.lowercased()) }
            var entry = makeEntry(row, meta: meta)
            for op in opsByRow[row.id] ?? [] {
                apply(op, to: &entry)
            }
            if let crid = row.clientRequestID, let op = createOps[crid.lowercased()],
               op.cancelReason == nil || !entry.voided {
                if op.cancelReason != nil {
                    // Removed by the user before the create's answer arrived.
                    entry.voided = true
                    entry.voidReason = op.cancelReason
                }
                entry.pendingOpID = op.id
                entry.syncState = op.failed ? .failed(op.lastError ?? "The bridge didn't accept this change.") : .pending
            }
            result.append(entry)
        }
        for op in pendingOps where op.kind == .create {
            guard let payload = op.create, !synced.contains(payload.clientRequestID.lowercased()) else { continue }
            result.append(makePendingEntry(op, payload: payload, rows: rows, meta: meta))
        }
        result.sort { lhs, rhs in
            let left = lhs.date ?? .distantPast
            let right = rhs.date ?? .distantPast
            if left != right { return left < right }
            return lhs.id < rhs.id
        }
        return result
    }

    private static func makeEntry(_ row: PeptideAdministration, meta: [String: PeptideLocalMeta]) -> PeptideLogEntry {
        let status = row.status.uppercased()
        let syncState: PeptideSyncState
        if row.recordedVia == "peptide-agent" || status == "PLANNED" {
            syncState = .readOnlyAgent
        } else if row.recordedVia != "app" {
            // Missing or unknown origin: read-only.
            syncState = .readOnly
        } else {
            syncState = .synced
        }
        let local = meta[row.clientRequestID?.lowercased() ?? row.id] ?? meta[row.id]
        return PeptideLogEntry(
            id: row.id,
            rowID: row.id,
            clientRequestID: row.clientRequestID,
            person: PeptidePerson.normalized(row.person),
            compound: row.compound,
            dose: row.dose,
            units: row.units,
            date: PeptideMath.parseISO8601(row.datetime),
            datetimeRaw: row.datetime,
            route: row.route,
            notes: row.notes,
            sourceVial: row.sourceVial,
            status: status,
            plannedID: row.plannedId,
            scheduleID: row.scheduleId,
            completedID: row.completedId,
            voided: row.voided,
            voidReason: row.voidReason,
            recordedVia: row.recordedVia,
            corrections: row.correctionHistory,
            badges: row.badges,
            vialID: local?.vialID,
            drawnVolume: local?.drawnVolume,
            drawnUnit: local?.drawnUnit,
            syncState: syncState,
            pendingOpID: nil,
            createdAt: row.createdAt
        )
    }

    private static func makePendingEntry(
        _ op: PeptidePendingOp,
        payload: PeptideCreatePayload,
        rows: [String: PeptideAdministration],
        meta: [String: PeptideLocalMeta]
    ) -> PeptideLogEntry {
        let planned = payload.plannedID.flatMap { rows[$0] }
        let local = meta[payload.clientRequestID]
        let state: PeptideSyncState = op.failed ? .failed(op.lastError ?? "The bridge didn't accept this entry.") : .pending
        return PeptideLogEntry(
            id: "pending-" + payload.clientRequestID,
            rowID: nil,
            clientRequestID: payload.clientRequestID,
            person: PeptidePerson.normalized(payload.person ?? planned?.person),
            compound: payload.compound ?? planned?.compound ?? "Planned dose",
            dose: payload.dose ?? planned?.dose,
            units: payload.units ?? planned?.units,
            date: PeptideMath.parseISO8601(payload.datetime),
            datetimeRaw: payload.datetime,
            route: payload.route,
            notes: payload.notes,
            sourceVial: payload.sourceVial,
            status: "COMPLETED",
            plannedID: payload.plannedID,
            scheduleID: planned?.scheduleId,
            completedID: nil,
            voided: op.cancelReason != nil,
            voidReason: op.cancelReason,
            recordedVia: "app",
            corrections: [],
            badges: [],
            vialID: local?.vialID,
            drawnVolume: local?.drawnVolume,
            drawnUnit: local?.drawnUnit,
            syncState: state,
            pendingOpID: op.id,
            createdAt: nil
        )
    }

    private static func apply(_ op: PeptidePendingOp, to entry: inout PeptideLogEntry) {
        switch op.kind {
        case .create:
            return
        case .correct:
            guard let changes = op.changes else { return }
            var date = entry.date
            if let datetime = changes.datetime { date = PeptideMath.parseISO8601(datetime) }
            entry = PeptideLogEntry(
                id: entry.id,
                rowID: entry.rowID,
                clientRequestID: entry.clientRequestID,
                person: entry.person,
                compound: changes.compound ?? entry.compound,
                dose: changes.dose ?? entry.dose,
                units: changes.units ?? entry.units,
                date: date,
                datetimeRaw: changes.datetime ?? entry.datetimeRaw,
                route: changes.route ?? entry.route,
                notes: changes.notes ?? entry.notes,
                sourceVial: changes.sourceVial ?? entry.sourceVial,
                status: entry.status,
                plannedID: entry.plannedID,
                scheduleID: entry.scheduleID,
                completedID: entry.completedID,
                voided: entry.voided,
                voidReason: entry.voidReason,
                recordedVia: entry.recordedVia,
                corrections: entry.corrections,
                badges: entry.badges,
                vialID: entry.vialID,
                drawnVolume: entry.drawnVolume,
                drawnUnit: entry.drawnUnit,
                syncState: entry.syncState,
                pendingOpID: entry.pendingOpID,
                createdAt: entry.createdAt
            )
        case .void:
            entry.voided = true
            entry.voidReason = op.reason
        }
        entry.pendingOpID = op.id
        entry.syncState = op.failed ? .failed(op.lastError ?? "The bridge didn't accept this change.") : .pending
    }

    // MARK: Saved file

    struct Snapshot: Codable {
        var version: Int
        var rows: [PeptideAdministration]
        var pendingOps: [PeptidePendingOp]
        var meta: [PeptideLocalMeta]
        var vials: [PeptideVial]
        var schedules: [PeptideUserSchedule]
        var lastSync: Date?
        var historyComplete: Bool

        enum CodingKeys: String, CodingKey {
            case version, rows, pendingOps, meta, vials, schedules, lastSync, historyComplete
        }

        init(
            version: Int,
            rows: [PeptideAdministration],
            pendingOps: [PeptidePendingOp],
            meta: [PeptideLocalMeta],
            vials: [PeptideVial],
            schedules: [PeptideUserSchedule],
            lastSync: Date?,
            historyComplete: Bool
        ) {
            self.version = version
            self.rows = rows
            self.pendingOps = pendingOps
            self.meta = meta
            self.vials = vials
            self.schedules = schedules
            self.lastSync = lastSync
            self.historyComplete = historyComplete
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = (try? container.decode(Int.self, forKey: .version)) ?? 1
            let lossyRows = (try? container.decode([PeptideLossy<PeptideAdministration>].self, forKey: .rows)) ?? []
            rows = lossyRows.compactMap(\.value)
            let lossyOps = (try? container.decode([PeptideLossy<PeptidePendingOp>].self, forKey: .pendingOps)) ?? []
            pendingOps = lossyOps.compactMap(\.value)
            let lossyMeta = (try? container.decode([PeptideLossy<PeptideLocalMeta>].self, forKey: .meta)) ?? []
            meta = lossyMeta.compactMap(\.value)
            let lossyVials = (try? container.decode([PeptideLossy<PeptideVial>].self, forKey: .vials)) ?? []
            vials = lossyVials.compactMap(\.value)
            let lossySchedules = (try? container.decode([PeptideLossy<PeptideUserSchedule>].self, forKey: .schedules)) ?? []
            schedules = lossySchedules.compactMap(\.value)
            lastSync = try? container.decodeIfPresent(Date.self, forKey: .lastSync)
            // Older saves have no flag: not complete until the next full refresh.
            let savedComplete = (try? container.decodeIfPresent(Bool.self, forKey: .historyComplete)) ?? false
            // A saved row or local link that no longer decodes may have been a dose from a vial,
            // so the cache can't vouch for completeness until the next full refresh.
            let droppedSomething = rows.count != lossyRows.count || meta.count != lossyMeta.count
            historyComplete = savedComplete && !droppedSomething
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(version, forKey: .version)
            try container.encode(rows, forKey: .rows)
            try container.encode(pendingOps, forKey: .pendingOps)
            try container.encode(meta, forKey: .meta)
            try container.encode(vials, forKey: .vials)
            try container.encode(schedules, forKey: .schedules)
            try container.encodeIfPresent(lastSync, forKey: .lastSync)
            try container.encode(historyComplete, forKey: .historyComplete)
        }
    }
}

// MARK: - Row cache

extension PeptideAdministration: Encodable {
    init(
        id: String,
        datetime: String,
        compound: String,
        dose: Double? = nil,
        units: String? = nil,
        volume: Double? = nil,
        volumeUnits: String? = nil,
        route: String? = nil,
        notes: String? = nil,
        status: String = "COMPLETED",
        plannedId: String? = nil,
        scheduleId: String? = nil,
        completedId: String? = nil,
        sourceVial: String? = nil,
        voided: Bool = false,
        doseDeviatesFromPlanned: Bool = false,
        volumeBasis: String? = nil,
        calcGate: String? = nil,
        concentrationBasis: String? = nil,
        badges: [String] = [],
        person: String? = nil,
        recordedVia: String? = nil,
        voidReason: String? = nil,
        correctionHistory: [PeptideCorrection] = [],
        createdAt: String? = nil,
        updatedAt: String? = nil,
        clientRequestID: String? = nil
    ) {
        self.id = id
        self.datetime = datetime
        self.compound = compound
        self.dose = dose
        self.units = units
        self.volume = volume
        self.volumeUnits = volumeUnits
        self.route = route
        self.notes = notes
        self.status = status
        self.plannedId = plannedId
        self.scheduleId = scheduleId
        self.completedId = completedId
        self.sourceVial = sourceVial
        self.voided = voided
        self.doseDeviatesFromPlanned = doseDeviatesFromPlanned
        self.volumeBasis = volumeBasis
        self.calcGate = calcGate
        self.concentrationBasis = concentrationBasis
        self.badges = badges
        self.person = person
        self.recordedVia = recordedVia
        self.voidReason = voidReason
        self.correctionHistory = correctionHistory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.clientRequestID = clientRequestID
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(datetime, forKey: .datetime)
        try container.encode(compound, forKey: .compound)
        try container.encodeIfPresent(dose, forKey: .dose)
        try container.encodeIfPresent(units, forKey: .units)
        try container.encodeIfPresent(volume, forKey: .volume)
        try container.encodeIfPresent(volumeUnits, forKey: .volumeUnits)
        try container.encodeIfPresent(route, forKey: .route)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(plannedId, forKey: .plannedId)
        try container.encodeIfPresent(scheduleId, forKey: .scheduleId)
        try container.encodeIfPresent(completedId, forKey: .completedId)
        try container.encodeIfPresent(sourceVial, forKey: .sourceVial)
        try container.encode(voided, forKey: .voided)
        try container.encode(doseDeviatesFromPlanned, forKey: .doseDeviatesFromPlanned)
        try container.encodeIfPresent(volumeBasis, forKey: .volumeBasis)
        try container.encodeIfPresent(calcGate, forKey: .calcGate)
        try container.encodeIfPresent(concentrationBasis, forKey: .concentrationBasis)
        try container.encode(badges, forKey: .badges)
        try container.encodeIfPresent(person, forKey: .person)
        try container.encodeIfPresent(recordedVia, forKey: .recordedVia)
        try container.encodeIfPresent(voidReason, forKey: .voidReason)
        try container.encode(correctionHistory, forKey: .correctionHistory)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(clientRequestID, forKey: .clientRequestID)
    }
}
