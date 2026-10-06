//
//  PeptideLegacyLog.swift
//  calorietracker
//
//  Reads the version-1 peptide log (cached bridge rows, queued writes and
//  device-only details) once, and turns it into on-device records: exactly
//  what the Peptides screens listed, minus the peptide assistant's plans.
//  Read only; nothing here is ever written in this format again.
//

import Foundation

enum PeptideLegacyLog {
    struct Migrated {
        var entries: [PeptideLogEntry]
        var vials: [PeptideVial]
        var schedules: [PeptideUserSchedule]
        /// Saved records that couldn't be read and were left out.
        var skipped: Int
    }

    /// The version-1 log as local records. Nil when the bytes aren't a version-1 log.
    static func migrate(_ data: Data) -> Migrated? {
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data), snapshot.version == 1 else { return nil }
        let rows = Dictionary(
            snapshot.rows.filter { !$0.id.isEmpty }.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let meta = Dictionary(snapshot.meta.map { ($0.key, $0) }, uniquingKeysWith: { _, latest in latest })
        var seen = Set<String>()
        var entries: [PeptideLogEntry] = []
        // The assistant's PLANNED rows were its plans, not doses taken.
        for merged in merge(rows: rows, pendingOps: snapshot.pendingOps, meta: meta) where merged.status == "COMPLETED" {
            let local = merged.local
            guard seen.insert(local.id).inserted else { continue }
            entries.append(local)
        }
        let rowsWithoutID = snapshot.rows.count - rows.count
        return Migrated(
            entries: entries,
            vials: snapshot.vials,
            schedules: snapshot.schedules,
            skipped: snapshot.skipped + max(rowsWithoutID, 0)
        )
    }

    // MARK: Merge (unchanged from the bridge-era store)

    /// One merged row before it becomes a local record.
    private struct Merged {
        var id: String
        var rowID: String?
        var clientRequestID: String?
        var person: String
        var compound: String
        var dose: Double?
        var units: String?
        var date: Date?
        var datetimeRaw: String
        var route: String?
        var notes: String?
        var sourceVial: String?
        /// "COMPLETED" or "PLANNED" (upper-cased).
        var status: String
        var voided: Bool
        var voidReason: String?
        var corrections: [PeptideCorrection]
        var vialID: String?
        var drawnVolume: Double?
        var drawnUnit: String?
        var createdAt: String?

        /// Keyed by the bridge row id, or the client_request_id of a create that never synced.
        var local: PeptideLogEntry {
            PeptideLogEntry(
                id: rowID ?? clientRequestID ?? id,
                person: person,
                compound: compound,
                dose: dose,
                units: units,
                date: date,
                datetimeRaw: datetimeRaw,
                route: route,
                notes: notes,
                sourceVial: sourceVial,
                voided: voided,
                voidReason: voidReason,
                corrections: corrections,
                vialID: vialID,
                drawnVolume: drawnVolume,
                drawnUnit: drawnUnit,
                createdAt: createdAt
            )
        }
    }

    /// Bridge rows merged with queued creates, oldest first.
    private static func merge(
        rows: [String: PeptideAdministration],
        pendingOps: [PeptidePendingOp],
        meta: [String: PeptideLocalMeta]
    ) -> [Merged] {
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
        var result: [Merged] = []
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

    private static func makeEntry(_ row: PeptideAdministration, meta: [String: PeptideLocalMeta]) -> Merged {
        let local = meta[row.clientRequestID?.lowercased() ?? row.id] ?? meta[row.id]
        return Merged(
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
            status: row.status.uppercased(),
            voided: row.voided,
            voidReason: row.voidReason,
            corrections: row.correctionHistory,
            vialID: local?.vialID,
            drawnVolume: local?.drawnVolume,
            drawnUnit: local?.drawnUnit,
            createdAt: row.createdAt
        )
    }

    private static func makePendingEntry(
        _ op: PeptidePendingOp,
        payload: PeptideCreatePayload,
        rows: [String: PeptideAdministration],
        meta: [String: PeptideLocalMeta]
    ) -> Merged {
        let planned = payload.plannedID.flatMap { rows[$0] }
        let local = meta[payload.clientRequestID]
        return Merged(
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
            voided: op.cancelReason != nil,
            voidReason: op.cancelReason,
            corrections: [],
            vialID: local?.vialID,
            drawnVolume: local?.drawnVolume,
            drawnUnit: local?.drawnUnit,
            createdAt: nil
        )
    }

    /// Queued corrections and voids, sent or refused, are applied: the user
    /// made them. Each adds to the correction trail with the user's reason and
    /// the time it was queued, as the bridge would have.
    private static func apply(_ op: PeptidePendingOp, to entry: inout Merged) {
        let before = entry.local
        let at = op.createdAt.map(PeptideMath.iso8601NewYork) ?? ""
        let reason = op.reason ?? ""
        switch op.kind {
        case .create:
            return
        case .correct:
            guard let changes = op.changes else { return }
            let trail = before.corrected(changes, reason: reason, at: at).corrections
            entry.corrections += trail.dropFirst(before.corrections.count)
            if let datetime = changes.datetime {
                entry.date = PeptideMath.parseISO8601(datetime)
                entry.datetimeRaw = datetime
            }
            entry.compound = changes.compound ?? entry.compound
            entry.dose = changes.dose ?? entry.dose
            entry.units = changes.units ?? entry.units
            entry.route = changes.route ?? entry.route
            entry.notes = changes.notes ?? entry.notes
            entry.sourceVial = changes.sourceVial ?? entry.sourceVial
        case .void:
            if !before.voided {
                entry.corrections += before.voiding(reason: reason, at: at).corrections.dropFirst(before.corrections.count)
            }
            entry.voided = true
            entry.voidReason = op.reason
        }
    }

    // MARK: Saved file (version 1)

    struct Snapshot: Decodable {
        var version: Int
        var rows: [PeptideAdministration]
        var pendingOps: [PeptidePendingOp]
        var meta: [PeptideLocalMeta]
        var vials: [PeptideVial]
        var schedules: [PeptideUserSchedule]
        /// List elements that couldn't be read.
        var skipped: Int

        enum CodingKeys: String, CodingKey {
            case version, rows, pendingOps, meta, vials, schedules
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
            skipped = (lossyRows.count - rows.count) + (lossyOps.count - pendingOps.count)
                + (lossyMeta.count - meta.count) + (lossyVials.count - vials.count)
                + (lossySchedules.count - schedules.count)
        }
    }
}

// MARK: - Version-1 records (read only)

/// Device-only details for one administration, keyed by client_request_id
/// (or the bridge row id for rows without one).
nonisolated struct PeptideLocalMeta: Decodable, Equatable {
    var key: String
    var vialID: String?
    var drawnVolume: Double?
    var drawnUnit: String?
}

/// A queued create, as the bridge-era queue saved it.
nonisolated struct PeptideCreatePayload: Decodable, Equatable {
    var clientRequestID: String
    var plannedID: String?
    var datetime: String
    var dose: Double?
    var units: String?
    var compound: String?
    var route: String?
    var notes: String?
    var sourceVial: String?
    var person: String?
}

nonisolated enum PeptidePendingKind: String, Decodable, Equatable {
    case create
    case correct
    case void
}

/// One queued bridge write, as saved.
nonisolated struct PeptidePendingOp: Decodable, Equatable {
    var id: String
    var kind: PeptidePendingKind
    var create: PeptideCreatePayload?
    var rowID: String?
    var reason: String?
    var changes: PeptideCorrectionChanges?
    /// When the user made the change (saved as seconds since 2001).
    var createdAt: Date?
    /// Set when the user removed a create the bridge may already have had.
    var cancelReason: String?
}
